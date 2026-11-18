import { test } from 'node:test';
import assert from 'node:assert/strict';
import sharp from 'sharp';
import { getFirestore } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions';
import {
  AI_TASK_CONFIG,
  TIMETABLE_STRUCTURED_SCHEMA,
  resolveActiveProviderName,
  resolveChatTask,
  resolveTaskSettings,
} from '../ai/ai_config.js';
import { getAiSecrets, getProvider } from '../ai/ai_provider.js';
import { AiError, mapAiError } from '../ai/ai_errors.js';
import {
  CLAUDE_MAX_IMAGE_BASE64_BYTES,
  CLAUDE_WEB_SEARCH_TOOL_TYPE,
  createClaudeProvider,
  setClaudeMessagesCreateForTest,
  toClaudeSdkParams,
  validateClaudeThinkingConfig,
} from '../ai/claude_provider.js';
import { setGeminiGenerateContentForTest } from '../ai/gemini_provider.js';
import { callAiSafely } from '../privacy/safe_ai.js';
import { setVisionClientForTest } from '../privacy/image_redactor.js';
import { ERROR_REASONS } from '../shared/error_reasons.js';
import {
  analyzeAssignmentSubmission,
  analyzeWeakArea,
  chatWithTutor,
  generateQuiz,
} from '../index.js';
import { previewTimetableImport } from '../school/timetable_import.js';

// ---------------------------------------------------------------------------
// In-memory Firestore & logger harness (restored on every test)
// ---------------------------------------------------------------------------
const isPlain = (v) => v && Object.getPrototypeOf(v) === Object.prototype;
const cloneData = (v) => {
  if (Array.isArray(v)) return v.map(cloneData);
  if (v instanceof Date) return new Date(v.getTime());
  if (isPlain(v)) {
    const out = {};
    for (const [k, val] of Object.entries(v)) out[k] = cloneData(val);
    return out;
  }
  return v;
};

const store = new Map();
const logEntries = [];
let failFirestoreReads = false;

const db = getFirestore();
logger.error = (msg, meta) => logEntries.push({ level: 'error', msg, meta });
logger.warn = (msg, meta) => logEntries.push({ level: 'warn', msg, meta });
logger.info = (msg, meta) => logEntries.push({ level: 'info', msg, meta });

function setupHarness() {
  store.clear();
  logEntries.length = 0;
  failFirestoreReads = false;
  setGeminiGenerateContentForTest(null);
  setClaudeMessagesCreateForTest(null);
  setVisionClientForTest(null);
  delete process.env.AI_PROVIDER;
  delete process.env.AI_MODEL_GEMINI;
  delete process.env.AI_MODEL_CLAUDE;
  delete process.env.AI_MODEL_CLAUDE_LIGHT;

  db.collection = (col) => ({
    doc: (id) => {
      const path = `${col}/${id}`;
      return {
        id,
        path,
        ref: { id, path },
        get: async () => {
          if (failFirestoreReads && col !== 'ai_usage') {
            throw new Error('Simulated Firestore failure');
          }
          const d = store.get(path);
          return {
            exists: d !== undefined,
            id,
            ref: { id, path },
            data: () => (d ? cloneData(d) : undefined),
          };
        },
        set: async (data, opts) => {
          if (opts?.merge && store.has(path)) {
            store.set(path, { ...store.get(path), ...cloneData(data) });
          } else {
            store.set(path, cloneData(data));
          }
        },
        update: async (fields) => {
          const cur = store.get(path) ?? {};
          store.set(path, { ...cur, ...cloneData(fields) });
        },
      };
    },
    where: (field, op, val) => ({
      limit: () => ({
        get: async () => {
          if (failFirestoreReads) {
            throw new Error('Simulated Firestore query failure');
          }
          const docs = [];
          for (const [path, d] of store.entries()) {
            if (!path.startsWith(`${col}/`)) continue;
            let match = false;
            if (op === '==' && d[field] === val) match = true;
            if (op === 'array-contains' && Array.isArray(d[field]) && d[field].includes(val)) match = true;
            if (match) {
              const id = path.slice(col.length + 1);
              docs.push({ id, ref: { id, path }, data: () => cloneData(d) });
            }
          }
          return { empty: docs.length === 0, docs, size: docs.length };
        },
      }),
    }),
  });

  db.getAll = async (...refs) => {
    if (failFirestoreReads) {
      throw new Error('Simulated Firestore getAll failure');
    }
    return refs.map((ref) => {
      const d = store.get(ref.path);
      return {
        exists: d !== undefined,
        id: ref.id,
        ref,
        data: () => (d ? cloneData(d) : undefined),
      };
    });
  };

  db.runTransaction = async (callback) => {
    const ops = [];
    const tx = {
      get: async (ref) => {
        const d = store.get(ref.path);
        return {
          exists: d !== undefined,
          id: ref.id,
          ref,
          data: () => (d ? cloneData(d) : undefined),
        };
      },
      set: (ref, data, opts) => ops.push({ type: 'set', path: ref.path, data: cloneData(data), opts }),
      update: (ref, data) => ops.push({ type: 'update', path: ref.path, data: cloneData(data) }),
      delete: (ref) => ops.push({ type: 'delete', path: ref.path }),
    };
    const result = await callback(tx);
    for (const op of ops) {
      if (op.type === 'set') {
        if (op.opts?.merge && store.has(op.path)) {
          store.set(op.path, { ...store.get(op.path), ...op.data });
        } else {
          store.set(op.path, op.data);
        }
      } else if (op.type === 'update') {
        const cur = store.get(op.path) ?? {};
        store.set(op.path, { ...cur, ...op.data });
      } else if (op.type === 'delete') {
        store.delete(op.path);
      }
    }
    return result;
  };
}

