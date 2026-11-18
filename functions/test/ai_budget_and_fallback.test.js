import { test } from 'node:test';
import assert from 'node:assert/strict';
import { getFirestore } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions';
import {
  AI_PRICING_CONFIG,
  AI_TASK_CONFIG,
  calculateRequestCostUsd,
  resolveFallbackProviderName,
  resolveMonthlyBudgetUsd,
} from '../ai/ai_config.js';
import {
  currentUsageMonth,
  formatModelDocId,
  resolveProviderWithBudget,
} from '../ai/ai_budget.js';
import { AiError, mapAiError } from '../ai/ai_errors.js';
import { setClaudeMessagesCreateForTest } from '../ai/claude_provider.js';
import { setGeminiGenerateContentForTest } from '../ai/gemini_provider.js';
import { callAiSafely } from '../privacy/safe_ai.js';
import { runSmokeTests } from '../scripts/compare_providers.mjs';
import { ERROR_REASONS } from '../shared/error_reasons.js';
import {
  analyzeAssignmentSubmission,
  chatWithTutor,
  generateQuiz,
} from '../index.js';

// ---------------------------------------------------------------------------
// Subcollection + FieldValue.increment aware in-memory Firestore mock
// ---------------------------------------------------------------------------
function isIncrementTransform(val) {
  return Boolean(
    val &&
      typeof val === 'object' &&
      val.constructor?.name === 'NumericIncrementTransform' &&
      typeof val.operand === 'number',
  );
}

const isPlain = (v) => v && Object.getPrototypeOf(v) === Object.prototype;

function clonePlain(v) {
  if (Array.isArray(v)) return v.map(clonePlain);
  if (v instanceof Date) return new Date(v.getTime());
  if (isPlain(v)) {
    const out = {};
    for (const [k, val] of Object.entries(v)) out[k] = clonePlain(val);
    return out;
  }
  return v;
}

function applyMerge(existing = {}, incoming = {}) {
  const next = { ...existing };
  for (const [k, val] of Object.entries(incoming)) {
    if (isIncrementTransform(val)) {
      next[k] = (Number(existing[k] ?? 0) || 0) + val.operand;
    } else {
      next[k] = clonePlain(val);
    }
  }
  return next;
}

const store = new Map();
const logEntries = [];
const db = getFirestore();
logger.error = (msg, meta) => logEntries.push({ level: 'error', msg, meta });
logger.warn = (msg, meta) => logEntries.push({ level: 'warn', msg, meta });
logger.info = (msg, meta) => logEntries.push({ level: 'info', msg, meta });

function makeDocRef(path, id) {
  return {
    id,
    path,
    ref: { id, path },
    collection: (subCol) => makeCollectionRef(`${path}/${subCol}`),
    get: async () => {
      const d = store.get(path);
      return {
        exists: d !== undefined,
        id,
        ref: { id, path },
        data: () => (d ? clonePlain(d) : undefined),
      };
    },
    set: async (data, opts) => {
      const prev = opts?.merge ? (store.get(path) ?? {}) : {};
      store.set(path, applyMerge(prev, data));
    },
    update: async (fields) => {
      const prev = store.get(path) ?? {};
      store.set(path, applyMerge(prev, fields));
    },
  };
}

function makeCollectionRef(colPath) {
  return {
    doc: (id) => makeDocRef(`${colPath}/${id}`, id),
    where: (field, op, val) => ({
      limit: () => ({
        get: async () => {
          const docs = [];
          for (const [path, d] of store.entries()) {
            if (!path.startsWith(`${colPath}/`)) continue;
            const remainder = path.slice(colPath.length + 1);
            if (remainder.includes('/')) continue;
            let match = false;
            if (op === '==' && d[field] === val) match = true;
            if (op === 'array-contains' && Array.isArray(d[field]) && d[field].includes(val)) match = true;
            if (match) {
              docs.push({ id: remainder, ref: { id: remainder, path }, data: () => clonePlain(d) });
            }
          }
          return { empty: docs.length === 0, docs, size: docs.length };
        },
      }),
    }),
  };
}

