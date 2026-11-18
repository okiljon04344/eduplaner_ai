import { defineString } from 'firebase-functions/params';
import { AiError } from './ai_errors.js';

export const VALID_AI_PROVIDERS = Object.freeze(['gemini', 'claude']);
export const VALID_FALLBACK_PROVIDERS = Object.freeze(['none', 'gemini', 'claude']);

export const AI_TRUNCATED_RETRY_MULTIPLIER = 1.5;
export const AI_MAX_RETRY_TOKENS_CEILING = 8192;

export const aiProviderParam = defineString('AI_PROVIDER', {
  default: 'gemini',
  description: 'Active AI provider: gemini or claude',
});

export const aiFallbackProviderParam = defineString('AI_FALLBACK_PROVIDER', {
  default: 'none',
  description: "Transient-error fallback provider: 'none', 'gemini', or 'claude'",
});

export const aiModelGeminiParam = defineString('AI_MODEL_GEMINI', {
  default: 'gemini-flash-latest',
  description: 'Gemini model ID used across AI tasks',
});

export const aiModelClaudeParam = defineString('AI_MODEL_CLAUDE', {
  default: 'claude-sonnet-5-5',
  description: 'Primary Claude model ID for standard/complex tasks',
});

export const aiModelClaudeLightParam = defineString('AI_MODEL_CLAUDE_LIGHT', {
  default: 'claude-haiku-5-5',
  description: 'Light Claude model ID for low-cost short tasks',
});

export const aiMonthlyBudgetUsdParam = defineString('AI_MONTHLY_BUDGET_USD', {
  default: '0',
  description: 'Monthly estimated USD budget cap (0 or empty disables budget auto-routing)',
});

/**
 * Model & tool pricing table (USD per 1M tokens and USD per 1,000 searches).
 * Kept in central config rather than handler code so rate updates are one edit.
 *
 * Official Anthropic Claude 5.5 rates (`platform.claude.com/docs/en/about-claude/pricing`):
 *   - claude-sonnet-5-5: $2 / MTok input, $10 / MTok output
 *   - claude-haiku-5-5 (<=100k prompts): $0.10 / MTok input, $0.50 / MTok output
 *   - web_search tool: $10 / 1,000 searches ($0.01 / request)
 */
export const AI_PRICING_CONFIG = Object.freeze({
  'claude-sonnet-5-5': Object.freeze({
    inputPerMTok: 2.0,
    outputPerMTok: 10.0,
    webSearchPer1k: 10.0,
  }),
  'claude-haiku-5-5': Object.freeze({
    inputPerMTok: 0.1,
    outputPerMTok: 0.5,
    webSearchPer1k: 10.0,
  }),
  'gemini-flash-latest': Object.freeze({
    inputPerMTok: 0.3,
    outputPerMTok: 2.5,
    webSearchPer1k: 0,
  }),
});

/**
 * Calculates estimated USD cost for a single AI response using `AI_PRICING_CONFIG`.
 *
 * @param {{ provider?: string, model?: string, usage?: { inputTokens?: number, outputTokens?: number, webSearchCount?: number } }} params
 * @returns {number}
 */
export function calculateRequestCostUsd({ provider = 'gemini', model = '', usage = {} }) {
  const normalizedModel = String(model || '').trim();
  const rate =
    AI_PRICING_CONFIG[normalizedModel] ??
    (provider === 'claude'
      ? (normalizedModel.includes('haiku')
          ? AI_PRICING_CONFIG['claude-haiku-5-5']
          : AI_PRICING_CONFIG['claude-sonnet-5-5'])
      : AI_PRICING_CONFIG['gemini-flash-latest']);

  const inputTokens = Math.max(0, Number(usage?.inputTokens ?? 0) || 0);
  const outputTokens = Math.max(0, Number(usage?.outputTokens ?? 0) || 0);
  const webSearchCount = Math.max(0, Number(usage?.webSearchCount ?? 0) || 0);

  const inputCost = (inputTokens / 1_000_000) * rate.inputPerMTok;
  const outputCost = (outputTokens / 1_000_000) * rate.outputPerMTok;
  const searchCost = (webSearchCount / 1_000) * (rate.webSearchPer1k ?? 0);

  return inputCost + outputCost + searchCost;
}

/**
 * Structured JSON Schema prepared for timetable AI fallback (`output_config.format`
 * on Claude when `structuredOutputEnabled` is turned on). Disabled by default so
 * prompt + `extractJson` + validator parity works identically across providers.
 */
