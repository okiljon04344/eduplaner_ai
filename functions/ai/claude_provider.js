import Anthropic from '@anthropic-ai/sdk';
import { defineSecret } from 'firebase-functions/params';
import sharp from 'sharp';
import { ERROR_REASONS } from '../shared/error_reasons.js';
import { AiError, toAiError } from './ai_errors.js';

export const anthropicApiKey = defineSecret('ANTHROPIC_API_KEY');
export const DEFAULT_CLAUDE_MODEL = 'claude-sonnet-5-5';
export const DEFAULT_CLAUDE_LIGHT_MODEL = 'claude-haiku-5-5';
export const CLAUDE_MAX_IMAGE_BASE64_BYTES = 5 * 1024 * 1024;
export const CLAUDE_WEB_SEARCH_TOOL_TYPE = 'web_search_20250305';

const SUPPORTED_CLAUDE_IMAGE_MIMES = new Set([
  'image/jpeg',
  'image/png',
  'image/webp',
  'image/gif',
]);

const DEFAULT_CLAUDE_TIMEOUT_MS = 60_000;

let _client = null;
let _cachedApiKey = null;
let _overrideCreateMessage = null;

/**
 * Allows unit/contract tests to inject a fake `messages.create` implementation
 * so no real network call is made and tests can inspect exact Claude payloads.
 * Pass `null` to reset.
 */
export function setClaudeMessagesCreateForTest(fn) {
  _overrideCreateMessage = fn;
}

function getAnthropicClient(timeoutMs, explicitApiKey) {
  const rawKey = explicitApiKey !== undefined ? explicitApiKey : anthropicApiKey.value();
  const key = String(rawKey ?? '').trim();
  if (!key) {
    throw new AiError({
      kind: 'auth',
      provider: 'claude',
      status: 401,
    });
  }
  if (!_client || _cachedApiKey !== key) {
    _client = new Anthropic({
      apiKey: key,
      maxRetries: 1,
      timeout: timeoutMs ?? DEFAULT_CLAUDE_TIMEOUT_MS,
    });
    _cachedApiKey = key;
  }
  return _client;
}

/**
 * Low-level Anthropic Messages API invocation.
 *
 * Restricted to `functions/ai/` — callers outside `functions/ai/` must go
 * through `privacy/safe_ai.js`.
 */
export async function invokeClaudeCreateMessage(params, reqOpts = {}) {
  if (_overrideCreateMessage) {
    return await _overrideCreateMessage(params, reqOpts);
  }
  const { apiKey, ...sdkReqOpts } = reqOpts;
  const client = getAnthropicClient(sdkReqOpts.timeout, apiKey);
  return await client.messages.create(params, sdkReqOpts);
}

/**
 * Validates Claude 5.5 thinking, effort, and sampling constraints matching the
 * official Anthropic Messages API rules so invalid 400-producing combinations
 * are rejected consistently before hitting the network.
 */
export function validateClaudeThinkingConfig({
  model,
  thinking,
  effort,
  temperature,
  top_p: topP,
  top_k: topK,
}) {
  const modelId = String(model ?? '').toLowerCase();
  const is55Model = modelId.includes('5-5');
  const isSonnet55 = modelId.includes('sonnet-5-5');
  const isHaiku55 = modelId.includes('haiku-5-5');

  if (is55Model && (temperature !== undefined || topP !== undefined || topK !== undefined)) {
    throw new AiError({ kind: 'invalid_request', provider: 'claude', status: 400 });
  }

  if (thinking && typeof thinking === 'object') {
    if (is55Model && (thinking.type === 'enabled' || thinking.budget_tokens !== undefined)) {
      throw new AiError({ kind: 'invalid_request', provider: 'claude', status: 400 });
    }

    if (isSonnet55 && thinking.type === 'disabled') {
      throw new AiError({ kind: 'invalid_request', provider: 'claude', status: 400 });
    }

    if (thinking.type === 'between_tools') {
      if (!isSonnet55) {
        throw new AiError({ kind: 'invalid_request', provider: 'claude', status: 400 });
      }
      if (effort === 'xhigh' || effort === 'max') {
        throw new AiError({ kind: 'invalid_request', provider: 'claude', status: 400 });
      }
      if (
        thinking.display !== undefined ||
        thinking.budget_tokens !== undefined ||
        thinking.block_binding !== undefined
      ) {
        throw new AiError({ kind: 'invalid_request', provider: 'claude', status: 400 });
      }
    }

    if (isHaiku55 && thinking.type === 'disabled' && (effort === 'xhigh' || effort === 'max')) {
      throw new AiError({ kind: 'invalid_request', provider: 'claude', status: 400 });
    }
  }
}

/**
 * Ensures an image block stays under `CLAUDE_MAX_IMAGE_BASE64_BYTES` (5 MB base64).
 * Re-compresses oversized images with `sharp` before failing closed with
 * `AiError({ kind: 'image_too_large_for_provider' })`.
 */