function setupHarness() {
  store.clear();
  logEntries.length = 0;
  setGeminiGenerateContentForTest(null);
  setClaudeMessagesCreateForTest(null);
  delete process.env.AI_PROVIDER;
  delete process.env.AI_FALLBACK_PROVIDER;
  delete process.env.AI_MONTHLY_BUDGET_USD;
  delete process.env.AI_MODEL_CLAUDE;
  delete process.env.AI_MODEL_CLAUDE_LIGHT;

  db.collection = (col) => makeCollectionRef(col);
  db.getAll = async (...refs) =>
    refs.map((ref) => {
      const d = store.get(ref.path);
      return {
        exists: d !== undefined,
        id: ref.id,
        ref,
        data: () => (d ? clonePlain(d) : undefined),
      };
    });

  // Serialized mutex queue for atomic in-memory runTransaction simulation
  let txChain = Promise.resolve();
  db.runTransaction = (callback) => {
    const run = txChain.then(async () => {
      const ops = [];
      const tx = {
        get: async (ref) => {
          const d = store.get(ref.path);
          return {
            exists: d !== undefined,
            id: ref.id,
            ref,
            data: () => (d ? clonePlain(d) : undefined),
          };
        },
        set: (ref, data, opts) => ops.push({ type: 'set', path: ref.path, data, opts }),
        update: (ref, data) => ops.push({ type: 'update', path: ref.path, data }),
        delete: (ref) => ops.push({ type: 'delete', path: ref.path }),
      };
      const result = await callback(tx);
      for (const op of ops) {
        if (op.type === 'set') {
          const prev = op.opts?.merge ? (store.get(op.path) ?? {}) : {};
          store.set(op.path, applyMerge(prev, op.data));
        } else if (op.type === 'update') {
          const prev = store.get(op.path) ?? {};
          store.set(op.path, applyMerge(prev, op.data));
        } else if (op.type === 'delete') {
          store.delete(op.path);
        }
      }
      return result;
    });
    txChain = run.catch(() => {});
    return run;
  };
}

function seedRoster() {
  store.set('schools/kosen.ac.jp', {
    name: '高専',
    grades: [1],
    courses: ['AI'],
    admins: [],
    teachers: ['teacher@kosen.ac.jp'],
    teacherProfiles: {
      'teacher@kosen.ac.jp': { name: '高橋誠', homeroom: { grade: 1, course: 'AI' } },
    },
  });
  store.set('users/student_1', {
    name: '山田太郎',
    grade: '1',
    course: 'AI',
    schoolDomain: 'kosen.ac.jp',
  });
}

const studentAuth = {
  uid: 'student_1',
  token: { email: 'taro@kosen.ac.jp', email_verified: true },
};

// ---------------------------------------------------------------------------
// Part B: max_tokens truncation handling (JSON retry 1.5x + text truncation)
// ---------------------------------------------------------------------------
test('Part B1: JSON task retries ONCE with maxTokens * 1.5 (up to 8192) on Claude max_tokens & Gemini MAX_TOKENS', async () => {
  for (const providerName of ['claude', 'gemini']) {
    setupHarness();
    seedRoster();
    process.env.AI_PROVIDER = providerName;

    const seenTokens = [];
    setClaudeMessagesCreateForTest(async (params) => {
      seenTokens.push(params.max_tokens);
      if (seenTokens.length === 1) {
        return {
          model: params.model,
          stop_reason: 'max_tokens',
          content: [{ type: 'text', text: '{"questions":[' }],
          usage: { input_tokens: 100, output_tokens: 4096 },
        };
      }
      return {
        model: params.model,
        stop_reason: 'end_turn',
        content: [{
          type: 'text',
          text: JSON.stringify({
            questions: [{
              question: '[STUDENT_1]の問題',
              choices: ['A', 'B', 'C', 'D'],
              answerIndex: 0,
              explanation: 'OK',
            }],
          }),
        }],
        usage: { input_tokens: 100, output_tokens: 500 },
      };
    });

    setGeminiGenerateContentForTest(async (cfg) => {
      if (cfg.config?.tools) {
        return { text: 'grounding' };
      }
      seenTokens.push(cfg.config?.maxOutputTokens ?? 4096);
      if (seenTokens.length === 1) {
        return {
          text: '{"questions":[',
          candidates: [{ finishReason: 'MAX_TOKENS' }],
          usageMetadata: { promptTokenCount: 100, candidatesTokenCount: 4096 },
        };
      }
      return {
        text: JSON.stringify({
          questions: [{
            question: '[STUDENT_1]の問題',
            choices: ['A', 'B', 'C', 'D'],
            answerIndex: 0,
            explanation: 'OK',
          }],
        }),
        candidates: [{ finishReason: 'STOP' }],
        usageMetadata: { promptTokenCount: 100, candidatesTokenCount: 500 },
      };
    });

    const res = await generateQuiz.run({
      auth: studentAuth,
      data: { subject: '数学', topic: '山田太郎の微分', useSearch: false, language: 'ja' },
    });

    assert.equal(seenTokens.length, 2, `${providerName} should retry exactly once`);
    assert.equal(seenTokens[1], 6144, '4096 * 1.5 = 6144 <= 8192 ceiling');
    assert.equal(res.questions[0].question, '山田太郎の問題');
    assert.ok(logEntries.some((l) => l.level === 'warn' && l.meta?.kind === 'truncated'));
  }
});