export const TIMETABLE_STRUCTURED_SCHEMA = Object.freeze({
  type: 'object',
  properties: {
    slots: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          date: { type: 'string' },
          dayOfWeek: { type: 'string' },
          period: { type: 'string' },
          subject: { type: 'string' },
          teacher: { type: 'string' },
          room: { type: 'string' },
          note: { type: 'string' },
          status: { type: 'string' },
        },
        required: ['period', 'subject'],
        additionalProperties: false,
      },
    },
  },
  required: ['slots'],
  additionalProperties: false,
});

/**
 * Maps `chatWithTutor` bot IDs to distinct task profiles when starting a
 * fresh single-turn call (e.g. home screen `aiStudyTip` uses `botId: 'focus'`).
 * Edit this map to reassign bots without touching handler logic.
 */
export const AI_CHAT_BOT_TASK_OVERRIDES = Object.freeze({
  focus: 'aiStudyTip',
});

/**
 * Single centralized configuration table for all AI-backed functions.
 *
 * `modelTier`:
 *   - `'light'` -> `AI_MODEL_CLAUDE_LIGHT` (`claude-haiku-5-5`) / `AI_MODEL_GEMINI`
 *   - `'main'`  -> `AI_MODEL_CLAUDE` (`claude-sonnet-5-5`) / `AI_MODEL_GEMINI`
 *
 * Anthropic API docs note: adaptive thinking tokens count toward `max_tokens`.
 * Tasks using `thinking: { type: 'adaptive' }` therefore allocate extra
 * headroom (e.g., 2560 / 3072 / 4096) so reasoning + final JSON/text fit
 * cleanly without `stop_reason: 'max_tokens'` truncation.
 */
export const AI_TASK_CONFIG = Object.freeze({
  aiStudyTip: Object.freeze({
    modelTier: 'light',
    maxTokens: 300,
    timeoutMs: 20_000,
    allowFallbackToFreeTier: true,
    claude: Object.freeze({
      thinking: Object.freeze({ type: 'disabled' }),
      effort: 'low',
    }),
  }),
  analyzeWeakArea: Object.freeze({
    modelTier: 'light',
    maxTokens: 500,
    timeoutMs: 30_000,
    allowFallbackToFreeTier: true,
    claude: Object.freeze({
      thinking: Object.freeze({ type: 'disabled' }),
      effort: 'low',
    }),
  }),
  chatWithTutor: Object.freeze({
    modelTier: 'main',
    maxTokens: 2560,
    timeoutMs: 45_000,
    allowFallbackToFreeTier: true,
    claude: Object.freeze({
      thinking: Object.freeze({ type: 'adaptive' }),
      effort: 'low',
    }),
  }),
  'generateQuiz:grounding': Object.freeze({
    modelTier: 'main',
    maxTokens: 3072,
    timeoutMs: 45_000,
    allowFallbackToFreeTier: true,
    webSearch: true,
    webSearchType: 'web_search_20250305',
    webSearchMaxUses: 2,
    claude: Object.freeze({
      thinking: Object.freeze({ type: 'adaptive' }),
      effort: 'medium',
    }),
  }),
  generateQuiz: Object.freeze({
    modelTier: 'main',
    maxTokens: 4096,
    timeoutMs: 60_000,
    allowFallbackToFreeTier: true,
    responseFormat: 'json',
    claude: Object.freeze({
      thinking: Object.freeze({ type: 'adaptive' }),
      effort: 'medium',
    }),
  }),
  analyzeAssignmentSubmission: Object.freeze({
    modelTier: 'main',
    maxTokens: 4096,
    timeoutMs: 50_000,
    allowFallbackToFreeTier: false,
    responseFormat: 'json',
    claude: Object.freeze({
      thinking: Object.freeze({ type: 'adaptive' }),
      effort: 'medium',
    }),
  }),
  previewTimetableImport: Object.freeze({
    modelTier: 'main',
    maxTokens: 4096,
    timeoutMs: 60_000,
    allowFallbackToFreeTier: false,
    responseFormat: 'json',
    structuredOutputEnabled: false,
    jsonSchema: TIMETABLE_STRUCTURED_SCHEMA,
    claude: Object.freeze({
      thinking: Object.freeze({ type: 'adaptive' }),
      effort: 'low',
    }),
  }),
});