function seedRosterAndPolicy(extraPolicy = null) {
  store.set('schools/kosen.ac.jp', {
    name: '高専',
    grades: [1, 2],
    courses: ['AI'],
    admins: ['admin_1'],
    teachers: ['teacher@kosen.ac.jp'],
    teacherProfiles: {
      'teacher@kosen.ac.jp': { name: '高橋誠', homeroom: { grade: 1, course: 'AI' } },
    },
    ...(extraPolicy ? { policy: extraPolicy } : {}),
  });
  store.set('users/student_1', {
    name: '山田太郎',
    grade: '1',
    course: 'AI',
    schoolDomain: 'kosen.ac.jp',
  });
  store.set('timetables/tt_1', {
    userId: 'student_1',
    teacher: '佐藤先生',
    subject: '数学',
  });
}

const studentAuth = {
  uid: 'student_1',
  token: { email: 'taro@kosen.ac.jp', email_verified: true },
};

const teacherAuth = {
  uid: 'teacher_1',
  token: { email: 'teacher@kosen.ac.jp', email_verified: true },
};

const PROVIDERS = ['gemini', 'claude'];

// ---------------------------------------------------------------------------
// 1. chatWithTutor contract across Gemini & Claude
// ---------------------------------------------------------------------------
test('Contract 1: chatWithTutor masks PII, uses Sonnet low effort on Claude, and restores tokens across both providers', async () => {
  for (const providerName of PROVIDERS) {
    setupHarness();
    seedRosterAndPolicy();
    process.env.AI_PROVIDER = providerName;

    let capturedGemini = null;
    let capturedClaude = null;

    setGeminiGenerateContentForTest(async (cfg) => {
      capturedGemini = cfg;
      return {
        text: '[STUDENT_1]さん、[TEACHER_1]先生の課題を優先しましょう。',
        usageMetadata: { promptTokenCount: 120, candidatesTokenCount: 35 },
      };
    });
    setClaudeMessagesCreateForTest(async (params) => {
      capturedClaude = params;
      return {
        id: 'msg_1',
        model: params.model,
        stop_reason: 'end_turn',
        content: [
          { type: 'thinking', thinking: '', signature: 'sig_1' },
          { type: 'text', text: '[STUDENT_1]さん、[TEACHER_1]先生の課題を優先しましょう。' },
        ],
        usage: { input_tokens: 150, output_tokens: 45 },
      };
    });

    const res = await chatWithTutor.run({
      auth: studentAuth,
      data: {
        botId: 'planner',
        message: '山田太郎です。高橋誠先生の課題が難しいです (090-1234-5678)。',
        language: 'ja',
      },
    });

    assert.equal(res.reply, '山田太郎さん、高橋誠先生の課題を優先しましょう。');
    if (providerName === 'gemini') {
      assert.ok(!JSON.stringify(capturedGemini).includes('山田太郎'));
      assert.ok(!JSON.stringify(capturedGemini).includes('高橋誠'));
      assert.ok(!JSON.stringify(capturedGemini).includes('090-1234-5678'));
    } else {
      assert.equal(capturedClaude.model, 'claude-sonnet-5-5');
      assert.equal(capturedClaude.max_tokens, AI_TASK_CONFIG.chatWithTutor.maxTokens);
      assert.deepEqual(capturedClaude.thinking, { type: 'adaptive' });
      assert.deepEqual(capturedClaude.output_config, { effort: 'low' });
      assert.equal(capturedClaude.temperature, undefined);
      assert.ok(!JSON.stringify(capturedClaude).includes('山田太郎'));
      assert.ok(!JSON.stringify(capturedClaude).includes('高橋誠'));
      assert.ok(!JSON.stringify(capturedClaude).includes('090-1234-5678'));
    }
  }
});