test('Part B2: Double JSON truncation fails with mapped HttpsError and refunds daily ai_usage quota', async () => {
  setupHarness();
  seedRoster();
  process.env.AI_PROVIDER = 'claude';

  let calls = 0;
  setClaudeMessagesCreateForTest(async (params) => {
    calls += 1;
    return {
      model: params.model,
      stop_reason: 'max_tokens',
      content: [{ type: 'text', text: '{"partial":' }],
      usage: { input_tokens: 100, output_tokens: params.max_tokens },
    };
  });

  await assert.rejects(
    () => generateQuiz.run({
      auth: studentAuth,
      data: { subject: '数学', topic: '積分', useSearch: false, language: 'ja' },
    }),
    (err) => err.code === 'internal',
  );

  assert.equal(calls, 2, 'Primary call + 1 expanded retry');
  const userUsage = store.get('ai_usage/student_1');
  assert.equal(userUsage.count, 0, 'Daily quota must be refunded after failed double truncation');
});

test('Part B3: Text task (chatWithTutor) returns restored partial text and logs kind: truncated', async () => {
  setupHarness();
  seedRoster();
  process.env.AI_PROVIDER = 'claude';

  let calls = 0;
  setClaudeMessagesCreateForTest(async (params) => {
    calls += 1;
    return {
      model: params.model,
      stop_reason: 'max_tokens',
      content: [{ type: 'text', text: '[STUDENT_1]さんの途中までの回答...' }],
      usage: { input_tokens: 120, output_tokens: params.max_tokens },
    };
  });

  const res = await chatWithTutor.run({
    auth: studentAuth,
    data: { botId: 'planner', message: '山田太郎です。長い説明をください', language: 'ja' },
  });

  assert.equal(calls, 1, 'Text tasks must NOT retry on max_tokens');
  assert.equal(res.reply, '山田太郎さんの途中までの回答...');
  assert.ok(
    logEntries.some((l) => l.meta?.kind === 'truncated'),
    'Truncation log with kind=truncated must be emitted',
  );
});

// ---------------------------------------------------------------------------
// Part C: Monthly usage aggregation & web_search tracking
// ---------------------------------------------------------------------------
test('Part C: ai_usage_monthly/{yyyymm}/models/{provider_model} atomically aggregates tokens & Claude web_search_requests without PII', async () => {
  setupHarness();
  seedRoster();
  process.env.AI_PROVIDER = 'claude';

  const fixedNow = new Date('2026-11-18T12:00:00Z');
  assert.equal(currentUsageMonth(fixedNow), '202611');
  assert.equal(formatModelDocId('claude', 'claude-sonnet-5-5'), 'claude_claude-sonnet-5-5');

  setClaudeMessagesCreateForTest(async (params) => {
    if (params.tools) {
      return {
        model: params.model,
        stop_reason: 'end_turn',
        content: [{ type: 'text', text: '[STUDENT_1]の検索メモ' }],
        usage: {
          input_tokens: 1000,
          output_tokens: 250,
          server_tool_use: { web_search_requests: 2 },
        },
      };
    }
    return {
      model: params.model,
      stop_reason: 'end_turn',
      content: [{
        type: 'text',
        text: JSON.stringify({
          questions: [{ question: 'Q', choices: ['1', '2', '3', '4'], answerIndex: 0, explanation: 'E' }],
        }),
      }],
      usage: { input_tokens: 1500, output_tokens: 400 },
    };
  });

  // 2 grounding + quiz calls via callAiSafely directly with fixed clock
  await callAiSafely(
    { task: 'generateQuiz:grounding', contents: '山田太郎の物理' },
    {
      auth: studentAuth,
      db,
      now: fixedNow,
      monthKey: '202611',
    },
  );
  await callAiSafely(
    { task: 'generateQuiz', contents: '山田太郎の物理クイズ' },
    {
      auth: studentAuth,
      db,
      now: fixedNow,
      monthKey: '202611',
    },
  );

  const modelDoc = store.get('ai_usage_monthly/202611/models/claude_claude-sonnet-5-5');
  assert.equal(modelDoc.provider, 'claude');
  assert.equal(modelDoc.model, 'claude-sonnet-5-5');
  assert.equal(modelDoc.inputTokens, 2500);
  assert.equal(modelDoc.outputTokens, 650);
  assert.equal(modelDoc.webSearchRequests, 2);
  assert.equal(modelDoc.calls, 2);

  const monthDoc = store.get('ai_usage_monthly/202611');
  assert.equal(monthDoc.inputTokens, 2500);
  assert.equal(monthDoc.outputTokens, 650);
  assert.equal(monthDoc.webSearchRequests, 2);
  assert.equal(monthDoc.calls, 2);
  assert.ok(!JSON.stringify(modelDoc).includes('山田太郎'));
  assert.ok(!JSON.stringify(monthDoc).includes('student_1'));

  // Official pricing check: Sonnet ($2/MTok in, $10/MTok out, $10/1000 web_search)
  const expectedCost =
    (2500 / 1_000_000) * AI_PRICING_CONFIG['claude-sonnet-5-5'].inputPerMTok +
    (650 / 1_000_000) * AI_PRICING_CONFIG['claude-sonnet-5-5'].outputPerMTok +
    (2 / 1_000) * AI_PRICING_CONFIG['claude-sonnet-5-5'].webSearchPer1k;
  assert.ok(Math.abs(monthDoc.estimatedCostUsd - expectedCost) < 1e-9);
});