/**
 * Resolves the active AI provider name from an explicit override or the
 * `AI_PROVIDER` Firebase parameter. Throws an `AiError('invalid_request')`
 * if an unsupported provider is configured.
 *
 * @param {string} [overrideName]
 * @returns {'gemini' | 'claude'}
 */
export function resolveActiveProviderName(overrideName) {
  const raw = overrideName !== undefined && overrideName !== null && overrideName !== ''
    ? String(overrideName)
    : String(aiProviderParam.value() || 'gemini');
  const normalized = raw.trim().toLowerCase();
  if (!VALID_AI_PROVIDERS.includes(normalized)) {
    throw new AiError({
      kind: 'invalid_request',
      provider: normalized || 'unknown',
      status: 400,
    });
  }
  return /** @type {'gemini' | 'claude'} */ (normalized);
}

/**
 * Resolves the transient-error fallback provider (`'none' | 'gemini' | 'claude'`).
 *
 * @param {string} [overrideName]
 * @returns {'none' | 'gemini' | 'claude'}
 */
export function resolveFallbackProviderName(overrideName) {
  const raw = overrideName !== undefined && overrideName !== null && overrideName !== ''
    ? String(overrideName)
    : String(aiFallbackProviderParam.value() || 'none');
  const normalized = raw.trim().toLowerCase();
  if (!VALID_FALLBACK_PROVIDERS.includes(normalized)) {
    throw new AiError({
      kind: 'invalid_request',
      provider: normalized || 'unknown',
      status: 400,
    });
  }
  return /** @type {'none' | 'gemini' | 'claude'} */ (normalized);
}

/**
 * Resolves the configured monthly USD budget cap (`0` = disabled).
 *
 * @param {number|string} [overrideBudget]
 * @returns {number}
 */
export function resolveMonthlyBudgetUsd(overrideBudget) {
  const raw = overrideBudget !== undefined && overrideBudget !== null && overrideBudget !== ''
    ? overrideBudget
    : aiMonthlyBudgetUsdParam.value();
  const parsed = Number(raw);
  if (!Number.isFinite(parsed) || parsed <= 0) return 0;
  return parsed;
}

/**
 * Resolves the task key for `chatWithTutor` based on `botId` and `history`.
 *
 * @param {string} botId
 * @param {unknown} history
 * @returns {string}
 */
export function resolveChatTask(botId, history) {
  const hasHistory = Array.isArray(history) && history.length > 0;
  if (!hasHistory && typeof botId === 'string' && botId in AI_CHAT_BOT_TASK_OVERRIDES) {
    return AI_CHAT_BOT_TASK_OVERRIDES[botId];
  }
  return 'chatWithTutor';
}

/**
 * Resolves model ID and provider-specific task settings from `AI_TASK_CONFIG`
 * and Firebase params for the given `task` and `providerName`.
 *
 * @param {string} [task]
 * @param {'gemini' | 'claude'} [providerName]
 * @param {{ structuredOutputEnabled?: boolean }} [overrides]
 */
export function resolveTaskSettings(task, providerName = 'gemini', overrides = {}) {
  const cfg = task && task in AI_TASK_CONFIG ? AI_TASK_CONFIG[task] : null;
  const modelTier = cfg?.modelTier === 'light' ? 'light' : 'main';

  let model;
  if (providerName === 'claude') {
    model = modelTier === 'light'
      ? (aiModelClaudeLightParam.value() || 'claude-haiku-5-5')
      : (aiModelClaudeParam.value() || 'claude-sonnet-5-5');
  } else {
    model = aiModelGeminiParam.value() || 'gemini-flash-latest';
  }

  const useStructuredSchema = overrides.structuredOutputEnabled ??
    cfg?.structuredOutputEnabled ??
    false;

  return {
    task: task ?? null,
    modelTier,
    model,
    maxTokens: cfg?.maxTokens,
    timeoutMs: cfg?.timeoutMs,
    allowFallbackToFreeTier: cfg ? Boolean(cfg.allowFallbackToFreeTier) : false,
    responseFormat: cfg?.responseFormat,
    webSearch: cfg?.webSearch,
    webSearchType: cfg?.webSearchType,
    webSearchMaxUses: cfg?.webSearchMaxUses,
    jsonSchema: useStructuredSchema ? cfg?.jsonSchema : undefined,
    claude: cfg?.claude ?? null,
  };
}
