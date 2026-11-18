import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { getFirestore } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions';
import { MaskingSession } from '../privacy/masking_session.js';
import { maskText } from '../privacy/anonymizer_service.js';
import { loadPeopleForCaller } from '../privacy/people_loader.js';
import {
  PRIVACY_TOKEN_INSTRUCTION,
  callAiSafely,
} from '../privacy/safe_ai.js';
import { setGeminiGenerateContentForTest } from '../ai/gemini_provider.js';
import { resolveSchoolDomain } from '../school/sync.js';
import {
  chatWithTutor,
  generateQuiz,
  analyzeWeakArea,
  analyzeAssignmentSubmission,
} from '../index.js';

// ---------------------------------------------------------------------------
// In-memory Firestore harness for privacy & callable tests
// ---------------------------------------------------------------------------
const isPlain = (v) => v && Object.getPrototypeOf(v) === Object.prototype;
const cloneData = (v) => {
  if (Array.isArray(v)) return v.map(cloneData);
  if (isPlain(v)) {
    const out = {};
    for (const [k, val] of Object.entries(v)) out[k] = cloneData(val);
    return out;
  }
  return v;
};

const store = new Map();
const readPaths = [];
let failFirestoreReads = false;

function resetTestEnv() {
  store.clear();
  readPaths.length = 0;
  failFirestoreReads = false;
  setGeminiGenerateContentForTest(null);
}

const db = getFirestore();
logger.error = () => {};
logger.warn = () => {};
logger.info = () => {};