// ---------------------------------------------------------------------------
// Part D: Budget protection (79%, 80%, 100%, month rollover, race)
// ---------------------------------------------------------------------------
test('Part D1: AI_MONTHLY_BUDGET_USD warns once at >=80%, auto-routes to gemini at >=100%, and resumes on month rollover', async () => {
  setupHarness();
  seedRoster();
  process.env.AI_PROVIDER = 'claude';
  process.env.AI_MONTHLY_BUDGET_USD = '1.00';

  assert.equal(resolveMonthlyBudgetUsd(), 1);

  let claudeCalls = 0;
  let geminiCalls = 0;

  setClaudeMessagesCreateForTest(async (params) => {
    claudeCalls += 1;
    // Sonnet $2/M in, $10/M out -> 39,500 output = $0.395 per call
    return {
      model: params.model,
      stop_reason: 'end_turn',
      content: [{ type: 'text', text: 'ok' }],
      usage: { input_tokens: 0, output_tokens: 39_500 },
    };
  });
  setGeminiGenerateContentForTest(async () => {
    geminiCalls += 1;
    return {
      text: 'gemini ok',
      usageMetadata: { promptTokenCount: 100, candidatesTokenCount: 50 },
    };
  });

  // Call 1: $0.395 (39.5%) -> Claude, no warning
  const r1 = await callAiSafely(
    { task: 'chatWithTutor', contents: '1' },
    { auth: studentAuth, db, monthKey: '202611' },
  );
  assert.equal(r1.provider, 'claude');
  assert.equal(logEntries.filter((l) => l.level === 'warn').length, 0);

  // Call 2: $0.79 (79%) -> Claude, still under 80%, NO warning
  const r2 = await callAiSafely(
    { task: 'chatWithTutor', contents: '2' },
    { auth: studentAuth, db, monthKey: '202611' },
  );
  assert.equal(r2.provider, 'claude');
  assert.equal(logEntries.filter((l) => l.level === 'warn').length, 0);

  // Override output tokens so Call 3 reaches $0.82 (82%) -> warns ONCE at 80%
  setClaudeMessagesCreateForTest(async (params) => {
    claudeCalls += 1;
    return {
      model: params.model,
      stop_reason: 'end_turn',
      content: [{ type: 'text', text: 'ok' }],
      usage: { input_tokens: 0, output_tokens: 3_000 }, // +$0.03 = $0.82
    };
  });
  await callAiSafely(
    { task: 'chatWithTutor', contents: '3' },
    { auth: studentAuth, db, monthKey: '202611' },
  );
  assert.equal(
    logEntries.filter((l) => l.level === 'warn' && l.msg.includes('80%')).length,
    1,
    '80% threshold must emit one warning',
  );

  // Call 4 reaches $0.85 (85%) -> MUST NOT emit 80% warning a second time
  await callAiSafely(
    { task: 'chatWithTutor', contents: '4' },
    { auth: studentAuth, db, monthKey: '202611' },
  );
  assert.equal(
    logEntries.filter((l) => l.level === 'warn' && l.msg.includes('80%')).length,
    1,
    '80% warning must NOT repeat at 85%',
  );

  // Call 5 pushes spend to >= $1.00 (100%)
  setClaudeMessagesCreateForTest(async (params) => {
    claudeCalls += 1;
    return {
      model: params.model,
      stop_reason: 'end_turn',
      content: [{ type: 'text', text: 'ok' }],
      usage: { input_tokens: 0, output_tokens: 20_000 }, // +$0.20 = $1.05
    };
  });
  await callAiSafely(
    { task: 'chatWithTutor', contents: '5' },
    { auth: studentAuth, db, monthKey: '202611' },
  );
  assert.equal(
    logEntries.filter((l) => l.level === 'warn' && l.msg.includes('100%')).length,
    1,
  );

  // Call 6 in same month (202611): MUST route to Gemini WITHOUT calling Claude!
  const claudeCountBefore = claudeCalls;
  const r6 = await callAiSafely(
    { task: 'chatWithTutor', contents: '6' },
    { auth: studentAuth, db, monthKey: '202611' },
  );
  assert.equal(r6.provider, 'gemini');
  assert.equal(r6.budgetRedirected, true);
  assert.equal(claudeCalls, claudeCountBefore, 'Claude MUST NOT be invoked at >=100% budget');
  assert.equal(geminiCalls, 1);

  // Month rollover to 202612: resumes Claude cleanly
  const rNextMonth = await callAiSafely(
    { task: 'chatWithTutor', contents: '7' },
    { auth: studentAuth, db, monthKey: '202612' },
  );
  assert.equal(rNextMonth.provider, 'claude');
  assert.equal(rNextMonth.budgetRedirected, false);
});