// ---------------------------------------------------------------------------
// 2. aiStudyTip (botId: focus) contract across Gemini & Claude
// ---------------------------------------------------------------------------
test('Contract 2: aiStudyTip (botId: focus, no history) uses LIGHT model with thinking disabled on Claude', async () => {
  for (const providerName of PROVIDERS) {
    setupHarness();
    seedRosterAndPolicy();
    process.env.AI_PROVIDER = providerName;

    let capturedClaude = null;
    setGeminiGenerateContentForTest(async () => ({
      text: '[STUDENT_1]さん、25分集中して復習しましょう。',
      usageMetadata: { promptTokenCount: 50, candidatesTokenCount: 20 },
    }));
    setClaudeMessagesCreateForTest(async (params) => {
      capturedClaude = params;
      return {
        model: params.model,
        stop_reason: 'end_turn',
        content: [{ type: 'text', text: '[STUDENT_1]さん、25分集中して復習しましょう。' }],
        usage: { input_tokens: 60, output_tokens: 22 },
      };
    });

    assert.equal(resolveChatTask('focus', []), 'aiStudyTip');
    assert.equal(resolveChatTask('focus', [{ role: 'user', content: 'hi' }]), 'chatWithTutor');

    const res = await chatWithTutor.run({
      auth: studentAuth,
      data: {
        botId: 'focus',
        message: '山田太郎の今日の学習ヒントをください',
        language: 'ja',
      },
    });

    assert.equal(res.reply, '山田太郎さん、25分集中して復習しましょう。');
    if (providerName === 'claude') {
      assert.equal(capturedClaude.model, 'claude-haiku-5-5');
      assert.equal(capturedClaude.max_tokens, AI_TASK_CONFIG.aiStudyTip.maxTokens);
      assert.deepEqual(capturedClaude.thinking, { type: 'disabled' });
      assert.deepEqual(capturedClaude.output_config, { effort: 'low' });
      assert.ok(!JSON.stringify(capturedClaude).includes('山田太郎'));
    }
  }
});

// ---------------------------------------------------------------------------
// 3. analyzeWeakArea contract across Gemini & Claude
// ---------------------------------------------------------------------------
test('Contract 3: analyzeWeakArea uses LIGHT model with thinking disabled on Claude and masks names', async () => {
  for (const providerName of PROVIDERS) {
    setupHarness();
    seedRosterAndPolicy();
    process.env.AI_PROVIDER = providerName;

    let capturedClaude = null;
    setGeminiGenerateContentForTest(async () => ({
      text: '[STUDENT_1]さんは数学を優先しましょう。',
    }));
    setClaudeMessagesCreateForTest(async (params) => {
      capturedClaude = params;
      return {
        model: params.model,
        stop_reason: 'end_turn',
        content: [{ type: 'text', text: '[STUDENT_1]さんは数学を優先しましょう。' }],
        usage: { input_tokens: 90, output_tokens: 30 },
      };
    });

    const res = await analyzeWeakArea.run({
      auth: studentAuth,
      data: {
        stats: [
          { subject: '数学 (山田太郎)', totalCount: 5, completedCount: 1, overdueCount: 2, avgDifficulty: 4 },
        ],
        language: 'ja',
      },
    });

    assert.equal(res.analysis, '山田太郎さんは数学を優先しましょう。');
    if (providerName === 'claude') {
      assert.equal(capturedClaude.model, 'claude-haiku-5-5');
      assert.equal(capturedClaude.max_tokens, AI_TASK_CONFIG.analyzeWeakArea.maxTokens);
      assert.deepEqual(capturedClaude.thinking, { type: 'disabled' });
      assert.ok(!JSON.stringify(capturedClaude).includes('山田太郎'));
    }
  }
});

