import { HttpsError } from 'firebase-functions/https';
import { logger } from 'firebase-functions';
import { MaskingSession } from './masking_session.js';
import {
  DEFAULT_HONORIFIC_EXCEPTIONS,
  compileRoster,
  maskText,
} from './anonymizer_service.js';
import { loadPeopleForCaller } from './people_loader.js';
import { getProvider } from '../ai/ai_provider.js';
import {
  AI_MAX_RETRY_TOKENS_CEILING,
  AI_TRUNCATED_RETRY_MULTIPLIER,
  resolveActiveProviderName,
  resolveFallbackProviderName,
  resolveTaskSettings,
} from '../ai/ai_config.js';
import {
  AiError,
  classifyRawAiError,
  isTransientAiError,
} from '../ai/ai_errors.js';
import {
  recordMonthlyUsageAndCheckBudget,
  resolveProviderWithBudget,
} from '../ai/ai_budget.js';
import {
  defaultSchoolPolicy,
  loadSchoolPolicyForAuth,
} from '../school/policy.js';
import { ERROR_REASONS } from '../shared/error_reasons.js';

export const PRIVACY_TOKEN_INSTRUCTION =
  '[STUDENT_1], [TEACHER_1], [PERSON_1], [EMAIL_1], [PHONE_1], [POSTAL_1], [STUDENT_ID_1] ' +
  'such bracketed tokens represent anonymized people or personal information. ' +
  'Keep every token in its exact bracketed form (do not translate, alter, split, or remove brackets), ' +
  'and never attempt to guess or fabricate the real underlying name or value.';

const PEOPLE_LOAD_TIMEOUT_MS = 10_000;

function withTimeout(promise, ms) {
  let timer;
  const timeoutPromise = new Promise((_, reject) => {
    timer = setTimeout(() => {
      reject(new Error(`People roster load timed out after ${ms}ms`));
    }, ms);
  });
  return Promise.race([promise, timeoutPromise]).finally(() => {
    clearTimeout(timer);
  });
}

/**
 * Recursively masks all text segments inside AI `contents` in order using
 * a single [MaskingSession], while passing binary/image parts (`inlineData`,
 * `type: 'image'`) through untouched.
 */
export function maskAiContents(contents, maskFn) {
  if (typeof contents === 'string') {
    return maskFn(contents);
  }
  if (Array.isArray(contents)) {
    return contents.map((item) => maskAiContents(item, maskFn));
  }
  if (contents && typeof contents === 'object') {
    const out = { ...contents };
    if (typeof out.text === 'string') {
      out.text = maskFn(out.text);
    }
    if (Array.isArray(out.parts)) {
      out.parts = out.parts.map((part) => {
        if (typeof part === 'string') return maskFn(part);
        if (part && typeof part === 'object') {
          if (typeof part.text === 'string') {
            return { ...part, text: maskFn(part.text) };
          }
          // `inlineData` / `{ type: 'image' }` bytes are intentionally left
          // untouched here; image redaction happens upstream in `redactImageForAi`.
          return { ...part };
        }
        return part;
      });
    }
    return out;
  }
  return contents;
}

/**
 * @deprecated Use `maskAiContents` instead.
 */
export const maskGeminiContents = maskAiContents;

export function prependPrivacySystemInstruction(existingInstruction) {
  if (!existingInstruction) return PRIVACY_TOKEN_INSTRUCTION;
  if (typeof existingInstruction === 'string') {
    if (existingInstruction.includes('[STUDENT_1]')) return existingInstruction;
    return `${PRIVACY_TOKEN_INSTRUCTION}\n${existingInstruction}`;
  }
  return existingInstruction;
}

/**
 * Loads the caller-scoped people roster with a strict timeout and fail-closed
 * semantics: if loading fails or times out, no AI provider is called and
 * `HttpsError('unavailable')` is thrown.
 */