test('Part D2: Concurrent requests crossing 80% and 100% increment atomically and warn at most once per threshold', async () => {
  setupHarness();
  seedRoster();
  process.env.AI_PROVIDER = 'claude';
  process.env.AI_MONTHLY_BUDGET_USD = '0.50';

  // Each call costs $0.10 (10,000 output tokens on Sonnet @ $10/M)
  setClaudeMessagesCreateForTest(async (params) => ({
    model: params.model,
    stop_reason: 'end_turn',
    content: [{ type: 'text', text: 'ok' }],
    usage: { input_tokens: 0, output_tokens: 10_000 },
  }));

  await Promise.all(
    Array.from({ length: 10 }, (_, idx) =>
      callAiSafely(
        { task: 'chatWithTutor', contents: `req-${idx}` },
        { auth: studentAuth, db, monthKey: '202611' },
      ),
    ),
  );

  const monthDoc = store.get('ai_usage_monthly/202611');
  const modelDoc = store.get('ai_usage_monthly/202611/models/claude_claude-sonnet-5-5');
  assert.equal(monthDoc.calls, 10);
  assert.equal(modelDoc.calls, 10);
  assert.ok(Math.abs(monthDoc.estimatedCostUsd - 1.0) < 1e-6);
  assert.equal(
    logEntries.filter((l) => l.level === 'warn' && l.msg.includes('80%')).length,
    1,
  );
  assert.equal(
    logEntries.filter((l) => l.level === 'warn' && l.msg.includes('100%')).length,
    1,
  );

  const checkAfter = await resolveProviderWithBudget({
    requestedProvider: 'claude',
    db,
    budgetUsd: 0.5,
    monthKey: '202611',
  });
  assert.equal(checkAfter.effectiveProvider, 'gemini');
  assert.equal(checkAfter.budgetRedirected, true);
});

// ---------------------------------------------------------------------------
// Part F: AI_FALLBACK_PROVIDER (transient-only + same MaskingSession + budget guard)
// ---------------------------------------------------------------------------
test('Part F1: AI_FALLBACK_PROVIDER retries transient errors (429/529/504) with identical masked request & restores tokens', async () => {
  assert.equal(resolveFallbackProviderName(), 'none');

  const transientErrors = [
    { status: 429, message: 'rate_limit_error' },
    { status: 529, message: 'overloaded_error' },
    { status: 504, name: 'APIConnectionTimeoutError', message: 'timeout' },
  ];

  // Claude -> Gemini
  for (const errObj of transientErrors) {
    setupHarness();
    seedRoster();
    process.env.AI_PROVIDER = 'claude';
    process.env.AI_FALLBACK_PROVIDER = 'gemini';

    let claudeSent = '';
    let geminiSent = '';
    setClaudeMessagesCreateForTest(async (params) => {
      claudeSent = JSON.stringify(params.messages);
      throw errObj;
    });
    setGeminiGenerateContentForTest(async (cfg) => {
      geminiSent = JSON.stringify(cfg.contents);
      return {
        text: '[STUDENT_1]さんの質問へのフォールバック回答',
        usageMetadata: { promptTokenCount: 50, candidatesTokenCount: 20 },
      };
    });

    const res = await callAiSafely(
      { task: 'chatWithTutor', contents: '山田太郎の質問です' },
      { auth: studentAuth, db, mapError: mapAiError },
    );

    assert.equal(res.provider, 'gemini');
    assert.equal(res.usedFallback, true);
    assert.equal(res.text, '山田太郎さんの質問へのフォールバック回答');
    assert.ok(claudeSent.includes('[STUDENT_1]') && !claudeSent.includes('山田太郎'));
    assert.ok(geminiSent.includes('[STUDENT_1]') && !geminiSent.includes('山田太郎'));
  }

  // Gemini -> Claude
  setupHarness();
  seedRoster();
  process.env.AI_PROVIDER = 'gemini';
  process.env.AI_FALLBACK_PROVIDER = 'claude';

  setGeminiGenerateContentForTest(async () => {
    throw new AiError({ kind: 'overloaded', provider: 'gemini', status: 503 });
  });
  setClaudeMessagesCreateForTest(async (params) => ({
    model: params.model,
    stop_reason: 'end_turn',
    content: [{ type: 'text', text: '[STUDENT_1]さん Claude回答' }],
    usage: { input_tokens: 40, output_tokens: 15 },
  }));

  const res2 = await callAiSafely(
    { task: 'aiStudyTip', contents: '山田太郎の集中ヒント' },
    { auth: studentAuth, db, mapError: mapAiError },
  );
  assert.equal(res2.provider, 'claude');
  assert.equal(res2.usedFallback, true);
  assert.equal(res2.text, '山田太郎さん Claude回答');
});

