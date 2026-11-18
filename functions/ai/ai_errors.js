import { HttpsError } from 'firebase-functions/https';
import { logger } from 'firebase-functions';
import { ERROR_REASONS } from '../shared/error_reasons.js';

/**
 * Normalized provider-agnostic AI error kinds.
 *
 * @typedef {'rate_limited' | 'overloaded' | 'timeout' | 'invalid_request' | 'auth' | 'safety_blocked' | 'image_too_large_for_provider' | 'budget_exceeded' | 'truncated' | 'unknown'} AiErrorKind
 */

const TRANSIENT_KINDS = new Set(['rate_limited', 'overloaded', 'timeout']);

const QUOTA_ERROR_RE = /quota|rate[_\s-]?limit/i;
const API_KEY_AUTH_RE = /api[_\s-]?key[_\s-]?(not[_\s-]?valid|invalid|expired|missing)|API_KEY_INVALID/i;
const INVALID_ARG_ERROR_RE = /invalid|bad request|request_too_large/i;
const UNAVAILABLE_ERROR_RE = /unavailable|timeout|timed out|deadline|connection error|fetch failed|network|econnreset|enotfound|etimedout|econnrefused|eai_again|ehostunreach/i;
const OVERLOADED_ERROR_RE = /overloaded/i;

const SAFE_TOKEN_RE = /^[A-Za-z0-9._-]{1,48}$/;
const SAFE_HOST_RE = /^[a-zA-Z0-9.-]{1,120}$/;

const DEFAULT_PROVIDER_HOSTS = Object.freeze({
  gemini: 'generativelanguage.googleapis.com',
  claude: 'api.anthropic.com',
});

/**
 * Extracts a strictly non-sensitive network/HTTP diagnostic summary from an error.
 * Never copies arbitrary `err.message` text, URLs with query strings, keys, or prompts.
 *
 * @param {unknown} err
 * @param {string} [provider]
 * @returns {{ httpStatus: number | null, errorCode: string | null, errorName: string | null, host: string | null }}
 */
export function extractSafeErrorDiag(err, provider = 'unknown') {
  if (err instanceof AiError) {
    if (err.diag) return err.diag;
    const resolvedProvider = err.provider || provider;
    return {
      httpStatus: typeof err.status === 'number' && Number.isFinite(err.status) ? err.status : null,
      errorCode: err.kind || null,
      errorName: err.kind || 'AiError',
      host: DEFAULT_PROVIDER_HOSTS[resolvedProvider] ?? null,
    };
  }

  const rawStatus = err?.status ?? err?.response?.status;
  const httpStatus = typeof rawStatus === 'number' && Number.isFinite(rawStatus)
    ? rawStatus
    : null;

  const rawCode = err?.cause?.code ?? (typeof err?.code === 'string' ? err.code : null);
  const errorCode = typeof rawCode === 'string' && SAFE_TOKEN_RE.test(rawCode)
    ? rawCode
    : null;

  const rawName = err?.cause?.name ?? err?.name;
  let errorName = typeof rawName === 'string' && SAFE_TOKEN_RE.test(rawName)
    ? rawName
    : null;
  if (!errorCode && /fetch failed/i.test(String(err?.message ?? ''))) {
    errorName = 'fetch failed';
  }

  let host = null;
  const rawHost = err?.cause?.hostname ?? err?.hostname;
  if (typeof rawHost === 'string' && SAFE_HOST_RE.test(rawHost)) {
    host = rawHost.toLowerCase();
  } else {
    const rawUrl = err?.url ?? err?.request?.url ?? err?.config?.url;
    if (typeof rawUrl === 'string' && rawUrl.startsWith('http')) {
      try {
        const parsed = new URL(rawUrl).hostname;
        if (SAFE_HOST_RE.test(parsed)) {
          host = parsed.toLowerCase();
        }
      } catch {
        // ignore invalid URL
      }
    }
  }
  if (!host && provider in DEFAULT_PROVIDER_HOSTS) {
    host = DEFAULT_PROVIDER_HOSTS[provider];
  }

  return { httpStatus, errorCode, errorName, host };
}