export async function loadPeopleFailClosed({
  auth,
  db,
  peopleCache,
  domainCache,
  policyCache,
  extraPeople = [],
  timeoutMs = PEOPLE_LOAD_TIMEOUT_MS,
  functionName = 'aiCall',
  japaneseFallback,
}) {
  try {
    const loaded = await withTimeout(
      loadPeopleForCaller(auth, { db, cache: peopleCache, domainCache, policyCache }),
      timeoutMs,
    );
    return [...loaded, ...extraPeople];
  } catch (err) {
    logger.error('Privacy roster load failed (fail-closed)', {
      functionName,
      code: err?.code ?? err?.name ?? 'ROSTER_LOAD_ERROR',
    });
    throw new HttpsError(
      'unavailable',
      japaneseFallback || 'AIサーバーが混雑しています。少し時間をおいてお試しください。',
    );
  }
}

/**
 * Normalizes either a provider-agnostic [AiRequest] or a legacy Gemini config
 * `{ model, contents, config: { systemInstruction, responseMimeType, tools } }`
 * into a canonical [AiRequest] shape.
 */
export function normalizeToAiRequest(requestOrConfig) {
  if (!requestOrConfig || typeof requestOrConfig !== 'object') {
    return { contents: '' };
  }
  const legacyCfg = requestOrConfig.config;
  if (legacyCfg && typeof legacyCfg === 'object') {
    const {
      systemInstruction: legacySys,
      responseMimeType,
      tools,
      ...restProviderConfig
    } = legacyCfg;
    const responseFormat = requestOrConfig.responseFormat ??
      (responseMimeType === 'application/json' ? 'json' : undefined);
    const webSearch = requestOrConfig.webSearch ??
      (Array.isArray(tools) && tools.some((t) => t && t.googleSearch !== undefined)
        ? true
        : undefined);
    return {
      ...requestOrConfig,
      systemInstruction: requestOrConfig.systemInstruction ?? legacySys,
      responseFormat,
      webSearch,
      providerConfig: Object.keys(restProviderConfig).length > 0
        ? restProviderConfig
        : requestOrConfig.providerConfig,
    };
  }
  return { ...requestOrConfig };
}

/**
 * Records non-sensitive AI token/model telemetry on `ai_usage/{uid}` (never
 * storing prompts, responses, or student content), and aggregates monthly
 * usage into `ai_usage_monthly/{yyyymm}/models/{provider_model}`.
 */
async function recordAllAiUsage({
  db,
  uid,
  provider,
  model,
  usage,
  budgetUsd,
  monthKey,
  now,
  functionName,
}) {
  if (!db || typeof db.collection !== 'function') return;

  if (uid) {
    try {
      const ref = db.collection('ai_usage').doc(uid);
      const today = (typeof now === 'function' ? now() : now).toISOString().slice(0, 10);
      const inputTokens = Number(usage?.inputTokens ?? 0) || 0;
      const outputTokens = Number(usage?.outputTokens ?? 0) || 0;

      const applyRecord = (prev = {}) => {
        const sameDay = prev.usageDay === today;
        return {
          usageDay: today,
          lastProvider: provider,
          lastModel: model ?? null,
          inputTokens: (sameDay ? Number(prev.inputTokens ?? 0) : 0) + inputTokens,
          outputTokens: (sameDay ? Number(prev.outputTokens ?? 0) : 0) + outputTokens,
        };
      };

      if (typeof db.runTransaction === 'function') {
        await db.runTransaction(async (tx) => {
          const snap = await tx.get(ref);
          const prev = snap.exists ? (snap.data() ?? {}) : {};
          tx.set(ref, applyRecord(prev), { merge: true });
        });
      } else if (typeof ref.get === 'function' && typeof ref.set === 'function') {
        const snap = await ref.get();
        const prev = snap.exists ? (snap.data() ?? {}) : {};
        await ref.set(applyRecord(prev), { merge: true });
      }
    } catch (err) {
      logger.warn('Failed to record per-user AI usage metadata', {
        functionName,
        code: err?.code ?? err?.name ?? 'USAGE_WRITE_ERROR',
      });
    }
  }

  await recordMonthlyUsageAndCheckBudget({
    db,
    provider,
    model,
    usage,
    budgetUsd,
    monthKey,
    now,
  }).catch((err) => {
    logger.warn('Failed to record monthly AI usage aggregate', {
      functionName,
      code: err?.code ?? err?.name ?? 'MONTHLY_USAGE_ERROR',
    });
  });
}