test('Part F2: Non-transient errors (400/401/safety_blocked) and budget-exceeded Claude do NOT trigger fallback', async () => {
  const nonTransient = [
    new AiError({ kind: 'invalid_request', provider: 'claude', status: 400 }),
    new AiError({ kind: 'auth', provider: 'claude', status: 401 }),
    new AiError({ kind: 'safety_blocked', provider: 'claude', status: 200 }),
  ];

  for (const err of nonTransient) {
    setupHarness();
    seedRoster();
    process.env.AI_PROVIDER = 'claude';
    process.env.AI_FALLBACK_PROVIDER = 'gemini';

    let fallbackCalled = false;
    setClaudeMessagesCreateForTest(async () => {
      throw err;
    });
    setGeminiGenerateContentForTest(async () => {
      fallbackCalled = true;
      return { text: 'should not happen' };
    });

    await assert.rejects(
      () => callAiSafely(
        { task: 'chatWithTutor', contents: 'hi' },
        { auth: studentAuth, db, mapError: mapAiError, japaneseFallback: 'error' },
      ),
    );
    assert.equal(fallbackCalled, false, `Must NOT fallback on ${err.kind}`);
  }

  // Fallback to claude blocked when monthly budget is already >= 100%
  setupHarness();
  seedRoster();
  process.env.AI_PROVIDER = 'gemini';
  process.env.AI_FALLBACK_PROVIDER = 'claude';
  process.env.AI_MONTHLY_BUDGET_USD = '1.00';
  store.set('ai_usage_monthly/202611', { estimatedCostUsd: 1.5 });

  let claudeCalled = false;
  setGeminiGenerateContentForTest(async () => {
    throw new AiError({ kind: 'rate_limited', provider: 'gemini', status: 429 });
  });
  setClaudeMessagesCreateForTest(async () => {
    claudeCalled = true;
    return { content: [{ type: 'text', text: 'no' }] };
  });

  await assert.rejects(
    () => callAiSafely(
      { task: 'chatWithTutor', contents: 'hi' },
      { auth: studentAuth, db, mapError: mapAiError, monthKey: '202611' },
    ),
    (e) => e.code === 'resource-exhausted',
  );
  assert.equal(claudeCalled, false, 'Fallback to Claude must be blocked when monthly budget reached 100%');
});

// ---------------------------------------------------------------------------
// Part E: compare_providers.mjs --smoke tests every task without leaking text
// ---------------------------------------------------------------------------
test('Part E: runSmokeTests tests every task in AI_TASK_CONFIG, tracks tokens/webSearch, and never leaks AI text', async () => {
  const SECRET_REPLY_MARKER = 'SENSITIVE_AI_RESPONSE_TEXT_DO_NOT_LEAK';
  const expectedTasks = Object.keys(AI_TASK_CONFIG);
  const calledTasks = [];

  const rows = await runSmokeTests({
    providers: ['claude'],
    providerFactory: () => ({
      name: 'claude',
      generate: async (req) => {
        calledTasks.push(req.task);
        if (req.task === 'previewTimetableImport') {
          throw new AiError({ kind: 'invalid_request', provider: 'claude', status: 400 });
        }
        return {
          text: SECRET_REPLY_MARKER,
          provider: 'claude',
          model: req.model,
          usage: {
            inputTokens: 120,
            outputTokens: 30,
            webSearchCount: req.webSearch ? 1 : 0,
          },
        };
      },
    }),
  });

  assert.deepEqual(calledTasks, expectedTasks);
  assert.equal(rows.length, expectedTasks.length);
  const serialized = JSON.stringify(rows);
  assert.ok(!serialized.includes(SECRET_REPLY_MARKER), 'Smoke test results must never include AI output text');

  const groundingRow = rows.find((r) => r.task === 'generateQuiz:grounding');
  assert.equal(groundingRow.ok, true);
  assert.equal(groundingRow.webSearchRequests, 1);

  const failedRow = rows.find((r) => r.task === 'previewTimetableImport');
  assert.equal(failedRow.ok, false);
  assert.equal(failedRow.status, 'ERR(invalid_request:400)');
});

test('Cost calculation helper computes official Sonnet 5.5, Haiku 5.5, and web_search costs', () => {
  const sonnetCost = calculateRequestCostUsd({
    provider: 'claude',
    model: 'claude-sonnet-5-5',
    usage: { inputTokens: 1_000_000, outputTokens: 1_000_000, webSearchCount: 100 },
  });
  // $2 in + $10 out + $1 (100 * $10/1000) = $13
  assert.ok(Math.abs(sonnetCost - 13) < 1e-9);

  const haikuCost = calculateRequestCostUsd({
    provider: 'claude',
    model: 'claude-haiku-5-5',
    usage: { inputTokens: 1_000_000, outputTokens: 1_000_000, webSearchCount: 0 },
  });
  // $0.10 in + $0.50 out = $0.60
  assert.ok(Math.abs(haikuCost - 0.6) < 1e-9);
});

