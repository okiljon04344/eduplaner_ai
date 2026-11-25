import { GoogleGenAI } from '@google/genai';
import { defineSecret } from 'firebase-functions/params';
import { ERROR_REASONS } from '../shared/error_reasons.js';
import { AiError, classifyRawAiError, toAiError } from './ai_errors.js';

export const geminiApiKey = defineSecret('GEMINI_API_KEY');
export const DEFAULT_GEMINI_MODEL = 'gemini-flash-latest';

let _ai;
let _cachedGeminiApiKey = null;
let _overrideGenerateContent = null;

/**
 * Allows unit tests to inject a fake `generateContent` implementation so no
 * real network call is made and tests can inspect the masked `contents`
 * delivered to Gemini. Pass `null` to reset.
 */
export function setGeminiGenerateContentForTest(fn) {
  _overrideGenerateContent = fn;
}

/**
 * Low-level Gemini `generateContent` invocation.
 *
 * Restricted to `functions/ai/` — feature handlers in `functions/index.js`
 * and `functions/school/` must call `callAiSafely` instead of invoking the SDK directly.
 */
export async function invokeGeminiGenerateContent(config, explicitApiKey, httpOpts = null) {
  if (_overrideGenerateContent) {
    return await _overrideGenerateContent(config);
  }
  const rawKey = explicitApiKey !== undefined ? explicitApiKey : geminiApiKey.value();
  const key = String(rawKey ?? '').trim();
  if (!key) {
    throw new AiError({
      kind: 'auth',
      provider: 'gemini',
      status: 401,
    });
  }
  if (!_ai || _cachedGeminiApiKey !== key) {
    _ai = new GoogleGenAI({ apiKey: key });
    _cachedGeminiApiKey = key;
  }
  if (httpOpts && (httpOpts.timeout !== undefined || httpOpts.retryOptions !== undefined)) {
    const nextConfig = {
      ...config,
      config: {
        ...(config.config ?? {}),
        httpOptions: {
          ...(config.config?.httpOptions ?? {}),
          ...(httpOpts.timeout !== undefined ? { timeout: httpOpts.timeout } : {}),
          ...(httpOpts.retryOptions !== undefined ? { retryOptions: httpOpts.retryOptions } : {}),
        },
      },
    };
    return await _ai.models.generateContent(nextConfig);
  }
  return await _ai.models.generateContent(config);
}

function toGeminiParts(parts) {
  if (!Array.isArray(parts)) return parts;
  return parts.map((part) => {
    if (typeof part === 'string') return { text: part };
    if (!part || typeof part !== 'object') return part;
    if (part.type === 'text' && typeof part.text === 'string') {
      return { text: part.text };
    }
    if (part.type === 'image' && part.mimeType && part.data) {
      return { inlineData: { mimeType: part.mimeType, data: part.data } };
    }
    return part;
  });
}

function toGeminiContents(contents) {
  if (typeof contents === 'string') return contents;
  if (!Array.isArray(contents)) return contents;
  return contents.map((item) => {
    if (!item || typeof item !== 'object') return item;
    if (Array.isArray(item.parts)) {
      return {
        ...item,
        role: item.role === 'assistant' ? 'model' : item.role,
        parts: toGeminiParts(item.parts),
      };
    }
    return item;
  });
}

/**
 * Users are school students: block at the strictest standard threshold instead
 * of the API default. A blocked reply comes back with empty text, which every
 * caller already treats as a failed generation. (Ported from the pre-pilot
 * audit, commit 51ea899.)
 */
export const GEMINI_SAFETY_SETTINGS = Object.freeze([
  'HARM_CATEGORY_HARASSMENT',
  'HARM_CATEGORY_HATE_SPEECH',
  'HARM_CATEGORY_SEXUALLY_EXPLICIT',
  'HARM_CATEGORY_DANGEROUS_CONTENT',
].map((category) => Object.freeze({ category, threshold: 'BLOCK_LOW_AND_ABOVE' })));

/**
 * Converts a provider-agnostic [AiRequest] into the configuration expected by
 * `@google/genai`'s `models.generateContent`.
 *
 * @param {import('./ai_provider.js').AiRequest} aiRequest
 * @param {string} [defaultModel]
 */