function buildProviderRequest({
  normalizedRequest,
  providerName,
  functionName,
  maskedContents,
  maskedSystemInstruction,
  isPrimaryProvider,
}) {
  const taskSettings = resolveTaskSettings(
    normalizedRequest.task ?? functionName,
    providerName === 'claude' ? 'claude' : 'gemini',
  );

  const req = {
    ...normalizedRequest,
    model: (isPrimaryProvider && normalizedRequest.model) || taskSettings.model,
    maxTokens: (isPrimaryProvider && normalizedRequest.maxTokens !== undefined)
      ? normalizedRequest.maxTokens
      : taskSettings.maxTokens,
    timeoutMs: normalizedRequest.timeoutMs ?? taskSettings.timeoutMs,
    responseFormat: normalizedRequest.responseFormat ?? taskSettings.responseFormat,
    webSearch: normalizedRequest.webSearch ?? taskSettings.webSearch,
    webSearchType: normalizedRequest.webSearchType ?? taskSettings.webSearchType,
    webSearchMaxUses: normalizedRequest.webSearchMaxUses ?? taskSettings.webSearchMaxUses,
    jsonSchema: normalizedRequest.jsonSchema ?? taskSettings.jsonSchema,
    thinking: isPrimaryProvider
      ? (normalizedRequest.thinking ?? taskSettings.claude?.thinking)
      : taskSettings.claude?.thinking,
    effort: isPrimaryProvider
      ? (normalizedRequest.effort ?? taskSettings.claude?.effort)
      : taskSettings.claude?.effort,
    contents: maskedContents,
    systemInstruction: maskedSystemInstruction,
  };
  delete req.config;
  return req;
}