export async function prepareClaudeImageBlock(mimeType, base64Data, maxBase64Bytes = CLAUDE_MAX_IMAGE_BASE64_BYTES) {
  const normalizedMime = SUPPORTED_CLAUDE_IMAGE_MIMES.has(mimeType) ? mimeType : 'image/jpeg';
  const cleanData = String(base64Data ?? '');

  if (cleanData.length <= maxBase64Bytes) {
    return {
      type: 'image',
      source: {
        type: 'base64',
        media_type: normalizedMime,
        data: cleanData,
      },
    };
  }

  const attempts = [
    { maxDim: 1600, quality: 80 },
    { maxDim: 1280, quality: 65 },
    { maxDim: 1024, quality: 50 },
  ];

  try {
    const rawBuf = Buffer.from(cleanData, 'base64');
    for (const attempt of attempts) {
      const compressed = await sharp(rawBuf)
        .resize(attempt.maxDim, attempt.maxDim, { fit: 'inside', withoutEnlargement: true })
        .jpeg({ quality: attempt.quality })
        .toBuffer();
      const reencoded = compressed.toString('base64');
      if (reencoded.length <= maxBase64Bytes) {
        return {
          type: 'image',
          source: {
            type: 'base64',
            media_type: 'image/jpeg',
            data: reencoded,
          },
        };
      }
    }
  } catch {
    // Fall through to fail-closed image_too_large_for_provider below.
  }

  throw new AiError({
    kind: 'image_too_large_for_provider',
    provider: 'claude',
    status: 413,
    reason: ERROR_REASONS.imageTooLargeForProvider,
  });
}

async function toClaudeContentBlocks(parts, maxImageBase64Bytes) {
  const imageBlocks = [];
  const textBlocks = [];

  for (const part of parts) {
    if (typeof part === 'string') {
      if (part.length > 0) {
        textBlocks.push({ type: 'text', text: part });
      }
      continue;
    }
    if (!part || typeof part !== 'object') continue;

    if (part.type === 'text' && typeof part.text === 'string') {
      textBlocks.push({ type: 'text', text: part.text });
    } else if (typeof part.text === 'string' && !part.inlineData && part.type !== 'image') {
      textBlocks.push({ type: 'text', text: part.text });
    } else if (part.type === 'image' && part.mimeType && part.data) {
      imageBlocks.push(
        await prepareClaudeImageBlock(part.mimeType, part.data, maxImageBase64Bytes),
      );
    } else if (part.inlineData?.mimeType && part.inlineData?.data) {
      imageBlocks.push(
        await prepareClaudeImageBlock(
          part.inlineData.mimeType,
          part.inlineData.data,
          maxImageBase64Bytes,
        ),
      );
    }
  }

  // Anthropic Vision best practice: place image blocks before text blocks.
  const combined = [...imageBlocks, ...textBlocks];
  return combined.length > 0 ? combined : [{ type: 'text', text: '' }];
}

async function toClaudeMessages(contents, maxImageBase64Bytes) {
  if (typeof contents === 'string') {
    return [{ role: 'user', content: contents }];
  }
  if (!Array.isArray(contents) || contents.length === 0) {
    return [{ role: 'user', content: '' }];
  }

  const messages = [];
  for (const item of contents) {
    if (typeof item === 'string') {
      messages.push({ role: 'user', content: item });
      continue;
    }
    if (!item || typeof item !== 'object') continue;

    const role = item.role === 'model' || item.role === 'assistant' ? 'assistant' : 'user';
    const rawParts = Array.isArray(item.parts)
      ? item.parts
      : (Array.isArray(item.content) ? item.content : [item]);
    const blocks = await toClaudeContentBlocks(rawParts, maxImageBase64Bytes);

    // Collapse adjacent blocks-only text to a simple string when single text block?
    // Keeping blocks or string both work; merge consecutive same-role messages for strict alternation.
    const prev = messages[messages.length - 1];
    if (prev && prev.role === role) {
      const prevBlocks = Array.isArray(prev.content)
        ? prev.content
        : [{ type: 'text', text: String(prev.content ?? '') }];
      prev.content = [...prevBlocks, ...blocks];
    } else {
      messages.push({ role, content: blocks });
    }
  }

  return messages.length > 0 ? messages : [{ role: 'user', content: '' }];
}

function stripJsonCodeFences(raw) {
  if (typeof raw !== 'string') return '';
  return raw
    .trim()
    .replace(/^```(?:json)?\s*/i, '')
    .replace(/```\s*$/i, '')
    .trim();
}

/**
 * Converts a provider-agnostic [AiRequest] into Anthropic Messages API params.
 *
 * @param {import('./ai_provider.js').AiRequest} aiRequest
 * @param {{ defaultModel?: string, maxImageBase64Bytes?: number }} [opts]
 */