export function toGeminiSdkConfig(aiRequest, defaultModel = DEFAULT_GEMINI_MODEL) {
  const model = aiRequest.model || defaultModel;
  const contents = toGeminiContents(aiRequest.contents);
  const config = {
    ...(aiRequest.providerConfig ?? {}),
    safetySettings: GEMINI_SAFETY_SETTINGS.map((s) => ({ ...s })),
  };

  if (aiRequest.systemInstruction !== undefined) {
    config.systemInstruction = aiRequest.systemInstruction;
  }
  if (aiRequest.responseFormat === 'json') {
    config.responseMimeType = 'application/json';
  }
  if (aiRequest.webSearch) {
    config.tools = [{ googleSearch: {} }];
  }
  if (typeof aiRequest.explicitMaxTokens === 'number') {
    config.maxOutputTokens = aiRequest.explicitMaxTokens;
  }

  return { model, contents, config };
}

/**
 * Creates a Gemini `AiProvider` adapter wrapping `@google/genai`.
 *
 * @param {{ generateContent?: Function, model?: string, apiKey?: string, maxRetries?: number }} [opts]
 * @returns {import('./ai_provider.js').AiProvider}
 */
export function createGeminiProvider({
  generateContent = invokeGeminiGenerateContent,
  model = DEFAULT_GEMINI_MODEL,
  apiKey,
  maxRetries,
} = {}) {
  return {
    name: 'gemini',
    async generate(aiRequest) {
      if (apiKey !== undefined && !String(apiKey ?? '').trim()) {
        throw new AiError({
          kind: 'auth',
          provider: 'gemini',
          status: 401,
        });
      }

      const sdkConfig = toGeminiSdkConfig(aiRequest, model);
      const effectiveMaxRetries = Math.min(1, Math.max(0, Number(aiRequest.maxRetries ?? maxRetries ?? 1)));
      const effectiveTimeout = typeof aiRequest.timeoutMs === 'number'
        ? aiRequest.timeoutMs
        : undefined;
      const isDefaultInvoke =
        generateContent === invokeGeminiGenerateContent && !_overrideGenerateContent;
      const retryDelayMs = typeof aiRequest.retryDelayMs === 'number'
        ? aiRequest.retryDelayMs
        : (isDefaultInvoke ? 500 : 0);

      let rawResponse;
      try {
        if (isDefaultInvoke) {
          const httpOpts = {
            ...(effectiveTimeout !== undefined ? { timeout: effectiveTimeout } : {}),
            retryOptions: { attempts: Math.max(1, effectiveMaxRetries + 1) },
          };
          rawResponse = await generateContent(sdkConfig, apiKey, httpOpts);
        } else {
          const invokeMock = () => (
            apiKey !== undefined
              ? generateContent(sdkConfig, apiKey)
              : generateContent(sdkConfig)
          );
          try {
            rawResponse = await invokeMock();
          } catch (firstErr) {
            if (classifyRawAiError(firstErr) === 'rate_limited' && effectiveMaxRetries >= 1) {
              if (retryDelayMs > 0) {
                await new Promise((r) => setTimeout(r, retryDelayMs));
              }
              try {
                rawResponse = await invokeMock();
              } catch (retryErr) {
                if (classifyRawAiError(retryErr) === 'rate_limited') {
                  throw new AiError({
                    kind: 'rate_limited',
                    provider: 'gemini',
                    status: 429,
                    reason: ERROR_REASONS.aiTemporarilyUnavailable,
                  });
                }
                throw retryErr;
              }
            } else {
              throw firstErr;
            }
          }
        }
      } catch (err) {
        if (err instanceof AiError) {
          throw err;
        }
        if (_overrideGenerateContent || generateContent !== invokeGeminiGenerateContent) {
          // Preserve raw error object when callers pass an explicit test mock
          // that expects its own error or mapError handling.
          throw err;
        }
        throw toAiError(err, 'gemini');
      }

      const finishReason = rawResponse?.candidates?.[0]?.finishReason ?? null;
      const rawText = typeof rawResponse?.text === 'string' ? rawResponse.text : '';
      if ((finishReason === 'SAFETY' || finishReason === 'RECITATION') && !rawText) {
        throw new AiError({ kind: 'safety_blocked', provider: 'gemini' });
      }

      const usageMeta = rawResponse?.usageMetadata;
      const usage = usageMeta
        ? {
          inputTokens: Number(usageMeta.promptTokenCount ?? 0),
          outputTokens: Number(usageMeta.candidatesTokenCount ?? 0),
          webSearchCount: 0,
        }
        : undefined;

      if (finishReason === 'MAX_TOKENS') {
        throw new AiError({
          kind: 'truncated',
          provider: 'gemini',
          status: 200,
          partialText: rawText,
          usage,
          model: sdkConfig.model,
        });
      }

      return {
        text: rawText,
        provider: 'gemini',
        model: sdkConfig.model,
        finishReason,
        usage,
      };
    },
  };
}
