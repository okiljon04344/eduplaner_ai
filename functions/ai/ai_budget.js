import { FieldValue } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions';
import {
  calculateRequestCostUsd,
  resolveMonthlyBudgetUsd,
} from './ai_config.js';

export const BUDGET_WARN_THRESHOLD = 0.8;

/**
 * Returns the UTC month key formatted as `yyyymm` (e.g. `'202611'`).
 *
 * @param {Date|(() => Date)} [now]
 * @returns {string}
 */
export function currentUsageMonth(now = () => new Date()) {
  const d = typeof now === 'function' ? now() : now;
  const iso = d.toISOString();
  return `${iso.slice(0, 4)}${iso.slice(5, 7)}`;
}

/**
 * Formats a Firestore-safe document ID for `ai_usage_monthly/{yyyymm}/models/{provider_model}`.
 *
 * @param {string} provider
 * @param {string} [model]
 * @returns {string}
 */
export function formatModelDocId(provider, model = '') {
  const cleanProvider = String(provider || 'unknown').replace(/[^a-zA-Z0-9._-]/g, '_');
  const cleanModel = String(model || 'default').replace(/[^a-zA-Z0-9._-]/g, '_');
  return `${cleanProvider}_${cleanModel}`;
}

/**
 * Checks whether monthly spending has already reached 100% of `AI_MONTHLY_BUDGET_USD`.
 * When `requestedProvider === 'claude'` and spend >= budget:
 *   - If `allowFallbackToFreeTier` is true, routes the call to `'gemini'` until UTC month rollover.
 *   - If `allowFallbackToFreeTier` is false, blocks the call (`budgetBlocked: true`) so
 *     sensitive/submission tasks fail closed with `'ai_budget_exceeded'`.
 *
 * @param {{
 *   requestedProvider: 'gemini' | 'claude',
 *   db?: any,
 *   budgetUsd?: number,
 *   monthKey?: string,
 *   now?: Date | (() => Date),
 *   allowFallbackToFreeTier?: boolean,
 * }} params
 * @returns {Promise<{ effectiveProvider: 'gemini' | 'claude' | null, budgetRedirected: boolean, budgetBlocked: boolean, estimatedCostUsd: number, budgetUsd: number, monthKey: string }>}
 */
export async function resolveProviderWithBudget({
  requestedProvider,
  db,
  budgetUsd,
  monthKey,
  now = () => new Date(),
  allowFallbackToFreeTier = true,
}) {
  const effectiveBudget = budgetUsd !== undefined
    ? Math.max(0, Number(budgetUsd) || 0)
    : resolveMonthlyBudgetUsd();
  const effectiveMonth = monthKey || currentUsageMonth(now);

  if (requestedProvider !== 'claude' || effectiveBudget <= 0 || !db || typeof db.collection !== 'function') {
    return {
      effectiveProvider: requestedProvider,
      budgetRedirected: false,
      budgetBlocked: false,
      estimatedCostUsd: 0,
      budgetUsd: effectiveBudget,
      monthKey: effectiveMonth,
    };
  }

  try {
    const snap = await db.collection('ai_usage_monthly').doc(effectiveMonth).get();
    const data = snap.exists ? (snap.data() ?? {}) : {};
    const estimatedCostUsd = Number(data.estimatedCostUsd ?? 0) || 0;

    if (estimatedCostUsd >= effectiveBudget) {
      if (!allowFallbackToFreeTier) {
        return {
          effectiveProvider: null,
          budgetRedirected: false,
          budgetBlocked: true,
          estimatedCostUsd,
          budgetUsd: effectiveBudget,
          monthKey: effectiveMonth,
        };
      }
      return {
        effectiveProvider: 'gemini',
        budgetRedirected: true,
        budgetBlocked: false,
        estimatedCostUsd,
        budgetUsd: effectiveBudget,
        monthKey: effectiveMonth,
      };
    }

    return {
      effectiveProvider: 'claude',
      budgetRedirected: false,
      budgetBlocked: false,
      estimatedCostUsd,
      budgetUsd: effectiveBudget,
      monthKey: effectiveMonth,
    };
  } catch (err) {
    logger.warn('Monthly budget lookup failed; proceeding with configured provider', {
      monthKey: effectiveMonth,
      code: err?.code ?? err?.name ?? 'BUDGET_READ_ERROR',
    });
    return {
      effectiveProvider: requestedProvider,
      budgetRedirected: false,
      budgetBlocked: false,
      estimatedCostUsd: 0,
      budgetUsd: effectiveBudget,
      monthKey: effectiveMonth,
    };
  }
}