// ---------------------------------------------------------------------------
// 4. generateQuiz (grounding web_search_20250305 max_uses=2 + JSON)
// ---------------------------------------------------------------------------
test('Contract 4: generateQuiz uses web_search_20250305 (max_uses: 2) on Claude, concatenates text blocks only, and restores tokens', async () => {
  for (const providerName of PROVIDERS) {
    setupHarness();
    seedRosterAndPolicy();
    process.env.AI_PROVIDER = providerName;

    const claudeCalls = [];
    setGeminiGenerateContentForTest(async (cfg) => {
      if (cfg.config?.tools) {
        return { text: '[TEACHER_1]先生の補足ノート' };
      }
      return {
        text: JSON.stringify({
          questions: [{
            question: '[TEACHER_1]先生の問題',
            choices: ['A', 'B', 'C', 'D'],
            answerIndex: 1,
            explanation: '[STUDENT_1]向けの解説',
          }],
        }),
      };
    });

    setClaudeMessagesCreateForTest(async (params) => {
      claudeCalls.push(params);
      if (params.tools) {
        return {
          model: params.model,
          stop_reason: 'end_turn',
          content: [
            { type: 'thinking', thinking: '', signature: 'sig_ground' },
            { type: 'server_tool_use', id: 'srv_1', name: 'web_search', input: { query: 'test' } },
            { type: 'web_search_tool_result', tool_use_id: 'srv_1', content: [] },
            { type: 'text', text: '[TEACHER_1]先生の' },
            { type: 'text', text: '補足ノート' },
          ],
          usage: {
            input_tokens: 200,
            output_tokens: 60,
            server_tool_use: { web_search_requests: 1 },
          },
        };
      }
      return {
        model: params.model,
        stop_reason: 'end_turn',
        content: [
          {
            type: 'text',
            text: '```json\n' + JSON.stringify({
              questions: [{
                question: '[TEACHER_1]先生の問題',
                choices: ['A', 'B', 'C', 'D'],
                answerIndex: 1,
                explanation: '[STUDENT_1]向けの解説',
              }],
            }) + '\n```',
          },
        ],
        usage: { input_tokens: 220, output_tokens: 180 },
      };
    });

    const res = await generateQuiz.run({
      auth: studentAuth,
      data: {
        subject: '物理',
        topic: '高橋誠先生の力学 (山田太郎)',
        useSearch: true,
        language: 'ja',
      },
    });

    assert.equal(res.grounded, true);
    assert.equal(res.questions[0].question, '高橋誠先生の問題');
    assert.equal(res.questions[0].explanation, '山田太郎向けの解説');

    if (providerName === 'claude') {
      assert.equal(claudeCalls.length, 2);
      assert.equal(claudeCalls[0].model, 'claude-sonnet-5-5');
      assert.deepEqual(claudeCalls[0].output_config, { effort: 'medium' });
      assert.deepEqual(claudeCalls[0].tools, [{
        type: CLAUDE_WEB_SEARCH_TOOL_TYPE,
        name: 'web_search',
        max_uses: 2,
      }]);
      assert.equal(claudeCalls[0].max_tokens, AI_TASK_CONFIG['generateQuiz:grounding'].maxTokens);
      assert.equal(claudeCalls[1].max_tokens, AI_TASK_CONFIG.generateQuiz.maxTokens);
      assert.ok(!JSON.stringify(claudeCalls).includes('高橋誠'));
      assert.ok(!JSON.stringify(claudeCalls).includes('山田太郎'));
    }
  }
});