async function runProviderWithTruncationPolicy(
  providerObj,
  safeRequest,
  { db, uid, budgetUsd, monthKey, now, functionName },
) {
  try {
    const rawResponse = await providerObj.generate(safeRequest);
    const resolvedProvider = rawResponse?.provider ?? providerObj.name;
    const resolvedModel = rawResponse?.model ?? safeRequest.model ?? null;
    await recordAllAiUsage({
      db,
      uid,
      provider: resolvedProvider,
      model: resolvedModel,
      usage: rawResponse?.usage,
      budgetUsd,
      monthKey,
      now,
      functionName,
    });
    return { rawResponse, truncated: false, retriedForTruncation: false };
  } catch (err) {
    if (!(err instanceof AiError && err.kind === 'truncated')) {
      throw err;
    }

    const firstProvider = err.provider || providerObj.name;
    const firstModel = err.model ?? safeRequest.model ?? null;
    await recordAllAiUsage({
      db,
      uid,
      provider: firstProvider,
      model: firstModel,
      usage: err.usage,
      budgetUsd,
      monthKey,
      now,
      functionName,
    });

    if (safeRequest.responseFormat === 'json') {
      const baseTokens = typeof safeRequest.maxTokens === 'number'
        ? safeRequest.maxTokens
        : 2048;
      const expandedTokens = Math.min(
        AI_MAX_RETRY_TOKENS_CEILING,
        Math.max(baseTokens + 1, Math.ceil(baseTokens * AI_TRUNCATED_RETRY_MULTIPLIER)),
      );
      if (expandedTokens <= baseTokens) {
        throw err;
      }
      logger.warn('JSON AI response truncated; retrying once with expanded maxTokens', {
        functionName,
        provider: firstProvider,
        model: firstModel,
        kind: 'truncated',
        previousMaxTokens: baseTokens,
        nextMaxTokens: expandedTokens,
      });

      const retryReq = {
        ...safeRequest,
        maxTokens: expandedTokens,
        explicitMaxTokens: expandedTokens,
      };
      try {
        const retryResponse = await providerObj.generate(retryReq);
        const retryProvider = retryResponse?.provider ?? providerObj.name;
        const retryModel = retryResponse?.model ?? retryReq.model ?? null;
        await recordAllAiUsage({
          db,
          uid,
          provider: retryProvider,
          model: retryModel,
          usage: retryResponse?.usage,
          budgetUsd,
          monthKey,
          now,
          functionName,
        });
        return { rawResponse: retryResponse, truncated: false, retriedForTruncation: true };
      } catch (retryErr) {
        if (retryErr instanceof AiError && retryErr.kind === 'truncated') {
          await recordAllAiUsage({
            db,
            uid,
            provider: retryErr.provider || providerObj.name,
            model: retryErr.model ?? retryReq.model ?? null,
            usage: retryErr.usage,
            budgetUsd,
            monthKey,
            now,
            functionName,
          });
        }
        throw retryErr;
      }
    }

    // Text tasks (chat, tips, weak-area, grounding): return truncated text and mark log.
    logger.warn('Text AI response truncated at token limit', {
      functionName,
      provider: firstProvider,
      model: firstModel,
      kind: 'truncated',
    });
    return {
      rawResponse: {
        text: err.partialText ?? '',
        provider: firstProvider,
        model: firstModel,
        finishReason: 'max_tokens',
        usage: err.usage,
      },
      truncated: true,
      retriedForTruncation: false,
    };
  }
}

/**
 * Single privacy-enforcing gateway for all server-side AI provider calls.
 *
 * Execution order:
 * 1. Resolve primary provider & check monthly budget cap (`AI_MONTHLY_BUDGET_USD`).
 *    If spend >= 100% and configured provider is `'claude'`, route to `'gemini'`.
 * 2. Load caller-scoped people roster (fail-closed: if loading fails or times
 *    out after 10s, NO AI provider is called and `HttpsError('unavailable')`
 *    is thrown).
 * 3. Load School Policy (using per-request caches so updates apply immediately).
 * 4. Mask all text segments in `request.contents` sequentially using a single
 *    `MaskingSession` so identical names/PII across history and prompt get the
 *    exact same token.
 * 5. Prepend `PRIVACY_TOKEN_INSTRUCTION` to `request.systemInstruction`.
 * 6. Call active provider with `max_tokens` truncation policy (JSON retries once
 *    with 1.5x up to ceiling; text returns partial with `kind: 'truncated'` log).
 * 7. If a transient error occurs (`rate_limited`, `overloaded`, `timeout`) and
 *    `AI_FALLBACK_PROVIDER` is configured (and not budget-blocked), retry once on
 *    the fallback provider using the exact same masked request & `MaskingSession`.
 * 8. Record per-user `ai_usage/{uid}` and atomic monthly `ai_usage_monthly/{yyyymm}`
 *    counters (no content).
 * 9. Restore tokens in `response.text` and check `findUnresolvedTokens`.
 */