// ---------------------------------------------------------------------------
// Part G: Per-task allowFallbackToFreeTier, 100% budget block, Gemini 429 retry
// ---------------------------------------------------------------------------
test('Part G1: AI_TASK_CONFIG defines allowFallbackToFreeTier per task and blocks free-tier fallback on sensitive tasks with ai_temporarily_unavailable + quota refund', async () => {
  const expectedPolicy = {
    aiStudyTip: true,
    analyzeWeakArea: true,
    chatWithTutor: true,
    'generateQuiz:grounding': true,
    generateQuiz: true,
    analyzeAssignmentSubmission: false,
    previewTimetableImport: false,
  };
  assert.deepEqual(
    Object.keys(AI_TASK_CONFIG).sort(),
    Object.keys(expectedPolicy).sort(),
  );

  for (const [task, expectedAllowed] of Object.entries(expectedPolicy)) {
    assert.equal(
      AI_TASK_CONFIG[task].allowFallbackToFreeTier,
      expectedAllowed,
      `AI_TASK_CONFIG.${task}.allowFallbackToFreeTier must be ${expectedAllowed}`,
    );

    setupHarness();
    seedRoster();
    process.env.AI_PROVIDER = 'claude';
    process.env.AI_FALLBACK_PROVIDER = 'gemini';

    let geminiCalled = false;
    setClaudeMessagesCreateForTest(async () => {
      throw { status: 503, message: 'service unavailable' };
    });
    setGeminiGenerateContentForTest(async () => {
      geminiCalled = true;
      return {
        text: 'gemini fallback response',
        usageMetadata: { promptTokenCount: 20, candidatesTokenCount: 10 },
      };
    });

    if (expectedAllowed) {
      const res = await callAiSafely(
        { task, contents: 'テスト入力' },
        { auth: studentAuth, db, mapError: mapAiError, japaneseFallback: 'fallback' },
      );
      assert.equal(geminiCalled, true, `${task} should fall back to Gemini free tier`);
      assert.equal(res.provider, 'gemini');
      assert.equal(res.usedFallback, true);
    } else {
      await assert.rejects(
        () => callAiSafely(
          { task, contents: 'テスト入力' },
          { auth: studentAuth, db, mapError: mapAiError, japaneseFallback: 'fallback' },
        ),
        (err) =>
          err.code === 'unavailable' &&
          err.details?.reason === ERROR_REASONS.aiTemporarilyUnavailable,
      );
      assert.equal(geminiCalled, false, `${task} MUST NOT fall back to Gemini free tier`);
    }
  }

  // End-to-end callable check for analyzeAssignmentSubmission: transient Claude 429 -> no Gemini + ai_temporarily_unavailable + quota refunded
  setupHarness();
  seedRoster();
  process.env.AI_PROVIDER = 'claude';
  process.env.AI_FALLBACK_PROVIDER = 'gemini';

  let geminiCalls = 0;
  setClaudeMessagesCreateForTest(async () => {
    throw { status: 429, message: 'rate_limit_error' };
  });
  setGeminiGenerateContentForTest(async () => {
    geminiCalls += 1;
    return { text: 'should not happen' };
  });

  await assert.rejects(
    () => analyzeAssignmentSubmission.run({
      auth: studentAuth,
      data: {
        subject: '数学',
        title: '宿題',
        fileBase64: Buffer.from('回答テスト', 'utf8').toString('base64'),
        mimeType: 'text/plain',
        language: 'uz',
      },
    }),
    (err) =>
      err.code === 'resource-exhausted' &&
      err.details?.reason === ERROR_REASONS.aiTemporarilyUnavailable,
  );
  assert.equal(geminiCalls, 0);
  const usageDoc = store.get('ai_usage/student_1');
  assert.equal(usageDoc.count, 0, 'Daily quota must be refunded when analyzeAssignmentSubmission fails transiently');
});