// ---------------------------------------------------------------------------
// 5. analyzeAssignmentSubmission: image ordering + 5 MB compression + fail-closed
// ---------------------------------------------------------------------------
test('Contract 5: analyzeAssignmentSubmission places redacted image before text, compresses >5MB base64, and throws image_too_large_for_provider when irreducible', async () => {
  const smallPng = await sharp({
    create: { width: 320, height: 240, channels: 3, background: '#FFFFFF' },
  }).png().toBuffer();

  for (const providerName of PROVIDERS) {
    setupHarness();
    seedRosterAndPolicy();
    process.env.AI_PROVIDER = providerName;

    setVisionClientForTest({
      documentTextDetection: async () => [{
        fullTextAnnotation: {
          pages: [{
            blocks: [{
              paragraphs: [{
                words: [
                  {
                    text: '山田太郎',
                    boundingBox: { vertices: [{ x: 20, y: 20 }, { x: 120, y: 20 }, { x: 120, y: 50 }, { x: 20, y: 50 }] },
                    symbols: [...'山田太郎'].map((t, i, arr) => ({
                      text: t,
                      ...(i === arr.length - 1 ? { property: { detectedBreak: { type: 'EOL_SURE_SPACE' } } } : {}),
                    })),
                  },
                ],
              }],
            }],
          }],
        },
      }],
    });

    let capturedClaude = null;
    setGeminiGenerateContentForTest(async () => ({
      text: JSON.stringify({
        completionPercent: 90,
        missingParts: ['[TEACHER_1]先生の検算'],
        advice: '[STUDENT_1]さん、よくできました。',
      }),
    }));
    setClaudeMessagesCreateForTest(async (params) => {
      capturedClaude = params;
      return {
        model: params.model,
        stop_reason: 'end_turn',
        content: [{
          type: 'text',
          text: JSON.stringify({
            completionPercent: 90,
            missingParts: ['[TEACHER_1]先生の検算'],
            advice: '[STUDENT_1]さん、よくできました。',
          }),
        }],
        usage: { input_tokens: 400, output_tokens: 90 },
      };
    });

    const res = await analyzeAssignmentSubmission.run({
      auth: studentAuth,
      data: {
        subject: '数学',
        title: '高橋誠先生の課題 山田太郎のレポート',
        fileBase64: smallPng.toString('base64'),
        mimeType: 'image/png',
        language: 'ja',
      },
    });
    assert.equal(res.completionPercent, 90);
    assert.deepEqual(res.missingParts, ['高橋誠先生の検算']);
    assert.equal(res.advice, '山田太郎さん、よくできました。');

    if (providerName === 'claude') {
      const blocks = capturedClaude.messages[0].content;
      assert.equal(blocks[0].type, 'image', 'Image block must come BEFORE text block');
      assert.equal(blocks[1].type, 'text');
      assert.ok(!blocks[1].text.includes('山田太郎'));
    }
  }

  // Test >5MB base64 compression success on Claude
  const hugeNoiseRaw = Buffer.alloc(1800 * 1800 * 3);
  for (let i = 0; i < hugeNoiseRaw.length; i += 3) {
    hugeNoiseRaw[i] = (i * 73) % 256;
    hugeNoiseRaw[i + 1] = (i * 151) % 256;
    hugeNoiseRaw[i + 2] = (i * 199) % 256;
  }
  const hugePng = await sharp(hugeNoiseRaw, {
    raw: { width: 1800, height: 1800, channels: 3 },
  }).png({ compressionLevel: 0 }).toBuffer();
  const hugeBase64 = hugePng.toString('base64');
  assert.ok(hugeBase64.length > CLAUDE_MAX_IMAGE_BASE64_BYTES);

  let compressedParams = null;
  const claude = createClaudeProvider({
    createMessage: async (params) => {
      compressedParams = params;
      return {
        model: params.model,
        stop_reason: 'end_turn',
        content: [{ type: 'text', text: 'ok' }],
      };
    },
  });
  await claude.generate({
    contents: [{ role: 'user', parts: [{ text: 'check' }, { type: 'image', mimeType: 'image/png', data: hugeBase64 }] }],
  });
  const sentImageBlock = compressedParams.messages[0].content[0];
  assert.equal(sentImageBlock.source.media_type, 'image/jpeg');
  assert.ok(sentImageBlock.source.data.length <= CLAUDE_MAX_IMAGE_BASE64_BYTES);

  // Test irreducible image -> image_too_large_for_provider (mapped to HttpsError invalid-argument with reason)
  const smallCapClaude = createClaudeProvider({
    maxImageBase64Bytes: 100,
    createMessage: async () => {
      throw new Error('Must not reach SDK when image exceeds provider limit');
    },
  });
  await assert.rejects(
    () => smallCapClaude.generate({
      contents: [{ role: 'user', parts: [{ type: 'image', mimeType: 'image/png', data: smallPng.toString('base64') }] }],
    }),
    (err) => {
      assert.ok(err instanceof AiError);
      assert.equal(err.kind, 'image_too_large_for_provider');
      assert.equal(err.reason, ERROR_REASONS.imageTooLargeForProvider);
      const mapped = mapAiError(err, 'fallback', { provider: 'claude' });
      assert.equal(mapped.code, 'invalid-argument');
      assert.equal(mapped.details?.reason, 'image_too_large_for_provider');
      return true;
    },
  );
});