export async function toClaudeSdkParams(
  aiRequest,
  {
    defaultModel = DEFAULT_CLAUDE_MODEL,
    maxImageBase64Bytes = CLAUDE_MAX_IMAGE_BASE64_BYTES,
  } = {},
) {
  const model = aiRequest.model || defaultModel;
  const maxTokens = typeof aiRequest.maxTokens === 'number' ? aiRequest.maxTokens : 2048;
  const claudeOpts = aiRequest.claude ?? aiRequest.providerConfig?.claude ?? {};
  const thinking = aiRequest.thinking ?? claudeOpts.thinking;
  const effort = aiRequest.effort ?? claudeOpts.effort;

  validateClaudeThinkingConfig({
    model,
    thinking,
    effort,
    temperature: aiRequest.temperature ?? aiRequest.providerConfig?.temperature,
    top_p: aiRequest.topP ?? aiRequest.providerConfig?.top_p,
    top_k: aiRequest.topK ?? aiRequest.providerConfig?.top_k,
  });

  const messages = await toClaudeMessages(aiRequest.contents, maxImageBase64Bytes);

  const params = {
    model,
    max_tokens: maxTokens,
    messages,
  };

  if (typeof aiRequest.systemInstruction === 'string' && aiRequest.systemInstruction.length > 0) {
    params.system = aiRequest.systemInstruction;
  }

  if (thinking && typeof thinking === 'object') {
    params.thinking = { ...thinking };
  }

  const outputConfig = {};
  if (typeof effort === 'string' && effort.length > 0) {
    outputConfig.effort = effort;
  }
  if (aiRequest.jsonSchema && typeof aiRequest.jsonSchema === 'object') {
    outputConfig.format = {
      type: 'json_schema',
      schema: aiRequest.jsonSchema,
    };
  }
  if (Object.keys(outputConfig).length > 0) {
    params.output_config = outputConfig;
  }

  if (aiRequest.webSearch) {
    params.tools = [
      {
        type: aiRequest.webSearchType || CLAUDE_WEB_SEARCH_TOOL_TYPE,
        name: 'web_search',
        max_uses: typeof aiRequest.webSearchMaxUses === 'number'
          ? aiRequest.webSearchMaxUses
          : 2,
      },
    ];
  }

  return params;
}

/**
 * Extracts concatenated text from Claude content blocks, rejecting safety
 * refusals (`stop_reason === 'refusal'`) as `AiError({ kind: 'safety_blocked' })`
 * and ignoring non-text blocks (`thinking`, `server_tool_use`, `web_search_tool_result`).
 */
export function extractClaudeText(response, responseFormat) {
  if (response?.stop_reason === 'refusal') {
    throw new AiError({
      kind: 'safety_blocked',
      provider: 'claude',
      status: 200,
    });
  }

  const blocks = Array.isArray(response?.content) ? response.content : [];
  const joined = blocks
    .filter((block) => block && block.type === 'text' && typeof block.text === 'string')
    .map((block) => block.text)
    .join('');

  return responseFormat === 'json' ? stripJsonCodeFences(joined) : joined;
}

/**
 * Creates a Claude `AiProvider` adapter wrapping `@anthropic-ai/sdk`.
 *
 * @param {{ createMessage?: Function, model?: string, maxImageBase64Bytes?: number, apiKey?: string, maxRetries?: number }} [opts]
 * @returns {import('./ai_provider.js').AiProvider}
 */
export function createClaudeProvider({
  createMessage = invokeClaudeCreateMessage,
  model = DEFAULT_CLAUDE_MODEL,
  maxImageBase64Bytes = CLAUDE_MAX_IMAGE_BASE64_BYTES,
  apiKey,
  maxRetries,
} = {}) {
  return {
    name: 'claude',
    async generate(aiRequest) {
      if (apiKey !== undefined && !String(apiKey ?? '').trim()) {
        throw new AiError({
          kind: 'auth',
          provider: 'claude',
          status: 401,
        });
      }

      const params = await toClaudeSdkParams(aiRequest, {
        defaultModel: model,
        maxImageBase64Bytes,
      });
      const timeout = typeof aiRequest.timeoutMs === 'number'
        ? aiRequest.timeoutMs
        : DEFAULT_CLAUDE_TIMEOUT_MS;
      const effectiveMaxRetries = aiRequest.maxRetries ?? maxRetries;

      let rawResponse;
      try {
        const reqOpts = {
          timeout,
          ...(apiKey !== undefined ? { apiKey } : {}),
          ...(effectiveMaxRetries !== undefined ? { maxRetries: effectiveMaxRetries } : {}),
        };
        rawResponse = await createMessage(params, reqOpts);
      } catch (err) {
        throw toAiError(err, 'claude');
      }

      const text = extractClaudeText(rawResponse, aiRequest.responseFormat);
      const usageObj = rawResponse?.usage;
      const usage = usageObj
        ? {
          inputTokens: Number(usageObj.input_tokens ?? 0),
          outputTokens: Number(usageObj.output_tokens ?? 0),
          webSearchCount: Number(usageObj.server_tool_use?.web_search_requests ?? 0),
        }
        : undefined;
      const resolvedModel = rawResponse?.model || params.model;

      if (rawResponse?.stop_reason === 'max_tokens') {
        throw new AiError({
          kind: 'truncated',
          provider: 'claude',
          status: 200,
          partialText: text,
          usage,
          model: resolvedModel,
        });
      }

      return {
        text,
        provider: 'claude',
        model: resolvedModel,
        finishReason: rawResponse?.stop_reason ?? null,
        usage,
      };
    },
  };
}
