import { createGeminiProvider, DEFAULT_GEMINI_MODEL, geminiApiKey } from './gemini_provider.js';
import {
  anthropicApiKey,
  createClaudeProvider,
  DEFAULT_CLAUDE_MODEL,
} from './claude_provider.js';
import { resolveActiveProviderName } from './ai_config.js';
import { AiError } from './ai_errors.js';

export { geminiApiKey, anthropicApiKey, DEFAULT_GEMINI_MODEL, DEFAULT_CLAUDE_MODEL };

/**
 * @typedef {Object} AiTextPart
 * @property {'text'} type
 * @property {string} text
 */

/**
 * @typedef {Object} AiImagePart
 * @property {'image'} type
 * @property {string} mimeType
 * @property {string} data
 */

/**
 * @typedef {Object} AiMessage
 * @property {'user' | 'assistant' | 'model'} role
 * @property {Array<AiTextPart | AiImagePart | string | Object>} parts
 */

/**
 * @typedef {Object} AiRequest
 * @property {string} [task]
 * @property {string} [model]
 * @property {string} [systemInstruction]
 * @property {string | Array<AiMessage | Object>} contents
 * @property {'text' | 'json'} [responseFormat]
 * @property {Object} [jsonSchema]
 * @property {boolean} [webSearch]
 * @property {string} [webSearchType]
 * @property {number} [webSearchMaxUses]
 * @property {number} [maxTokens]
 * @property {number} [timeoutMs]
 * @property {{ type: 'adaptive' | 'between_tools' | 'disabled' }} [thinking]
 * @property {'low' | 'medium' | 'high' | 'xhigh' | 'max'} [effort]
 * @property {Object} [providerConfig]
 */

/**
 * @typedef {Object} AiUsage
 * @property {number} inputTokens
 * @property {number} outputTokens
 * @property {number} [webSearchCount]
 */

/**
 * @typedef {Object} AiResponse
 * @property {string} text
 * @property {string} provider
 * @property {string} model
 * @property {string | null} [finishReason]
 * @property {AiUsage} [usage]
 */

/**
 * @typedef {Object} AiProvider
 * @property {string} name
 * @property {(request: AiRequest) => Promise<AiResponse>} generate
 */

/**
 * Returns the Firebase Secret definitions required by all AI providers.
 */
export function getAiSecrets() {
  return [geminiApiKey, anthropicApiKey];
}

/**
 * Resolves the active [AiProvider] (`'gemini'` or `'claude'`) from an explicit
 * `providerName` or the `AI_PROVIDER` Firebase parameter.
 *
 * @param {{ providerName?: string, generateContent?: Function, createMessage?: Function, model?: string, apiKey?: string }} [opts]
 * @returns {AiProvider}
 */
export function getProvider({
  providerName,
  generateContent,
  createMessage,
  model,
  apiKey,
} = {}) {
  const resolved = resolveActiveProviderName(providerName);
  if (resolved === 'gemini') {
    return createGeminiProvider({ generateContent, model, apiKey });
  }
  if (resolved === 'claude') {
    return createClaudeProvider({ createMessage, model, apiKey });
  }
  throw new AiError({
    kind: 'invalid_request',
    provider: String(resolved),
    status: 400,
  });
}