// ---------------------------------------------------------------------------
// 6. previewTimetableImport AI fallback + optional jsonSchema (default off)
// ---------------------------------------------------------------------------
test('Contract 6: previewTimetableImport sends ONLY masked OCR text (no inlineData) across providers and supports optional jsonSchema', async () => {
  const samplePng = await sharp({
    create: { width: 600, height: 400, channels: 3, background: '#FFFFFF' },
  }).png().toBuffer();

  for (const providerName of PROVIDERS) {
    setupHarness();
    seedRosterAndPolicy();
    process.env.AI_PROVIDER = providerName;

    setVisionClientForTest({
      documentTextDetection: async () => [{
        fullTextAnnotation: {
          pages: [{
            blocks: [{
              paragraphs: [{
                words: [{
                  text: '来週火曜1限は高橋誠先生の数学です',
                  boundingBox: { vertices: [{ x: 20, y: 20 }, { x: 400, y: 20 }, { x: 400, y: 50 }, { x: 20, y: 50 }] },
                  symbols: [...'来週火曜1限は高橋誠先生の数学です'].map((t, i, arr) => ({
                    text: t,
                    ...(i === arr.length - 1 ? { property: { detectedBreak: { type: 'EOL_SURE_SPACE' } } } : {}),
                  })),
                }],
              }],
            }],
          }],
        },
      }],
    });

    let capturedClaude = null;
    let capturedGemini = null;
    const jsonPayload = JSON.stringify({
      slots: [{ dayOfWeek: '火', period: '1', subject: '数学', teacher: '[TEACHER_1]', room: '101' }],
    });

    const preview = await previewTimetableImport(
      'kosen.ac.jp',
      store.get('schools/kosen.ac.jp'),
      teacherAuth,
      {
        grade: 1,
        course: 'AI',
        fileName: 'board.png',
        mimeType: 'image/png',
        fileBase64: samplePng.toString('base64'),
        dateRange: { start: '2026-06-01', end: '2026-06-05' },
      },
      {
        db,
        generateContent: async (cfg) => {
          capturedGemini = cfg;
          return { text: jsonPayload };
        },
        createMessage: async (params) => {
          capturedClaude = params;
          return {
            model: params.model,
            stop_reason: 'end_turn',
            content: [{ type: 'text', text: jsonPayload }],
          };
        },
      },
    );

    assert.equal(preview.parseMethod, 'ai');
    assert.equal(preview.usedAi, true);
    assert.equal(preview.diffPreview[0].after.teacher, '高橋誠');
    const serialized = JSON.stringify(providerName === 'gemini' ? capturedGemini : capturedClaude);
    assert.ok(!serialized.includes('inlineData'));
    assert.ok(!serialized.includes('"type":"image"'));
    assert.ok(!serialized.includes('高橋誠'));
    assert.ok(serialized.includes('[TEACHER_1]'));
    if (providerName === 'claude') {
      assert.equal(capturedClaude.output_config?.format, undefined, 'jsonSchema is disabled by default');
    }
  }

  // Verify optional jsonSchema attaches output_config.format when explicitly enabled
  const withSchema = await toClaudeSdkParams({
    contents: 'extract',
    responseFormat: 'json',
    jsonSchema: TIMETABLE_STRUCTURED_SCHEMA,
    effort: 'low',
  });
  assert.deepEqual(withSchema.output_config, {
    effort: 'low',
    format: {
      type: 'json_schema',
      schema: TIMETABLE_STRUCTURED_SCHEMA,
    },
  });
});

// ---------------------------------------------------------------------------
// 7. Fail-closed roster & timeout across both providers
// ---------------------------------------------------------------------------
test('Contract 7: Neither Gemini nor Claude is called when roster load fails or times out', async () => {
  for (const providerName of PROVIDERS) {
    setupHarness();
    process.env.AI_PROVIDER = providerName;
    failFirestoreReads = true;

    let called = false;
    await assert.rejects(
      () => callAiSafely(
        { task: 'chatWithTutor', contents: '山田太郎です' },
        {
          auth: studentAuth,
          db,
          generateContent: async () => { called = true; return { text: 'ok' }; },
          createMessage: async () => { called = true; return { content: [{ type: 'text', text: 'ok' }] }; },
        },
      ),
      (err) => err.code === 'unavailable',
    );
    assert.equal(called, false, `${providerName} must NOT be called when roster fails`);
  }
});