db.collection = (col) => ({
  doc: (id) => {
    const path = `${col}/${id}`;
    return {
      id,
      path,
      ref: { id, path },
      get: async () => {
        if (failFirestoreReads && col !== 'ai_usage') {
          throw new Error('Simulated Firestore read failure');
        }
        readPaths.push(path);
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
          store.set(path, { ...store.get(path), ...data });
        } else {
          store.set(path, cloneData(data));
        }
      },
      update: async (fields) => {
        const cur = store.get(path) ?? {};
        store.set(path, { ...cur, ...fields });
      },
    };
  },
  where: (field, op, val) => ({
    limit: () => ({
      get: async () => {
        if (failFirestoreReads) {
          throw new Error('Simulated Firestore query failure');
        }
        readPaths.push(`${col}?${field}${op}${val}`);
        const docs = [];
        for (const [path, d] of store.entries()) {
          if (!path.startsWith(`${col}/`)) continue;
          let match = false;
          if (op === '==' && d[field] === val) match = true;
          if (op === 'array-contains' && Array.isArray(d[field]) && d[field].includes(val)) match = true;
          if (match) {
            const id = path.slice(col.length + 1);
            docs.push({
              id,
              ref: { id, path },
              data: () => cloneData(d),
            });
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
    readPaths.push(ref.path);
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
    set: (ref, data, opts) => {
      if (opts?.merge && store.has(ref.path)) {
        store.set(ref.path, { ...store.get(ref.path), ...data });
      } else {
        store.set(ref.path, cloneData(data));
      }
    },
    update: (ref, data) => {
      const cur = store.get(ref.path) ?? {};
      store.set(ref.path, { ...cur, ...data });
    },
  };
  return await callback(tx);
};

// ---------------------------------------------------------------------------
// 1. Shared Fixture Parity Test (Dart <-> JS)
// ---------------------------------------------------------------------------
test('Shared fixture test_fixtures/privacy_cases.json matches JS maskText and restore', () => {
  const raw = readFileSync(
    new URL('../../test_fixtures/privacy_cases.json', import.meta.url),
    'utf8',
  );
  const cases = JSON.parse(raw);

  for (const c of cases) {
    const session = new MaskingSession();
    const masked = maskText(c.input, c.people, session, {
      extraPatterns: c.extraPatterns ?? [],
    });
    const restored = session.restore(masked);

    assert.equal(masked, c.expectedMasked, `masked mismatch in ${c.id}`);
    assert.equal(restored, c.expectedRestored, `restored mismatch in ${c.id}`);
  }
});

// ---------------------------------------------------------------------------
// 2. School Domain Resolution & Isolation Tests
// ---------------------------------------------------------------------------
test('resolveSchoolDomain matches firestore.rules inDomain/isTester semantics', async () => {
  resetTestEnv();
  store.set('schools/tokyo.ac.jp', { name: '東京専門学校', courses: ['IT'] });
  store.set('school_testers/pilot@gmail.com', { domain: 'tokyo.ac.jp' });

  // Verified school email
  assert.equal(
    await resolveSchoolDomain(
      { uid: 'u1', token: { email: 'student@tokyo.ac.jp', email_verified: true } },
      { db },
    ),
    'tokyo.ac.jp',
  );

  // Unverified school email -> null
  assert.equal(
    await resolveSchoolDomain(
      { uid: 'u1', token: { email: 'student@tokyo.ac.jp', email_verified: false } },
      { db },
    ),
    null,
  );

  // Pilot tester Gmail -> mapped school domain
  assert.equal(
    await resolveSchoolDomain(
      { uid: 'u2', token: { email: 'pilot@gmail.com', email_verified: true } },
      { db },
    ),
    'tokyo.ac.jp',
  );

  // Regular unlinked Gmail -> null (not an error)
  assert.equal(
    await resolveSchoolDomain(
      { uid: 'u3', token: { email: 'regular@gmail.com', email_verified: true } },
      { db },
    ),
    null,
  );
});

test('loadPeopleForCaller isolates school data and never reads another school domain', async () => {
  resetTestEnv();

  // School A (caller's school)
  store.set('schools/alpha.ac.jp', {
    name: 'Alpha School',
    courses: ['AI'],
    teacherProfiles: {
      't1@alpha.ac.jp': { name: '大谷翔平' },
    },
  });
  // School B (foreign school — must NEVER be read)
  store.set('schools/beta.ac.jp', {
    name: 'Beta School',
    courses: ['AI'],
    teacherProfiles: {
      't2@beta.ac.jp': { name: '秘密先生' },
    },
  });

  store.set('users/student_alpha', {
    name: '山田太郎',
    grade: '1',
    course: 'AI',
    schoolDomain: 'alpha.ac.jp',
  });
  store.set('timetables/tt_1', {
    userId: 'student_alpha',
    teacher: '佐藤先生',
    subject: '数学',
  });

  const auth = {
    uid: 'student_alpha',
    token: { email: 'taro@alpha.ac.jp', email_verified: true },
  };
  const people = await loadPeopleForCaller(auth, { db });
  const names = people.map((p) => p.fullName);

  assert.ok(names.includes('山田太郎'));
  assert.ok(names.includes('大谷翔平'));
  assert.ok(names.includes('佐藤'));
  assert.ok(!names.includes('秘密'), 'Foreign school teacher must not be loaded');
  assert.ok(
    !readPaths.some((p) => p.includes('beta.ac.jp')),
    'Must never touch Firestore paths belonging to beta.ac.jp',
  );
});

test('loadPeopleForCaller succeeds for unlinked personal account without school domain', async () => {
  resetTestEnv();
  store.set('users/solo_uid', { name: '個人学習者' });
  store.set('timetables/tt_solo', {
    userId: 'solo_uid',
    teacher: '田中講師',
    subject: '英語',
  });

  const people = await loadPeopleForCaller(
    { uid: 'solo_uid', token: { email: 'solo@gmail.com', email_verified: true } },
    { db },
  );
  const names = people.map((p) => p.fullName);

  assert.deepEqual(names, ['個人学習者', '田中講師']);
});

// ---------------------------------------------------------------------------
// 3. callAiSafely Unit Tests (fail-closed, timeout, multi-turn, inlineData)
// ---------------------------------------------------------------------------
test('15. callAiSafely is fail-closed when roster load fails (Gemini is never called)', async () => {
  resetTestEnv();
  failFirestoreReads = true;
  let geminiCalled = false;

  await assert.rejects(
    () =>
      callAiSafely(
        { model: 'gemini-flash-latest', contents: '山田太郎です' },
        {
          auth: { uid: 'u1', token: { email: 'a@b.com', email_verified: true } },
          db,
          generateContent: async () => {
            geminiCalled = true;
            return { text: 'ok' };
          },
          japaneseFallback: 'エラー',
        },
      ),
    (err) => err.code === 'unavailable',
  );

  assert.equal(geminiCalled, false, 'Gemini must not be called when roster fails');
});

test('16. callAiSafely is fail-closed on roster load timeout', async () => {
  resetTestEnv();
  let geminiCalled = false;
  const hangingDb = {
    collection: () => ({
      doc: () => ({
        get: () => new Promise(() => {}), // never resolves
      }),
      where: () => ({
        limit: () => ({
          get: () => new Promise(() => {}),
        }),
      }),
    }),
  };

  await assert.rejects(
    () =>
      callAiSafely(
        { model: 'gemini-flash-latest', contents: '山田太郎です' },
        {
          auth: { uid: 'u1', token: { email: 'a@b.com', email_verified: true } },
          db: hangingDb,
          timeoutMs: 30,
          generateContent: async () => {
            geminiCalled = true;
            return { text: 'ok' };
          },
        },
      ),
    (err) => err.code === 'unavailable',
  );

  assert.equal(geminiCalled, false, 'Gemini must not be called on timeout');
});

test('17. callAiSafely prepends privacy token rule to systemInstruction and keeps consistent tokens across multi-message history', async () => {
  resetTestEnv();
  store.set('users/u1', { name: '山田太郎' });
  store.set('timetables/tt1', { userId: 'u1', teacher: '鈴木一郎' });

  let capturedConfig = null;
  const result = await callAiSafely(
    {
      model: 'gemini-flash-latest',
      contents: [
        { role: 'user', parts: [{ text: '山田太郎が鈴木一郎先生に質問した' }] },
        { role: 'model', parts: [{ text: '鈴木一郎先生の授業ですね' }] },
        { role: 'user', parts: [{ text: 'はい、山田太郎の連絡先は 090-1234-5678 です' }] },
      ],
      config: { systemInstruction: 'You are Planner Bot.' },
    },
    {
      auth: { uid: 'u1', token: { email: 'u1@gmail.com', email_verified: true } },
      db,
      generateContent: async (cfg) => {
        capturedConfig = cfg;
        return { text: '[STUDENT_1]さん、[TEACHER_1]先生に確認しましょう。' };
      },
    },
  );

  assert.ok(capturedConfig.config.systemInstruction.includes(PRIVACY_TOKEN_INSTRUCTION));
  assert.ok(capturedConfig.config.systemInstruction.includes('You are Planner Bot.'));

  const serialized = JSON.stringify(capturedConfig.contents);
  assert.ok(!serialized.includes('山田太郎'));
  assert.ok(!serialized.includes('鈴木一郎'));
  assert.ok(!serialized.includes('090-1234-5678'));

  // Same token used across all turns in contents
  assert.equal(
    capturedConfig.contents[0].parts[0].text,
    '[STUDENT_1]が[TEACHER_1]先生に質問した',
  );
  assert.equal(
    capturedConfig.contents[1].parts[0].text,
    '[TEACHER_1]先生の授業ですね',
  );
  assert.equal(
    capturedConfig.contents[2].parts[0].text,
    'はい、[STUDENT_1]の連絡先は [PHONE_1] です',
  );

  // Restored reply
  assert.equal(result.text, '山田太郎さん、鈴木一郎先生に確認しましょう。');
  assert.deepEqual(result.warnings, []);
});

test('inlineData parts are preserved while accompanying text parts are masked', async () => {
  resetTestEnv();
  store.set('users/u1', { name: '山田太郎' });

  let capturedContents = null;
  await callAiSafely(
    {
      model: 'gemini-flash-latest',
      contents: [
        {
          role: 'user',
          parts: [
            { text: '提出者: 山田太郎 (090-1111-2222)' },
            { inlineData: { mimeType: 'image/png', data: 'iVBORw0KGgoAAAANSUhEUg==' } },
          ],
        },
      ],
    },
    {
      auth: { uid: 'u1', token: { email: 'u1@gmail.com', email_verified: true } },
      db,
      generateContent: async (cfg) => {
        capturedContents = cfg.contents;
        return { text: '{}' };
      },
    },
  );

  assert.equal(capturedContents[0].parts[0].text, '提出者: [STUDENT_1] ([PHONE_1])');
  assert.deepEqual(capturedContents[0].parts[1], {
    inlineData: { mimeType: 'image/png', data: 'iVBORw0KGgoAAAANSUhEUg==' },
  });
});

// ---------------------------------------------------------------------------
// 4. All 4 Cloud Functions Callables End-to-End Privacy Verification
// ---------------------------------------------------------------------------
test('14. All 4 AI callables (chatWithTutor, generateQuiz, analyzeWeakArea, analyzeAssignmentSubmission) strip real names before calling Gemini', async () => {
  resetTestEnv();
  store.set('schools/kosen.ac.jp', {
    name: '高専',
    courses: ['情報'],
    teacherProfiles: {
      't@kosen.ac.jp': { name: '高橋誠' },
    },
  });
  store.set('users/student_1', {
    name: '山田太郎',
    grade: '2',
    course: '情報',
    schoolDomain: 'kosen.ac.jp',
  });
  store.set('timetables/tt_s1', {
    userId: 'student_1',
    teacher: '渡辺先生',
    subject: '物理',
  });

  const auth = {
    uid: 'student_1',
    token: { email: 'taro@kosen.ac.jp', email_verified: true },
  };

  const capturedPayloads = [];

  // (A) chatWithTutor (including stray teacher field in classes & multi-turn history)
  setGeminiGenerateContentForTest(async (cfg) => {
    capturedPayloads.push({ fn: 'chatWithTutor', cfg });
    return { text: '[STUDENT_1]さん、[TEACHER_1]先生の物理を復習しましょう。' };
  });

  const chatRes = await chatWithTutor.run({
    auth,
    data: {
      botId: 'planner',
      message: '山田太郎です。高橋誠先生と渡辺先生の課題で困っています。電話は090-9999-8888です。',
      history: [
        { role: 'user', content: '昨日も山田太郎が質問しました' },
        { role: 'assistant', content: '山田太郎さん、こんにちは' },
      ],
      classes: [
        { subject: '物理', dayOfWeek: '月', period: 1, teacher: '高橋誠', room: '101' },
      ],
      assignments: [
        { subject: '物理', dueDate: '11/20', status: '未着手', progress: 0, title: '山田太郎のレポート' },
      ],
      language: 'ja',
    },
  });
  assert.equal(chatRes.reply, '山田太郎さん、高橋誠先生の物理を復習しましょう。');

  // (B) generateQuiz (with useSearch = true so both grounding and quiz stages run)
  setGeminiGenerateContentForTest(async (cfg) => {
    capturedPayloads.push({ fn: 'generateQuiz', cfg });
    if (cfg.config?.tools) {
      return { text: '[TEACHER_1]先生の講義ノート要約' };
    }
    return {
      text: JSON.stringify({
        questions: [
          {
            question: '[TEACHER_1]先生が出題した問題',
            choices: ['A', 'B', 'C', 'D'],
            answerIndex: 0,
            explanation: '[STUDENT_1]向けの解説',
          },
        ],
      }),
    };
  });

  const quizRes = await generateQuiz.run({
    auth,
    data: {
      subject: '物理',
      topic: '高橋誠先生の力学プリント (山田太郎)',
      useSearch: true,
      language: 'ja',
    },
  });
  assert.equal(quizRes.questions[0].question, '高橋誠先生が出題した問題');
  assert.equal(quizRes.questions[0].explanation, '山田太郎向けの解説');

  // (C) analyzeWeakArea
  setGeminiGenerateContentForTest(async (cfg) => {
    capturedPayloads.push({ fn: 'analyzeWeakArea', cfg });
    return { text: '[STUDENT_1]さんは物理を優先しましょう。' };
  });

  const weakRes = await analyzeWeakArea.run({
    auth,
    data: {
      stats: [
        { subject: '物理 (担当: 高橋誠, 生徒: 山田太郎)', totalCount: 3, completedCount: 0, overdueCount: 2, avgDifficulty: 4 },
      ],
      language: 'ja',
    },
  });
  assert.equal(weakRes.analysis, '山田太郎さんは物理を優先しましょう。');

  // (D) analyzeAssignmentSubmission (text/plain submission containing student & teacher names)
  setGeminiGenerateContentForTest(async (cfg) => {
    capturedPayloads.push({ fn: 'analyzeAssignmentSubmission', cfg });
    return {
      text: JSON.stringify({
        completionPercent: 80,
        missingParts: ['[TEACHER_1]先生指定のグラフ'],
        advice: '[STUDENT_1]さんは結論を追記してください。',
      }),
    };
  });

  const submissionText = '氏名: 山田太郎 / 担当: 高橋誠先生 / メール: taro@kosen.ac.jp\n本文: 実験結果の考察';
  const subRes = await analyzeAssignmentSubmission.run({
    auth,
    data: {
      subject: '物理',
      title: '山田太郎の実験レポート',
      description: '高橋誠先生へ提出',
      fileBase64: Buffer.from(submissionText, 'utf8').toString('base64'),
      mimeType: 'text/plain',
      language: 'ja',
    },
  });
  assert.equal(subRes.completionPercent, 80);
  assert.deepEqual(subRes.missingParts, ['高橋誠先生指定のグラフ']);
  assert.equal(subRes.advice, '山田太郎さんは結論を追記してください。');

  // Verify NO real names or PII reached Gemini in ANY of the 5 calls (2 for quiz + 3 others)
  assert.equal(capturedPayloads.length, 5);
  for (const { fn, cfg } of capturedPayloads) {
    const rawSent = JSON.stringify(cfg.contents);
    assert.ok(!rawSent.includes('山田太郎'), `Leaked 山田太郎 in ${fn}`);
    assert.ok(!rawSent.includes('高橋誠'), `Leaked 高橋誠 in ${fn}`);
    assert.ok(!rawSent.includes('渡辺'), `Leaked 渡辺 in ${fn}`);
    assert.ok(!rawSent.includes('090-9999-8888'), `Leaked phone in ${fn}`);
    assert.ok(!rawSent.includes('taro@kosen.ac.jp'), `Leaked email in ${fn}`);
  }
});