/**
 * Atomically records per-model monthly token/search usage into:
 *   `ai_usage_monthly/{yyyymm}/models/{provider_model}`
 * and updates the monthly cost aggregate in `ai_usage_monthly/{yyyymm}`.
 * Emits a single `logger.warn` when spend crosses 80% (and when reaching 100%).
 * Never stores or logs prompts, responses, or user PII.
 *
 * @param {{
 *   db?: any,
 *   provider: string,
 *   model?: string|null,
 *   usage?: { inputTokens?: number, outputTokens?: number, webSearchCount?: number },
 *   budgetUsd?: number,
 *   monthKey?: string,
 *   now?: Date | (() => Date),
 * }} params
 */
export async function recordMonthlyUsageAndCheckBudget({
  db,
  provider,
  model,
  usage,
  budgetUsd,
  monthKey,
  now = () => new Date(),
}) {
  if (!db || typeof db.collection !== 'function') return null;

  const effectiveMonth = monthKey || currentUsageMonth(now);
  const effectiveBudget = budgetUsd !== undefined
    ? Math.max(0, Number(budgetUsd) || 0)
    : resolveMonthlyBudgetUsd();

  const monthRef = db.collection('ai_usage_monthly').doc(effectiveMonth);
  const inputTokens = Math.max(0, Number(usage?.inputTokens ?? 0) || 0);
  const outputTokens = Math.max(0, Number(usage?.outputTokens ?? 0) || 0);
  const webSearchRequests = Math.max(0, Number(usage?.webSearchCount ?? 0) || 0);
  const callCostUsd = calculateRequestCostUsd({ provider, model: model ?? '', usage });

  // 1. Atomic per-model counter document: ai_usage_monthly/{yyyymm}/models/{provider_model}
  if (typeof monthRef.collection === 'function') {
    const modelDocId = formatModelDocId(provider, model || 'default');
    const modelRef = monthRef.collection('models').doc(modelDocId);
    await modelRef.set(
      {
        provider,
        model: model ?? null,
        inputTokens: FieldValue.increment(inputTokens),
        outputTokens: FieldValue.increment(outputTokens),
        webSearchRequests: FieldValue.increment(webSearchRequests),
        calls: FieldValue.increment(1),
      },
      { merge: true },
    );
  }

  // 2. Transactional monthly total + one-time 80%/100% warning flags.
  let warningEvent = null;
  if (typeof db.runTransaction === 'function') {
    await db.runTransaction(async (tx) => {
      warningEvent = null;
      const snap = await tx.get(monthRef);
      const prev = snap.exists ? (snap.data() ?? {}) : {};
      const nextCost = (Number(prev.estimatedCostUsd ?? 0) || 0) + callCostUsd;
      const updates = {
        month: effectiveMonth,
        estimatedCostUsd: FieldValue.increment(callCostUsd),
        inputTokens: FieldValue.increment(inputTokens),
        outputTokens: FieldValue.increment(outputTokens),
        webSearchRequests: FieldValue.increment(webSearchRequests),
        calls: FieldValue.increment(1),
      };

      if (effectiveBudget > 0) {
        if (!prev.budgetExceededWarned && nextCost >= effectiveBudget) {
          updates.budgetExceededWarned = true;
          updates.budgetWarned80 = true;
          warningEvent = {
            level: '100',
            monthKey: effectiveMonth,
            estimatedCostUsd: nextCost,
            budgetUsd: effectiveBudget,
          };
        } else if (!prev.budgetWarned80 && nextCost >= effectiveBudget * BUDGET_WARN_THRESHOLD) {
          updates.budgetWarned80 = true;
          warningEvent = {
            level: '80',
            monthKey: effectiveMonth,
            estimatedCostUsd: nextCost,
            budgetUsd: effectiveBudget,
          };
        }
      }

      tx.set(monthRef, updates, { merge: true });
    });
  } else if (typeof monthRef.set === 'function') {
    await monthRef.set(
      {
        month: effectiveMonth,
        estimatedCostUsd: FieldValue.increment(callCostUsd),
        inputTokens: FieldValue.increment(inputTokens),
        outputTokens: FieldValue.increment(outputTokens),
        webSearchRequests: FieldValue.increment(webSearchRequests),
        calls: FieldValue.increment(1),
      },
      { merge: true },
    );
  }

  if (warningEvent?.level === '80') {
    logger.warn('AI monthly budget crossed 80% threshold', {
      monthKey: warningEvent.monthKey,
      estimatedCostUsd: Number(warningEvent.estimatedCostUsd.toFixed(6)),
      budgetUsd: warningEvent.budgetUsd,
    });
  } else if (warningEvent?.level === '100') {
    logger.warn('AI monthly budget reached 100%; routing Claude calls to Gemini', {
      monthKey: warningEvent.monthKey,
      estimatedCostUsd: Number(warningEvent.estimatedCostUsd.toFixed(6)),
      budgetUsd: warningEvent.budgetUsd,
    });
  }

  return {
    monthKey: effectiveMonth,
    callCostUsd,
    warningEvent,
  };
}