/**
 * Provider-agnostic error thrown or returned by AI provider implementations.
 * Never embeds prompts, responses, or raw SDK error messages in `message`
 * so sensitive details cannot leak into logs or client error payloads.
 */
export class AiError extends Error {
  /**
   * @param {Object} params
   * @param {AiErrorKind} params.kind
   * @param {string} [params.provider]
   * @param {number|string|null} [params.status]
   * @param {string|null} [params.reason]
   * @param {string|null} [params.partialText]
   * @param {Object|null} [params.usage]
   * @param {string|null} [params.model]
   * @param {{ httpStatus?: number|null, errorCode?: string|null, errorName?: string|null, host?: string|null }|null} [params.diag]
   */
  constructor({
    kind,
    provider = 'unknown',
    status = null,
    reason = null,
    partialText = null,
    usage = null,
    model = null,
    diag = null,
  }) {
    super(`AI provider error (${provider}: ${kind})`);
    this.name = 'AiError';
    /** @type {AiErrorKind} */
    this.kind = kind;
    this.provider = provider;
    this.status = status;
    this.reason = reason;
    this.partialText = partialText;
    this.usage = usage;
    this.model = model;
    this.diag = diag;
    this.retryable = TRANSIENT_KINDS.has(kind);
  }
}

/**
 * Returns true if the error represents a transient provider condition where
 * a fallback attempt on another provider with the same masked request is safe.
 *
 * @param {unknown} err
 * @returns {boolean}
 */
export function isTransientAiError(err) {
  if (err instanceof AiError) {
    return TRANSIENT_KINDS.has(err.kind);
  }
  const kind = classifyRawAiError(err);
  return TRANSIENT_KINDS.has(kind);
}

/**
 * Classifies a raw SDK or HTTP-like error into a normalized [AiErrorKind]
 * without exposing raw error text.
 *
 * @param {unknown} err
 * @returns {AiErrorKind}
 */
export function classifyRawAiError(err) {
  if (!err) return 'unknown';
  if (err instanceof AiError) return err.kind;

  const status = err?.status ?? err?.response?.status ?? err?.code;
  const causeCode = String(err?.cause?.code ?? err?.code ?? '');
  const causeName = String(err?.cause?.name ?? '');
  const name = String(err?.name ?? '');
  const type = String(err?.type ?? err?.error?.type ?? '');
  const message = String(err?.message ?? '');

  // Check explicit HTTP status codes & SDK error names/types first so words like
  // "invalid" inside a 401 auth error message do not shadow auth status codes.
  if (status === 429 || name === 'RateLimitError' || type === 'rate_limit_error') {
    return 'rate_limited';
  }
  if (
    status === 529 ||
    status === 503 ||
    name === 'OverloadedError' ||
    name === 'ServiceUnavailableError' ||
    type === 'overloaded_error'
  ) {
    return 'overloaded';
  }
  if (
    status === 408 ||
    status === 504 ||
    name === 'APIConnectionTimeoutError' ||
    name === 'RequestTimeoutError' ||
    name === 'GatewayTimeoutError' ||
    name === 'APIConnectionError' ||
    name === 'AbortError' ||
    causeName === 'ConnectTimeoutError' ||
    type === 'timeout_error' ||
    /^(ENOTFOUND|ECONNRESET|ETIMEDOUT|ECONNREFUSED|EAI_AGAIN|EHOSTUNREACH|UND_ERR_CONNECT_TIMEOUT|UND_ERR_HEADERS_TIMEOUT|UND_ERR_BODY_TIMEOUT|ABORT_ERR)$/.test(causeCode)
  ) {
    return 'timeout';
  }
  if (
    status === 401 ||
    status === 403 ||
    name === 'AuthenticationError' ||
    name === 'PermissionDeniedError' ||
    type === 'authentication_error' ||
    type === 'permission_error' ||
    API_KEY_AUTH_RE.test(message)
  ) {
    return 'auth';
  }
  if (
    status === 400 ||
    status === 413 ||
    status === 422 ||
    name === 'BadRequestError' ||
    name === 'ContentTooLargeError' ||
    name === 'UnprocessableEntityError' ||
    type === 'invalid_request_error' ||
    type === 'request_too_large'
  ) {
    return 'invalid_request';
  }

  // Fallback message heuristics only when structured status/name/type is absent.
  if (QUOTA_ERROR_RE.test(message)) return 'rate_limited';
  if (OVERLOADED_ERROR_RE.test(message)) return 'overloaded';
  if (UNAVAILABLE_ERROR_RE.test(message)) return 'timeout';
  if (INVALID_ARG_ERROR_RE.test(message)) return 'invalid_request';
  return 'unknown';
}