export async function callAiSafely(
  requestOrConfig,
  {
    auth,
    db,
    provider: explicitProvider,
    providerName,
    fallbackProviderName,
    generateContent,
    createMessage,
    mapError,
    japaneseFallback,
    functionName = 'aiCall',
    session: externalSession,
    extraPeople = [],
    extraPatterns = [],
    extraHonorificExceptions = [],
    peopleCache,
    domainCache,
    policyCache,
    policy: explicitPolicy,
    timeoutMs = PEOPLE_LOAD_TIMEOUT_MS,
    budgetUsd,
    monthKey,
    now = () => new Date(),
  } = {},
) {
  const normalizedRequest = normalizeToAiRequest(requestOrConfig);
  const configuredPrimaryName = explicitProvider?.name ?? resolveActiveProviderName(providerName);
  const configuredFallbackName = explicitProvider
    ? 'none'
    : resolveFallbackProviderName(fallbackProviderName);
  const taskName = normalizedRequest.task ?? functionName;
  const primaryTaskSettings = resolveTaskSettings(taskName, configuredPrimaryName);
  const allowFallbackToFreeTier = normalizedRequest.allowFallbackToFreeTier !== undefined
    ? Boolean(normalizedRequest.allowFallbackToFreeTier)
    : primaryTaskSettings.allowFallbackToFreeTier;

  const budgetCheck = explicitProvider
    ? { effectiveProvider: configuredPrimaryName, budgetRedirected: false, budgetBlocked: false }
    : await resolveProviderWithBudget({
      requestedProvider: configuredPrimaryName,
      db,
      budgetUsd,
      monthKey,
      now,
      allowFallbackToFreeTier,
    });

  if (budgetCheck.budgetBlocked) {
    logger.warn('AI call blocked: monthly budget reached and task disallows free-tier fallback', {
      functionName,
      task: taskName,
      monthKey: budgetCheck.monthKey,
    });
    const budgetErr = new AiError({
      kind: 'budget_exceeded',
      provider: configuredPrimaryName,
      status: 429,
      reason: ERROR_REASONS.aiBudgetExceeded,
    });
    if (mapError) {
      throw mapError(budgetErr, japaneseFallback, { provider: configuredPrimaryName });
    }
    throw budgetErr;
  }

  const activeProviderName = budgetCheck.effectiveProvider;
  const activeProvider = explicitProvider ?? getProvider({
    providerName: activeProviderName,
    generateContent,
    createMessage,
  });

  const effectiveDomainCache = domainCache ?? new Map();
  const effectivePolicyCache = policyCache ?? new Map();
  const people = await loadPeopleFailClosed({
    auth,
    db,
    peopleCache,
    domainCache: effectiveDomainCache,
    policyCache: effectivePolicyCache,
    extraPeople,
    timeoutMs,
    functionName,
    japaneseFallback,
  });

  const policy = explicitPolicy ??
    (auth && db
      ? await loadSchoolPolicyForAuth(auth, {
        db,
        domainCache: effectiveDomainCache,
        policyCache: effectivePolicyCache,
      })
      : defaultSchoolPolicy());

  const mergedPatterns = [
    ...(policy?.privacy?.studentIdPatterns ?? []),
    ...extraPatterns,
  ];
  const mergedHonorificExceptions = new Set([
    ...DEFAULT_HONORIFIC_EXCEPTIONS,
    ...(policy?.privacy?.extraHonorificExceptions ?? []),
    ...extraHonorificExceptions,
  ]);

  const session = externalSession ?? new MaskingSession();
  const compiledRoster = compileRoster(people);
  const maskFn = (text) =>
    maskText(text, people, session, {
      compiledRoster,
      extraPatterns: mergedPatterns,
      honorificExceptions: mergedHonorificExceptions,
    });

  const maskedContents = maskAiContents(normalizedRequest.contents, maskFn);
  const maskedSystemInstruction = prependPrivacySystemInstruction(
    normalizedRequest.systemInstruction,
  );

  const primaryRequest = buildProviderRequest({
    normalizedRequest,
    providerName: activeProvider.name,
    functionName,
    maskedContents,
    maskedSystemInstruction,
    isPrimaryProvider: true,
  });

  let outcome;
  let usedFallback = false;
  let lastAttemptedProvider = activeProvider.name;

  try {
    outcome = await runProviderWithTruncationPolicy(activeProvider, primaryRequest, {
      db,
      uid: auth?.uid,
      budgetUsd,
      monthKey,
      now,
      functionName,
    });
  } catch (primaryErr) {
    const isFreeTierFallback = configuredFallbackName === 'gemini';
    const canFallback =
      !explicitProvider &&
      configuredFallbackName !== 'none' &&
      configuredFallbackName !== activeProvider.name &&
      !(configuredFallbackName === 'claude' && budgetCheck.budgetRedirected) &&
      (!isFreeTierFallback || allowFallbackToFreeTier) &&
      isTransientAiError(primaryErr);

    if (!canFallback) {
      const errorToMap = (!allowFallbackToFreeTier && isTransientAiError(primaryErr))
        ? new AiError({
          kind: primaryErr instanceof AiError ? primaryErr.kind : classifyRawAiError(primaryErr),
          provider: activeProvider.name,
          status: primaryErr?.status ?? null,
          reason: ERROR_REASONS.aiTemporarilyUnavailable,
          diag: primaryErr?.diag ?? null,
        })
        : primaryErr;
      if (mapError) {
        throw mapError(errorToMap, japaneseFallback, { provider: activeProvider.name });
      }
      throw errorToMap;
    }

    const fallbackBudget = configuredFallbackName === 'claude'
      ? await resolveProviderWithBudget({
        requestedProvider: 'claude',
        db,
        budgetUsd,
        monthKey,
        now,
      })
      : { effectiveProvider: configuredFallbackName, budgetRedirected: false };

    if (fallbackBudget.effectiveProvider === activeProvider.name) {
      if (mapError) {
        throw mapError(primaryErr, japaneseFallback, { provider: activeProvider.name });
      }
      throw primaryErr;
    }

    logger.warn('AI primary provider failed transiently; retrying on fallback provider', {
      functionName,
      fromProvider: activeProvider.name,
      toProvider: fallbackBudget.effectiveProvider,
      kind: classifyRawAiError(primaryErr),
    });

    const fallbackProvider = getProvider({
      providerName: fallbackBudget.effectiveProvider,
      generateContent,
      createMessage,
    });
    const fallbackRequest = buildProviderRequest({
      normalizedRequest,
      providerName: fallbackProvider.name,
      functionName,
      maskedContents,
      maskedSystemInstruction,
      isPrimaryProvider: false,
    });
    usedFallback = true;
    lastAttemptedProvider = fallbackProvider.name;

    try {
      outcome = await runProviderWithTruncationPolicy(fallbackProvider, fallbackRequest, {
        db,
        uid: auth?.uid,
        budgetUsd,
        monthKey,
        now,
        functionName,
      });
    } catch (fallbackErr) {
      if (mapError) {
        throw mapError(fallbackErr, japaneseFallback, { provider: lastAttemptedProvider });
      }
      throw fallbackErr;
    }
  }

  const rawResponse = outcome.rawResponse;
  const resolvedProvider = rawResponse?.provider ?? lastAttemptedProvider;
  const resolvedModel = rawResponse?.model ?? primaryRequest.model ?? null;
  const rawText = typeof rawResponse?.text === 'string' ? rawResponse.text : '';
  const restoredText = session.restore(rawText);
  const warnings = session.findUnresolvedTokens(restoredText);

  logger.info('Privacy gateway completed', {
    functionName,
    provider: resolvedProvider,
    model: resolvedModel,
    maskedCount: session.maskedCount,
    unresolvedTokenCount: warnings.length,
    ...(outcome.truncated ? { kind: 'truncated' } : {}),
    ...(usedFallback ? { fallback: true } : {}),
    ...(budgetCheck.budgetRedirected ? { budgetRedirected: true } : {}),
  });

  return {
    text: restoredText,
    warnings,
    maskedCount: session.maskedCount,
    maskedContents,
    provider: resolvedProvider,
    model: resolvedModel,
    usage: rawResponse?.usage,
    truncated: outcome.truncated,
    usedFallback,
    budgetRedirected: budgetCheck.budgetRedirected,
  };
}