test('Part G2: At 100% monthly budget, allowed tasks route to Gemini while disallowed tasks fail with ai_budget_exceeded and refund quota', async () => {
  const allowedTasks = [
    'aiStudyTip',
    'analyzeWeakArea',
    'chatWithTutor',
    'generateQuiz:grounding',
    'generateQuiz',
  ];
  for (const task of allowedTasks) {
    setupHarness();
    seedRoster();
    process.env.AI_PROVIDER = 'claude';
    process.env.AI_MONTHLY_BUDGET_USD = '1.00';
    store.set('ai_usage_monthly/202611', { estimatedCostUsd: 1.0 });

    let claudeCalled = false;
    let geminiCalled = false;
    setClaudeMessagesCreateForTest(async () => {
      claudeCalled = true;
      return { content: [{ type: 'text', text: 'no' }] };
    });
    setGeminiGenerateContentForTest(async () => {
      geminiCalled = true;
      return { text: 'ok', usageMetadata: { promptTokenCount: 10, candidatesTokenCount: 5 } };
    });

    const res = await callAiSafely(
      { task, contents: 'hi' },
      { auth: studentAuth, db, mapError: mapAiError, monthKey: '202611' },
    );
    assert.equal(claudeCalled, false);
    assert.equal(geminiCalled, true);
    assert.equal(res.provider, 'gemini');
    assert.equal(res.budgetRedirected, true);
  }

  // Disallowed tasks (previewTimetableImport & analyzeAssignmentSubmission) must be blocked with ai_budget_exceeded
  for (const blockedTask of ['previewTimetableImport', 'analyzeAssignmentSubmission']) {
    setupHarness();
    seedRoster();
    process.env.AI_PROVIDER = 'claude';
    process.env.AI_MONTHLY_BUDGET_USD = '1.00';
    store.set('ai_usage_monthly/202611', { estimatedCostUsd: 1.25 });

    let claudeCalled = false;
    let geminiCalled = false;
    setClaudeMessagesCreateForTest(async () => {
      claudeCalled = true;
      return { content: [{ type: 'text', text: 'no' }] };
    });
    setGeminiGenerateContentForTest(async () => {
      geminiCalled = true;
      return { text: 'no' };
    });

    await assert.rejects(
      () => callAiSafely(
        { task: blockedTask, contents: 'secret student/school data' },
        { auth: studentAuth, db, mapError: mapAiError, monthKey: '202611' },
      ),
      (err) =>
        err.code === 'resource-exhausted' &&
        err.details?.reason === ERROR_REASONS.aiBudgetExceeded,
    );
    assert.equal(claudeCalled, false);
    assert.equal(geminiCalled, false);
  }

  // Callable analyzeAssignmentSubmission with image payload at 100% budget -> blocked before Vision/Gemini + quota refunded
  setupHarness();
  seedRoster();
  process.env.AI_PROVIDER = 'claude';
  process.env.AI_MONTHLY_BUDGET_USD = '1.00';
  const currentMonth = currentUsageMonth();
  store.set(`ai_usage_monthly/${currentMonth}`, { estimatedCostUsd: 1.0 });

  let claudeImgCalls = 0;
  let geminiImgCalls = 0;
  setClaudeMessagesCreateForTest(async () => {
    claudeImgCalls += 1;
    return { content: [{ type: 'text', text: 'no' }] };
  });
  setGeminiGenerateContentForTest(async () => {
    geminiImgCalls += 1;
    return { text: 'no' };
  });

  // Use BOTH image/png and text/plain to verify callable budget block runs before Vision OCR / Claude / Gemini
  for (const [mimeType, payload] of [
    ['image/png', Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]).toString('base64')],
    ['text/plain', Buffer.from('My homework submission', 'utf8').toString('base64')],
  ]) {
    await assert.rejects(
      () => analyzeAssignmentSubmission.run({
        auth: studentAuth,
        data: {
          subject: '英語',
          title: 'エッセイ',
          fileBase64: payload,
          mimeType,
          language: 'uz',
        },
      }),
      (err) =>
        err.code === 'resource-exhausted' &&
        err.details?.reason === ERROR_REASONS.aiBudgetExceeded,
    );
    assert.equal(store.get('ai_usage/student_1').count, 0);
  }
  assert.equal(claudeImgCalls, 0);
  assert.equal(geminiImgCalls, 0);
});

test('Part G3: Gemini free tier retries 429 exactly once, succeeding on retry or failing with ai_temporarily_unavailable', async () => {
  // 1. First 429 -> retries once -> succeeds on 2nd attempt
  setupHarness();
  seedRoster();
  process.env.AI_PROVIDER = 'gemini';

  let attempts = 0;
  setGeminiGenerateContentForTest(async () => {
    attempts += 1;
    if (attempts === 1) {
      const err = new Error('RESOURCE_EXHAUSTED');
      err.status = 429;
      throw err;
    }
    return {
      text: '[STUDENT_1]さん、リトライ成功',
      usageMetadata: { promptTokenCount: 15, candidatesTokenCount: 8 },
    };
  });

  const okRes = await callAiSafely(
    { task: 'aiStudyTip', contents: '山田太郎' },
    { auth: studentAuth, db, mapError: mapAiError },
  );
  assert.equal(attempts, 2, 'Gemini must retry 429 once and succeed on 2nd attempt');
  assert.equal(okRes.text, '山田太郎さん、リトライ成功');

  // 2. Both attempts return 429 -> stops after 2 attempts (1 initial + 1 retry) with ai_temporarily_unavailable
  setupHarness();
  seedRoster();
  process.env.AI_PROVIDER = 'gemini';

  let failAttempts = 0;
  setGeminiGenerateContentForTest(async () => {
    failAttempts += 1;
    const err = new Error('RESOURCE_EXHAUSTED');
    err.status = 429;
    throw err;
  });

  await assert.rejects(
    () => callAiSafely(
      { task: 'aiStudyTip', contents: '山田太郎' },
      { auth: studentAuth, db, mapError: mapAiError },
    ),
    (err) =>
      err.code === 'resource-exhausted' &&
      err.details?.reason === ERROR_REASONS.aiTemporarilyUnavailable,
  );
  assert.equal(failAttempts, 2, 'Gemini must retry 429 at most ONCE (2 total attempts)');
});