// ---------------------------------------------------------------------------
// 8. SchoolPolicy additive privacy parity across both providers
// ---------------------------------------------------------------------------
test('Contract 8: SchoolPolicy studentIdPatterns & extraHonorificExceptions apply identically under Gemini & Claude', async () => {
  for (const providerName of PROVIDERS) {
    setupHarness();
    seedRosterAndPolicy({
      schemaVersion: 1,
      privacy: {
        studentIdPatterns: ['\\bS\\d{6}\\b'],
        extraHonorificExceptions: ['部長'],
      },
    });
    process.env.AI_PROVIDER = providerName;

    let sent = '';
    const res = await callAiSafely(
      { task: 'chatWithTutor', contents: 'S202601 の山田太郎と部長さんと田中さん' },
      {
        auth: studentAuth,
        db,
        generateContent: async (cfg) => {
          sent = JSON.stringify(cfg.contents);
          return { text: '[STUDENT_ID_1] [STUDENT_1] 部長さん [PERSON_1]さん' };
        },
        createMessage: async (params) => {
          sent = JSON.stringify(params.messages);
          return {
            model: params.model,
            stop_reason: 'end_turn',
            content: [{ type: 'text', text: '[STUDENT_ID_1] [STUDENT_1] 部長さん [PERSON_1]さん' }],
          };
        },
      },
    );

    assert.ok(!sent.includes('S202601'));
    assert.ok(!sent.includes('山田太郎'));
    assert.ok(!sent.includes('田中'));
    assert.ok(sent.includes('[STUDENT_ID_1]'));
    assert.ok(sent.includes('部長さん'));
    assert.equal(res.text, 'S202601 山田太郎 部長さん 田中さん');
  }
});

// ---------------------------------------------------------------------------
// 9. Safety refusal parity (Claude stop_reason: 'refusal', Gemini SAFETY)
// ---------------------------------------------------------------------------
test('Contract 9: Claude stop_reason=refusal and Gemini SAFETY finishReason both map to safety_blocked -> internal', async () => {
  setupHarness();
  seedRosterAndPolicy();

  await assert.rejects(
    () => callAiSafely(
      { task: 'chatWithTutor', contents: 'hello' },
      {
        providerName: 'gemini',
        auth: studentAuth,
        db,
        mapError: mapAiError,
        japaneseFallback: '安全フィルタによりブロックされました。',
        generateContent: async () => ({
          text: '',
          candidates: [{ finishReason: 'SAFETY' }],
        }),
      },
    ),
    (err) => err.code === 'internal' && err.message === '安全フィルタによりブロックされました。',
  );

  await assert.rejects(
    () => callAiSafely(
      { task: 'chatWithTutor', contents: 'hello' },
      {
        providerName: 'claude',
        auth: studentAuth,
        db,
        mapError: mapAiError,
        japaneseFallback: '安全フィルタによりブロックされました。',
        createMessage: async () => ({
          model: 'claude-sonnet-5-5',
          stop_reason: 'refusal',
          content: [{ type: 'text', text: 'I cannot help with that.' }],
        }),
      },
    ),
    (err) => err.code === 'internal' && err.message === '安全フィルタによりブロックされました。',
  );
});

// ---------------------------------------------------------------------------
// 10. Error mapping parity & zero sensitive message leakage
// ---------------------------------------------------------------------------
test('Contract 10: Error mapping parity (429/400/413/529/503/504/401) without leaking raw SDK messages', async () => {
  const cases = [
    { raw: { status: 429, message: 'SECRET_PROMPT rate_limit_error sk-ant-secret' }, expectedCode: 'resource-exhausted' },
    { raw: { status: 400, message: 'SECRET_PROMPT invalid_request_error' }, expectedCode: 'invalid-argument' },
    { raw: { status: 413, message: 'SECRET_PROMPT request_too_large' }, expectedCode: 'invalid-argument' },
    { raw: { status: 529, message: 'SECRET_PROMPT overloaded_error' }, expectedCode: 'unavailable' },
    { raw: { status: 503, message: 'SECRET_PROMPT service unavailable' }, expectedCode: 'unavailable' },
    { raw: { status: 504, name: 'APIConnectionTimeoutError', message: 'SECRET_PROMPT timed out' }, expectedCode: 'unavailable' },
    { raw: { status: 401, message: 'SECRET_API_KEY invalid' }, expectedCode: 'internal' },
  ];

  for (const c of cases) {
    for (const providerName of PROVIDERS) {
      setupHarness();
      seedRosterAndPolicy();
      const mapped = await callAiSafely(
        { task: 'chatWithTutor', contents: 'hello' },
        {
          providerName,
          auth: studentAuth,
          db,
          mapError: mapAiError,
          japaneseFallback: 'フォールバックメッセージ',
          generateContent: async () => { throw c.raw; },
          createMessage: async () => { throw c.raw; },
        },
      ).catch((e) => e);

      assert.equal(mapped.code, c.expectedCode, `${providerName} status ${c.raw.status}`);
      assert.ok(!mapped.message.includes('SECRET_PROMPT'));
      assert.ok(!mapped.message.includes('sk-ant-'));
      assert.ok(!mapped.message.includes('SECRET_API_KEY'));
      const serializedLogs = JSON.stringify(logEntries);
      assert.ok(!serializedLogs.includes('SECRET_PROMPT'));
      assert.ok(!serializedLogs.includes('sk-ant-'));
      assert.ok(!serializedLogs.includes('SECRET_API_KEY'));
    }
  }
});