/**
 * Wraps an arbitrary error into an [AiError] instance (returning it unchanged
 * if it is already an [AiError] or [HttpsError]).
 *
 * @param {unknown} err
 * @param {string} [provider]
 * @returns {AiError | HttpsError}
 */
export function toAiError(err, provider = 'unknown') {
  if (err instanceof HttpsError || err instanceof AiError) {
    return err;
  }
  const diag = extractSafeErrorDiag(err, provider);
  const status = diag.httpStatus ?? err?.cause?.code ?? err?.code ?? null;
  const kind = classifyRawAiError(err);
  const reason = kind === 'rate_limited' && provider === 'gemini'
    ? ERROR_REASONS.aiTemporarilyUnavailable
    : null;
  return new AiError({
    kind,
    provider,
    status,
    reason,
    diag,
  });
}

/**
 * Maps any AI / SDK error into an [HttpsError] with a localized client-safe
 * message. Never lets raw SDK error text (prompt fragments, URLs, stack
 * traces) reach the client or logs.
 *
 * @param {unknown} err
 * @param {string} japaneseFallback
 * @param {{ provider?: string }} [opts]
 * @returns {HttpsError}
 */
export function mapAiError(err, japaneseFallback, opts = {}) {
  if (err instanceof HttpsError) {
    return err;
  }

  const aiErr = err instanceof AiError
    ? err
    : new AiError({
      kind: classifyRawAiError(err),
      provider: opts.provider ?? 'unknown',
      status: err?.status ?? err?.response?.status ?? err?.code ?? 'UNKNOWN',
    });

  logger.error('AI call failed', {
    provider: aiErr.provider,
    kind: aiErr.kind,
    status: aiErr.status ?? 'UNKNOWN',
  });

  switch (aiErr.kind) {
    case 'budget_exceeded':
      return new HttpsError(
        'resource-exhausted',
        '今月のAI利用予算に達しました。次の期間に再度お試しください。',
        { reason: aiErr.reason || ERROR_REASONS.aiBudgetExceeded },
      );
    case 'rate_limited': {
      const reason = aiErr.reason || (aiErr.provider === 'gemini'
        ? ERROR_REASONS.aiTemporarilyUnavailable
        : null);
      return new HttpsError(
        'resource-exhausted',
        'AIの利用上限に達しました。しばらくしてからもう一度お試しください。',
        ...(reason ? [{ reason }] : []),
      );
    }
    case 'image_too_large_for_provider':
      return new HttpsError(
        'invalid-argument',
        'ファイルサイズが大きすぎます。10MB以下のファイルをお試しください。',
        { reason: aiErr.reason || ERROR_REASONS.imageTooLargeForProvider },
      );
    case 'invalid_request':
      return new HttpsError('invalid-argument', '入力内容を確認してください。');
    case 'overloaded':
    case 'timeout': {
      const reason = aiErr.reason || ERROR_REASONS.aiTemporarilyUnavailable;
      return new HttpsError(
        'unavailable',
        'AIサーバーが混雑しています。少し時間をおいてお試しください。',
        { reason },
      );
    }
    case 'truncated':
    case 'auth':
    case 'safety_blocked':
    case 'unknown':
    default:
      return new HttpsError('internal', japaneseFallback);
  }
}

/**
 * Backwards-compatible alias for `mapAiError`.
 *
 * @deprecated Use `mapAiError` instead.
 */
export function mapGeminiError(err, japaneseFallback) {
  return mapAiError(err, japaneseFallback, { provider: 'gemini' });
}