// ---------------------------------------------------------------------------
// 11. ai_usage/{uid} metadata recording + AI_PROVIDER validation
// ---------------------------------------------------------------------------
test('Contract 11: ai_usage records provider/model/tokens without content; invalid AI_PROVIDER throws and default is gemini', async () => {
  setupHarness();
  seedRosterAndPolicy();

  assert.equal(resolveActiveProviderName(), 'gemini');
  process.env.AI_PROVIDER = 'invalid_xyz';
  assert.throws(
    () => getProvider(),
    (err) => err instanceof AiError && err.kind === 'invalid_request',
  );

  process.env.AI_PROVIDER = 'claude';
  setClaudeMessagesCreateForTest(async (params) => ({
    model: params.model,
    stop_reason: 'end_turn',
    content: [{ type: 'text', text: '[STUDENT_1]さん OK' }],
    usage: { input_tokens: 321, output_tokens: 64 },
  }));

  await chatWithTutor.run({
    auth: studentAuth,
    data: { botId: 'planner', message: '山田太郎の秘匿質問テキスト', language: 'ja' },
  });

  const usageDoc = store.get('ai_usage/student_1');
  assert.equal(usageDoc.lastProvider, 'claude');
  assert.equal(usageDoc.lastModel, 'claude-sonnet-5-5');
  assert.equal(usageDoc.inputTokens, 321);
  assert.equal(usageDoc.outputTokens, 64);
  assert.ok(!JSON.stringify(usageDoc).includes('秘匿質問テキスト'));
  assert.ok(!JSON.stringify(usageDoc).includes('山田太郎'));

  // Secrets list includes both GEMINI_API_KEY and ANTHROPIC_API_KEY
  assert.equal(getAiSecrets().length, 2);
});

// ---------------------------------------------------------------------------
// 12. Official Claude 5.5 invalid 400 combinations + task config verification
// ---------------------------------------------------------------------------
test('Contract 12: Claude 5.5 rejects invalid thinking/effort/sampling combinations and all configured tasks are valid', () => {
  // Invalid combinations that official Anthropic API rejects with 400
  const invalidCases = [
    { model: 'claude-sonnet-5-5', thinking: { type: 'disabled' } },
    { model: 'claude-sonnet-5-5', thinking: { type: 'enabled', budget_tokens: 1024 } },
    { model: 'claude-haiku-5-5', thinking: { type: 'enabled', budget_tokens: 1024 } },
    { model: 'claude-sonnet-5-5', thinking: { type: 'between_tools' }, effort: 'xhigh' },
    { model: 'claude-sonnet-5-5', thinking: { type: 'between_tools' }, effort: 'max' },
    { model: 'claude-sonnet-5-5', thinking: { type: 'between_tools', display: 'summarized' }, effort: 'low' },
    { model: 'claude-sonnet-5-5', thinking: { type: 'between_tools', budget_tokens: 500 }, effort: 'low' },
    { model: 'claude-haiku-5-5', thinking: { type: 'disabled' }, effort: 'xhigh' },
    { model: 'claude-haiku-5-5', thinking: { type: 'disabled' }, effort: 'max' },
    { model: 'claude-sonnet-5-5', temperature: 0.5 },
    { model: 'claude-haiku-5-5', top_p: 0.9 },
    { model: 'claude-haiku-5-5', top_k: 40 },
  ];

  for (const invalid of invalidCases) {
    assert.throws(
      () => validateClaudeThinkingConfig(invalid),
      (err) => err instanceof AiError && err.kind === 'invalid_request' && err.status === 400,
      `Expected 400 validation failure for ${JSON.stringify(invalid)}`,
    );
  }

  // Every configured task in AI_TASK_CONFIG must resolve to a valid Claude & Gemini configuration
  for (const taskKey of Object.keys(AI_TASK_CONFIG)) {
    const resolvedClaude = resolveTaskSettings(taskKey, 'claude');
    assert.ok(typeof resolvedClaude.maxTokens === 'number' && resolvedClaude.maxTokens > 0);
    assert.doesNotThrow(() =>
      validateClaudeThinkingConfig({
        model: resolvedClaude.model,
        thinking: resolvedClaude.claude?.thinking,
        effort: resolvedClaude.claude?.effort,
      }),
    );

    const resolvedGemini = resolveTaskSettings(taskKey, 'gemini');
    assert.equal(resolvedGemini.model, 'gemini-flash-latest');
  }
});
