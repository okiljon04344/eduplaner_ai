import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import sharp from 'sharp';
import { getFirestore } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions';
import {
  DEFAULT_SCHOOL_POLICY,
  POLICY_HISTORY_TTL_DAYS,
  canUserImportTimetable,
  canUserUseReplaceMode,
  isValidIsoDate,
  loadSchoolPolicy,
  normalizeSchoolPolicy,
  validateSafeRegexPattern,
  validateSchoolPolicyInput,
} from '../school/policy.js';
import { callAiSafely } from '../privacy/safe_ai.js';
import {
  MAX_SCHOOL_REGEX_INPUT_CHARS,
  boundedSchoolMatches,
  maskPiiPatterns,
} from '../privacy/pii_pattern_masker.js';
import { MaskingSession } from '../privacy/masking_session.js';
import { setGeminiGenerateContentForTest } from '../ai/gemini_provider.js';
import {
  redactImageForAi,
  setVisionClientForTest,
} from '../privacy/image_redactor.js';
import {
  analyzeAssignmentSubmission,
  analyzeWeakArea,
  chatWithTutor,
  generateQuiz,
  setSchoolPolicy,
} from '../index.js';

// ---------------------------------------------------------------------------
// In-memory Firestore harness with read-counting & transaction support
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
const reads = [];
const warnLogs = [];
const db = getFirestore();

logger.error = () => {};
logger.info = () => {};
logger.warn = (msg, meta) => {
  warnLogs.push({ msg, meta: cloneData(meta) });
};

function setupDb() {
  db.collection = (col) => ({
    doc: (id) => {
      const path = `${col}/${id}`;
      return {
        id,
        path,
        ref: { id, path },
        get: async () => {
          reads.push(path);
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
          reads.push(`${col}?${field}${op}${val}`);
          const docs = [];
          for (const [path, d] of store.entries()) {
            if (!path.startsWith(`${col}/`)) continue;
            let match = false;
            if (op === '==' && d[field] === val) match = true;
            if (op === 'array-contains' && Array.isArray(d[field]) && d[field].includes(val)) {
              match = true;
            }
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

  db.getAll = async (...refs) =>
    refs.map((ref) => {
      reads.push(ref.path);
      const d = store.get(ref.path);
      return {
        exists: d !== undefined,
        id: ref.id,
        ref,
        data: () => (d ? cloneData(d) : undefined),
      };
    });

  db.runTransaction = async (callback) => {
    const pendingWrites = [];
    const tx = {
      get: async (ref) => {
        reads.push(ref.path);
        const d = store.get(ref.path);
        return {
          exists: d !== undefined,
          id: ref.id,
          ref,
          data: () => (d ? cloneData(d) : undefined),
        };
      },
      set: (ref, data, opts) => {
        pendingWrites.push({ type: 'set', path: ref.path, data: cloneData(data), opts });
      },
      update: (ref, data) => {
        pendingWrites.push({ type: 'update', path: ref.path, data: cloneData(data) });
      },
    };
    const result = await callback(tx);
    for (const w of pendingWrites) {
      if (w.type === 'set') {
        if (w.opts?.merge && store.has(w.path)) {
          store.set(w.path, { ...store.get(w.path), ...w.data });
        } else {
          store.set(w.path, w.data);
        }
      } else if (w.type === 'update') {
        const cur = store.get(w.path) ?? {};
        store.set(w.path, { ...cur, ...w.data });
      }
    }
    return result;
  };
}

function resetHarness() {
  setupDb();
  store.clear();
  reads.length = 0;
  warnLogs.length = 0;
  setGeminiGenerateContentForTest(null);
  setVisionClientForTest(null);
}

// ---------------------------------------------------------------------------
// Image helpers
// ---------------------------------------------------------------------------
async function createTestPng({ width = 420, height = 300, bg = '#FFFFFF' } = {}) {
  return sharp({ create: { width, height, channels: 3, background: bg } }).png().toBuffer();
}

async function readPixelRgb(buffer, x, y) {
  const { data, info } = await sharp(buffer).raw().toBuffer({ resolveWithObject: true });
  const idx = (y * info.width + x) * info.channels;
  return [data[idx], data[idx + 1], data[idx + 2]];
}

function makeWord(text, left, top, right, bottom, breakType = null) {
  const step = (right - left) / Math.max(1, text.length);
  const symbols = [...text].map((ch, idx) => {
    const sLeft = Math.round(left + idx * step);
    const sRight = Math.round(left + (idx + 1) * step);
    const sym = {
      text: ch,
      boundingBox: {
        vertices: [
          { x: sLeft, y: top },
          { x: sRight, y: top },
          { x: sRight, y: bottom },
          { x: sLeft, y: bottom },
        ],
      },
    };
    if (idx === text.length - 1 && breakType) {
      sym.property = { detectedBreak: { type: breakType } };
    }
    return sym;
  });
  return { symbols };
}

function buildVisionAnnotation(paragraphs) {
  return {
    fullTextAnnotation: {
      pages: [{ blocks: [{ paragraphs: paragraphs.map((words) => ({ words })) }] }],
    },
  };
}

// ---------------------------------------------------------------------------
// 1. Default policy & missing policy behavior
// ---------------------------------------------------------------------------
test('Missing schools/{domain}.policy returns DEFAULT_SCHOOL_POLICY with zero warnings', async () => {
  resetHarness();
  store.set('schools/tokyo.ac.jp', { name: 'Tokyo School', admins: ['admin_1'] });

  const policy = await loadSchoolPolicy('tokyo.ac.jp', { db });
  assert.deepEqual(policy, DEFAULT_SCHOOL_POLICY);
  assert.equal(warnLogs.length, 0);

  // Unlinked (null domain) also returns defaults with 0 DB reads and 0 warnings
  const nullPolicy = await loadSchoolPolicy(null, { db });
  assert.deepEqual(nullPolicy, DEFAULT_SCHOOL_POLICY);
  assert.equal(warnLogs.length, 0);
});

// ---------------------------------------------------------------------------
// 2. Resilient normalization on corrupted policy data
// ---------------------------------------------------------------------------
test('Corrupted policy falls back field-by-field to defaults and logs field names ONLY (never values)', () => {
  resetHarness();
  const secretCorruptValue = 'SECRET_CORRUPT_VALUE_XYZ';

  const normalized = normalizeSchoolPolicy(
    {
      schemaVersion: 99,
      disableMasking: true,
      timetableImport: {
        allowedImporters: secretCorruptValue,
        replaceMode: 'allowed',
        undoWindowDays: 999,
        schoolDays: ['月', 'INVALID_DAY'],
        closedDateRanges: [
          { start: '2026-08-01', end: '2026-08-15', label: '夏休み' },
          { start: '2026-09-10', end: '2026-09-01', label: '逆転範囲' },
        ],
        excludeNationalHolidays: 'yes',
      },
      privacy: {
        studentIdPatterns: ['\\bS\\d{6}\\b', '(a+)+$'],
        extraRedactionLabels: ['生徒番号', ''],
        extraHonorificExceptions: ['部長'],
        failOpen: true,
      },
    },
    { domain: 'tokyo.ac.jp' },
  );

  // Valid fields preserved
  assert.equal(normalized.timetableImport.replaceMode, 'allowed');
  assert.deepEqual(normalized.timetableImport.schoolDays, ['月']);
  assert.deepEqual(normalized.timetableImport.closedDateRanges, [
    { start: '2026-08-01', end: '2026-08-15', label: '夏休み' },
  ]);
  assert.deepEqual(normalized.privacy.studentIdPatterns, ['\\bS\\d{6}\\b']);
  assert.deepEqual(normalized.privacy.extraRedactionLabels, ['生徒番号']);
  assert.deepEqual(normalized.privacy.extraHonorificExceptions, ['部長']);

  // Corrupted fields fell back to defaults
  assert.equal(normalized.schemaVersion, 1);
  assert.equal(normalized.timetableImport.allowedImporters, 'homeroom_and_admins');
  assert.equal(normalized.timetableImport.undoWindowDays, 7);
  assert.equal(normalized.timetableImport.excludeNationalHolidays, true);

  // Logged warning contains field names ONLY, never values
  assert.equal(warnLogs.length, 1);
  const loggedJson = JSON.stringify(warnLogs[0]);
  assert.ok(!loggedJson.includes(secretCorruptValue), 'Must never log corrupted field values');
  assert.ok(warnLogs[0].meta.fields.includes('timetableImport.allowedImporters'));
  assert.ok(warnLogs[0].meta.fields.includes('timetableImport.undoWindowDays'));
  assert.ok(warnLogs[0].meta.fields.includes('privacy.studentIdPatterns'));
  assert.ok(warnLogs[0].meta.fields.includes('unknown.disableMasking'));
  assert.ok(warnLogs[0].meta.fields.includes('privacy.unknown.failOpen'));
});

// ---------------------------------------------------------------------------
// 3. ReDoS & strict schema validation
// ---------------------------------------------------------------------------
test('validateSafeRegexPattern rejects ReDoS & dangerous regexes and accepts safe student ID patterns', () => {
  const unsafe = [
    '(a+)+$',
    '([a-z]+)*',
    '(a|a)+',
    '(?:\\d+)+',
    '(?:19|20)+\\d{2}',
    '(?=\\d)S\\d{6}',
    '(?!admin)\\w+',
    '(?<=id:)\\d+',
    '(\\d+)\\1',
    'a*', // matches empty string
    '\\d{1000}',
    'S'.repeat(101),
    '',
  ];
  for (const pat of unsafe) {
    const res = validateSafeRegexPattern(pat);
    assert.equal(res.ok, false, `Expected unsafe regex to be rejected: ${pat}`);
  }

  const safe = [
    '\\bS\\d{6}\\b',
    '[A-Z]{2}\\d{4,6}',
    '(?:19|20)\\d{2}-\\d{4}',
    'STU-\\d{5,8}',
    '[0-9]{2}[A-Z][0-9]{4}',
  ];
  for (const pat of safe) {
    const res = validateSafeRegexPattern(pat);
    assert.equal(res.ok, true, `Expected safe regex to be accepted: ${pat} (${res.reason})`);
  }
});

test('validateSchoolPolicyInput rejects unknown fields, privacy relaxation attempts, and invalid dates/ranges', () => {
  // Reject unknown top-level & privacy-weakening keys
  for (const badPayload of [
    { disableMasking: true },
    { privacy: { failOpen: true } },
    { privacy: { skipRedaction: true } },
    { privacy: { allowRawImage: true } },
    { timetableImport: { unknownSetting: 1 } },
    { timetableImport: { undoWindowDays: 0 } },
    { timetableImport: { undoWindowDays: 31 } },
    { timetableImport: { undoWindowDays: 1.5 } },
    { timetableImport: { schoolDays: [] } },
    { timetableImport: { schoolDays: ['月', '月'] } },
    { timetableImport: { schoolDays: ['Mon'] } },
    { timetableImport: { allowedImporters: 'everyone' } },
    { timetableImport: { replaceMode: 'force_all' } },
    { timetableImport: { closedDateRanges: [{ start: '2026-08-20', end: '2026-08-10' }] } },
    { timetableImport: { closedDateRanges: [{ start: '2026-02-30', end: '2026-03-01' }] } },
    { privacy: { studentIdPatterns: ['(a+)+$'] } },
    { privacy: { studentIdPatterns: Array.from({ length: 11 }, (_, i) => `ID${i}\\d{4}`) } },
    { privacy: { extraRedactionLabels: [''] } },
  ]) {
    assert.throws(
      () => validateSchoolPolicyInput(badPayload),
      (err) => err.code === 'invalid-argument',
      `Expected invalid-argument for ${JSON.stringify(badPayload)}`,
    );
  }

  assert.equal(isValidIsoDate('2026-02-28'), true);
  assert.equal(isValidIsoDate('2026-02-29'), false);
  assert.equal(isValidIsoDate('2028-02-29'), true);

  // Partial update fills remaining defaults
  const valid = validateSchoolPolicyInput({
    timetableImport: {
      undoWindowDays: 14,
      closedDateRanges: [{ start: '2026-08-10', end: '2026-08-20', label: '夏期休業' }],
    },
    privacy: {
      studentIdPatterns: ['\\bS\\d{6}\\b'],
    },
  });
  assert.equal(valid.schemaVersion, 1);
  assert.equal(valid.timetableImport.allowedImporters, 'homeroom_and_admins');
  assert.equal(valid.timetableImport.undoWindowDays, 14);
  assert.deepEqual(valid.privacy.studentIdPatterns, ['\\bS\\d{6}\\b']);
});

// ---------------------------------------------------------------------------
// 4. setSchoolPolicy callable + audit history + TTL
// ---------------------------------------------------------------------------
test('setSchoolPolicy rejects non-admins and records audited update with 365d TTL for admins', async () => {
  resetHarness();
  store.set('schools/tokyo.ac.jp', {
    name: 'Tokyo School',
    admins: ['admin_uid'],
    teachers: ['teacher@tokyo.ac.jp'],
  });

  // Unauthenticated
  await assert.rejects(
    () => setSchoolPolicy.run({ auth: null, data: {} }),
    (err) => err.code === 'unauthenticated',
  );

  // Regular teacher (non-admin) -> permission-denied
  await assert.rejects(
    () =>
      setSchoolPolicy.run({
        auth: { uid: 'teacher_uid', token: { email: 'teacher@tokyo.ac.jp', email_verified: true } },
        data: { policy: { timetableImport: { allowedImporters: 'all_teachers' } } },
      }),
    (err) => err.code === 'permission-denied',
  );

  // Student -> permission-denied
  await assert.rejects(
    () =>
      setSchoolPolicy.run({
        auth: { uid: 'student_uid', token: { email: 'student@tokyo.ac.jp', email_verified: true } },
        data: { policy: { timetableImport: { allowedImporters: 'all_teachers' } } },
      }),
    (err) => err.code === 'permission-denied',
  );

  // Admin succeeds
  const res = await setSchoolPolicy.run({
    auth: { uid: 'admin_uid', token: { email: 'Admin@Tokyo.ac.jp', email_verified: true } },
    data: {
      policy: {
        timetableImport: {
          allowedImporters: 'all_teachers',
          replaceMode: 'disabled',
          undoWindowDays: 10,
          notifyStudentsDefault: true,
        },
        privacy: {
          studentIdPatterns: ['\\bS\\d{6}\\b'],
          extraRedactionLabels: ['生徒番号'],
          extraHonorificExceptions: ['部長'],
        },
      },
    },
  });

  assert.equal(res.policy.timetableImport.allowedImporters, 'all_teachers');
  assert.equal(res.policy.timetableImport.replaceMode, 'disabled');
  assert.equal(res.policy.timetableImport.undoWindowDays, 10);
  assert.ok(res.historyId.startsWith('tokyo.ac.jp_'));

  const savedSchool = store.get('schools/tokyo.ac.jp');
  assert.deepEqual(savedSchool.policy, res.policy);

  const historyDoc = store.get(`school_policy_history/${res.historyId}`);
  assert.ok(historyDoc, 'Audit history document must be written');
  assert.equal(historyDoc.domain, 'tokyo.ac.jp');
  assert.equal(historyDoc.changedByUid, 'admin_uid');
  assert.equal(historyDoc.changedByEmail, 'admin@tokyo.ac.jp');
  assert.deepEqual(historyDoc.previousPolicy, DEFAULT_SCHOOL_POLICY);
  assert.deepEqual(historyDoc.nextPolicy, res.policy);

  const ttlMs = historyDoc.expiresAt.getTime() - historyDoc.createdAt.getTime();
  assert.equal(ttlMs, POLICY_HISTORY_TTL_DAYS * 86_400_000);
});

// ---------------------------------------------------------------------------
// 5. loadSchoolPolicy caching
// ---------------------------------------------------------------------------
test('loadSchoolPolicy caches per domain and isolates returned clones', async () => {
  resetHarness();
  store.set('schools/tokyo.ac.jp', {
    name: 'Tokyo School',
    policy: {
      schemaVersion: 1,
      privacy: { studentIdPatterns: ['\\bS\\d{6}\\b'] },
    },
  });

  const cache = new Map();
  const first = await loadSchoolPolicy('tokyo.ac.jp', { db, cache });
  first.privacy.studentIdPatterns.push('MUTATED');

  const second = await loadSchoolPolicy('tokyo.ac.jp', { db, cache });
  assert.equal(reads.filter((p) => p === 'schools/tokyo.ac.jp').length, 1);
  assert.deepEqual(second.privacy.studentIdPatterns, ['\\bS\\d{6}\\b']);
});

// ---------------------------------------------------------------------------
// 6. Privacy wiring: callGeminiSafely + redactImageForAi + analyzeAssignmentSubmission
// ---------------------------------------------------------------------------
test('callAiSafely applies school studentIdPatterns & extraHonorificExceptions while preserving default masking', async () => {
  resetHarness();
  store.set('schools/kosen.ac.jp', {
    name: '高専',
    courses: ['AI'],
    policy: {
      schemaVersion: 1,
      privacy: {
        studentIdPatterns: ['\\bS\\d{6}\\b'],
        extraHonorificExceptions: ['部長'],
      },
    },
  });
  store.set('users/u_stu', { name: '山田太郎', grade: '1', course: 'AI' });

  let sentPrompt = '';
  const res = await callAiSafely(
    {
      model: 'gemini-flash-latest',
      contents: '学籍 S202601 の山田太郎と部長さんと佐藤さんが参加した',
    },
    {
      auth: { uid: 'u_stu', token: { email: 'taro@kosen.ac.jp', email_verified: true } },
      db,
      generateContent: async (cfg) => {
        sentPrompt = cfg.contents;
        return { text: '[STUDENT_ID_1] の [STUDENT_1] と部長さんと[PERSON_1]さん' };
      },
    },
  );

  assert.ok(!sentPrompt.includes('S202601'));
  assert.ok(!sentPrompt.includes('山田太郎'));
  assert.ok(!sentPrompt.includes('佐藤'));
  assert.ok(sentPrompt.includes('[STUDENT_ID_1]'));
  assert.ok(sentPrompt.includes('[STUDENT_1]'));
  assert.ok(sentPrompt.includes('部長さん'), 'extraHonorificExceptions should leave 部長さん unmasked');
  assert.equal(res.text, 'S202601 の 山田太郎 と部長さんと佐藤さん');
});

test('redactImageForAi & analyzeAssignmentSubmission redact extraLabels and studentIdPatterns in addition to defaults', async () => {
  resetHarness();
  store.set('schools/kosen.ac.jp', {
    name: '高専',
    courses: ['AI'],
    policy: {
      schemaVersion: 1,
      privacy: {
        studentIdPatterns: ['\\bS\\d{6}\\b'],
        extraRedactionLabels: ['生徒番号'],
      },
    },
  });
  store.set('users/u_stu', { name: '山田太郎', grade: '1', course: 'AI' });

  const originalPng = await createTestPng({ width: 420, height: 300 });

  // OCR lines:
  // 1) Custom label `生徒番号` at y=30..50 -> right side (x=150..270) should be blacked out
  // 2) Student ID matching policy pattern `S202601` at x=30..130, y=120..145 -> blacked out
  // 3) Default name `山田太郎` at x=30..130, y=200..225 -> blacked out
  // 4) Unrelated math `x + 1 = 2` at x=250..360, y=240..265 -> remains white
  setVisionClientForTest({
    documentTextDetection: async () => [
      buildVisionAnnotation([
        [makeWord('生徒番号', 30, 30, 120, 50, 'EOL_SURE_SPACE')],
        [makeWord('S202601', 30, 120, 130, 145, 'EOL_SURE_SPACE')],
        [makeWord('山田太郎', 30, 200, 130, 225, 'EOL_SURE_SPACE')],
        [makeWord('x + 1 = 2', 250, 240, 360, 265, 'EOL_SURE_SPACE')],
      ]),
    ],
  });

  // Direct redactImageForAi test
  const redactedDirect = await redactImageForAi(
    originalPng,
    'image/png',
    [{ id: 'u_stu', fullName: '山田太郎', role: 'student', parts: [] }],
    {
      extraLabels: ['生徒番号'],
      extraPatterns: ['\\bS\\d{6}\\b'],
    },
  );
  assert.deepEqual(await readPixelRgb(redactedDirect.buffer, 170, 40), [0, 0, 0]);
  assert.deepEqual(await readPixelRgb(redactedDirect.buffer, 80, 132), [0, 0, 0]);
  assert.deepEqual(await readPixelRgb(redactedDirect.buffer, 80, 212), [0, 0, 0]);
  assert.deepEqual(await readPixelRgb(redactedDirect.buffer, 300, 252), [255, 255, 255]);

  // End-to-end analyzeAssignmentSubmission test loading policy from Firestore
  let geminiSentPng = null;
  setGeminiGenerateContentForTest(async (cfg) => {
    geminiSentPng = Buffer.from(cfg.contents[0].parts[1].inlineData.data, 'base64');
    return {
      text: JSON.stringify({
        completionPercent: 95,
        missingParts: [],
        advice: '[STUDENT_1]さん、よくできました。',
      }),
    };
  });

  const subRes = await analyzeAssignmentSubmission.run({
    auth: { uid: 'u_stu', token: { email: 'taro@kosen.ac.jp', email_verified: true } },
    data: {
      subject: '数学',
      title: '山田太郎 (S202601) の課題',
      fileBase64: originalPng.toString('base64'),
      mimeType: 'image/png',
      language: 'ja',
    },
  });

  assert.equal(subRes.completionPercent, 95);
  assert.equal(subRes.advice, '山田太郎さん、よくできました。');
  assert.deepEqual(await readPixelRgb(geminiSentPng, 170, 40), [0, 0, 0]);
  assert.deepEqual(await readPixelRgb(geminiSentPng, 80, 132), [0, 0, 0]);
  assert.deepEqual(await readPixelRgb(geminiSentPng, 80, 212), [0, 0, 0]);
  assert.deepEqual(await readPixelRgb(geminiSentPng, 300, 252), [255, 255, 255]);
});

// ---------------------------------------------------------------------------
// 7. Importer & replaceMode permission helpers across all policy modes
// ---------------------------------------------------------------------------
test('canUserImportTimetable enforces admins_only, homeroom_and_admins, and all_teachers', () => {
  const school = {
    admins: ['admin_1'],
    teachers: ['homeroom1a@s.ac.jp', 'other@s.ac.jp'],
    teacherProfiles: {
      'homeroom1a@s.ac.jp': { name: '佐藤', homeroom: { grade: 1, course: 'A' } },
      'other@s.ac.jp': { name: '鈴木', homeroom: null },
    },
  };

  const pAdmins = normalizeSchoolPolicy({ timetableImport: { allowedImporters: 'admins_only' } });
  assert.equal(canUserImportTimetable(school, pAdmins, 'admin_1', 'admin@s.ac.jp', 1, 'A'), true);
  assert.equal(canUserImportTimetable(school, pAdmins, 't1', 'homeroom1a@s.ac.jp', 1, 'A'), false);
  assert.equal(canUserImportTimetable(school, pAdmins, 't2', 'other@s.ac.jp', 1, 'A'), false);
  assert.equal(canUserImportTimetable(school, pAdmins, 's1', 'stu@s.ac.jp', 1, 'A'), false);

  const pHomeroom = normalizeSchoolPolicy({ timetableImport: { allowedImporters: 'homeroom_and_admins' } });
  assert.equal(canUserImportTimetable(school, pHomeroom, 'admin_1', 'admin@s.ac.jp', 2, 'B'), true);
  assert.equal(canUserImportTimetable(school, pHomeroom, 't1', 'homeroom1a@s.ac.jp', 1, 'A'), true);
  assert.equal(canUserImportTimetable(school, pHomeroom, 't1', 'homeroom1a@s.ac.jp', 2, 'A'), false);
  assert.equal(canUserImportTimetable(school, pHomeroom, 't1', 'homeroom1a@s.ac.jp', 1, 'B'), false);
  assert.equal(canUserImportTimetable(school, pHomeroom, 't2', 'other@s.ac.jp', 1, 'A'), false);
  assert.equal(canUserImportTimetable(school, pHomeroom, 's1', 'stu@s.ac.jp', 1, 'A'), false);

  const pAll = normalizeSchoolPolicy({ timetableImport: { allowedImporters: 'all_teachers' } });
  assert.equal(canUserImportTimetable(school, pAll, 'admin_1', 'admin@s.ac.jp', 1, 'A'), true);
  assert.equal(canUserImportTimetable(school, pAll, 't1', 'homeroom1a@s.ac.jp', 3, 'Z'), true);
  assert.equal(canUserImportTimetable(school, pAll, 't2', 'other@s.ac.jp', 1, 'A'), true);
  assert.equal(canUserImportTimetable(school, pAll, 's1', 'stu@s.ac.jp', 1, 'A'), false);
});

test('canUserUseReplaceMode enforces disabled, admins_only, and allowed', () => {
  const school = { admins: ['admin_1'], teachers: ['t@s.ac.jp'] };

  assert.equal(
    canUserUseReplaceMode(
      school,
      normalizeSchoolPolicy({ timetableImport: { replaceMode: 'disabled' } }),
      'admin_1',
    ),
    false,
  );
  assert.equal(
    canUserUseReplaceMode(
      school,
      normalizeSchoolPolicy({ timetableImport: { replaceMode: 'admins_only' } }),
      'admin_1',
    ),
    true,
  );
  assert.equal(
    canUserUseReplaceMode(
      school,
      normalizeSchoolPolicy({ timetableImport: { replaceMode: 'admins_only' } }),
      't_uid',
    ),
    false,
  );
  assert.equal(
    canUserUseReplaceMode(
      school,
      normalizeSchoolPolicy({ timetableImport: { replaceMode: 'allowed' } }),
      't_uid',
    ),
    true,
  );
});

// ---------------------------------------------------------------------------
// 8. setSchoolPolicy optimistic concurrency (two admins racing)
// ---------------------------------------------------------------------------
test('setSchoolPolicy enforces optimistic concurrency via revision & updatedAt and throws aborted on conflict', async () => {
  resetHarness();
  store.set('schools/tokyo.ac.jp', {
    name: 'Tokyo School',
    admins: ['admin_1', 'admin_2'],
  });

  // Admin 1 saves first policy -> revision becomes 1
  const first = await setSchoolPolicy.run({
    auth: { uid: 'admin_1', token: { email: 'a1@tokyo.ac.jp', email_verified: true } },
    data: {
      expectedRevision: 0,
      policy: { timetableImport: { undoWindowDays: 10 } },
    },
  });
  assert.equal(first.policy.revision, 1);
  assert.ok(typeof first.policy.updatedAt === 'string');

  // Ensure wall clock advances by >= 2ms so ISO updatedAt differs between revisions
  await new Promise((r) => setTimeout(r, 5));

  // Admin 2 reads revision 1, then Admin 1 saves revision 2
  const second = await setSchoolPolicy.run({
    auth: { uid: 'admin_1', token: { email: 'a1@tokyo.ac.jp', email_verified: true } },
    data: {
      expectedRevision: 1,
      policy: { timetableImport: { undoWindowDays: 14 } },
    },
  });
  assert.equal(second.policy.revision, 2);

  // Admin 2 attempts to save using stale expectedRevision=1 -> aborted
  await assert.rejects(
    () =>
      setSchoolPolicy.run({
        auth: { uid: 'admin_2', token: { email: 'a2@tokyo.ac.jp', email_verified: true } },
        data: {
          expectedRevision: 1,
          policy: { timetableImport: { undoWindowDays: 3 } },
        },
      }),
    (err) => err.code === 'aborted' && err.details?.reason === 'policy_changed',
  );

  // Admin 2 attempts to save using stale expectedUpdatedAt -> aborted
  await assert.rejects(
    () =>
      setSchoolPolicy.run({
        auth: { uid: 'admin_2', token: { email: 'a2@tokyo.ac.jp', email_verified: true } },
        data: {
          expectedUpdatedAt: first.policy.updatedAt,
          policy: { timetableImport: { undoWindowDays: 3 } },
        },
      }),
    (err) => err.code === 'aborted' && err.details?.reason === 'policy_changed',
  );

  // Verify revision 2 from Admin 1 was NOT overwritten
  assert.equal(store.get('schools/tokyo.ac.jp').policy.timetableImport.undoWindowDays, 14);
  assert.equal(store.get('schools/tokyo.ac.jp').policy.revision, 2);
});

// ---------------------------------------------------------------------------
// 9. Per-invocation cache isolation (no stale module-global cache across requests)
// ---------------------------------------------------------------------------
test('Policy changes take effect immediately on the next invocation in the same process', async () => {
  resetHarness();
  store.set('schools/kosen.ac.jp', {
    name: '高専',
    admins: ['admin_1'],
    courses: ['AI'],
    policy: {
      schemaVersion: 1,
      revision: 1,
      privacy: { studentIdPatterns: ['\\bOLD\\d{4}\\b'] },
    },
  });
  store.set('users/u_stu', { name: '山田太郎', grade: '1', course: 'AI' });

  const stuAuth = { uid: 'u_stu', token: { email: 'taro@kosen.ac.jp', email_verified: true } };
  const sentPrompts = [];
  setGeminiGenerateContentForTest(async (cfg) => {
    sentPrompts.push(String(cfg.contents));
    return { text: 'ok' };
  });

  // Invocation 1: NEW202601 is NOT masked under old policy
  await chatWithTutor.run({
    auth: stuAuth,
    data: { message: 'ID NEW202601 と OLD1234', language: 'ja' },
  });
  assert.ok(sentPrompts[0].includes('NEW202601'));
  assert.ok(!sentPrompts[0].includes('OLD1234'));

  // Admin updates policy on the same warm instance
  await setSchoolPolicy.run({
    auth: { uid: 'admin_1', token: { email: 'admin@kosen.ac.jp', email_verified: true } },
    data: {
      expectedRevision: 1,
      policy: {
        privacy: { studentIdPatterns: ['\\bNEW\\d{6}\\b'] },
      },
    },
  });

  // Invocation 2 on the SAME warm instance: must pick up NEW202601 immediately
  await chatWithTutor.run({
    auth: stuAuth,
    data: { message: 'ID NEW202601 です', language: 'ja' },
  });
  assert.ok(!sentPrompts[1].includes('NEW202601'));
  assert.ok(sentPrompts[1].includes('[STUDENT_ID_1]'));
});

// ---------------------------------------------------------------------------
// 10. Policy coverage across ALL 4 AI callables
// ---------------------------------------------------------------------------
test('All 4 AI callables (chatWithTutor, analyzeWeakArea, generateQuiz, analyzeAssignmentSubmission) enforce school policy privacy rules', async () => {
  resetHarness();
  store.set('schools/kosen.ac.jp', {
    name: '高専',
    courses: ['AI'],
    policy: {
      schemaVersion: 1,
      privacy: {
        studentIdPatterns: ['\\bS\\d{6}\\b'],
        extraRedactionLabels: ['生徒番号'],
        extraHonorificExceptions: ['部長'],
      },
    },
  });
  store.set('users/u_stu', { name: '山田太郎', grade: '1', course: 'AI' });

  const stuAuth = { uid: 'u_stu', token: { email: 'taro@kosen.ac.jp', email_verified: true } };
  const captured = [];

  // 1) chatWithTutor
  setGeminiGenerateContentForTest(async (cfg) => {
    captured.push({ fn: 'chatWithTutor', payload: JSON.stringify(cfg.contents) });
    return { text: '[STUDENT_ID_1] 部長さん [PERSON_1]さん' };
  });
  const chatRes = await chatWithTutor.run({
    auth: stuAuth,
    data: { message: 'S202601 部長さん 佐藤さん', language: 'ja' },
  });
  assert.equal(chatRes.reply, 'S202601 部長さん 佐藤さん');

  // 2) analyzeWeakArea
  setGeminiGenerateContentForTest(async (cfg) => {
    captured.push({ fn: 'analyzeWeakArea', payload: JSON.stringify(cfg.contents) });
    return { text: '[STUDENT_ID_1] 部長さん [PERSON_1]さん' };
  });
  const weakRes = await analyzeWeakArea.run({
    auth: stuAuth,
    data: {
      stats: [{ subject: 'S202601 部長さん 佐藤さん 数学', totalCount: 3, completedCount: 1, overdueCount: 1, avgDifficulty: 3 }],
      language: 'ja',
    },
  });
  assert.equal(weakRes.analysis, 'S202601 部長さん 佐藤さん');

  // 3) generateQuiz
  setGeminiGenerateContentForTest(async (cfg) => {
    captured.push({ fn: 'generateQuiz', payload: JSON.stringify(cfg.contents) });
    return {
      text: JSON.stringify({
        questions: [{
          question: '[STUDENT_ID_1] 部長さん [PERSON_1]さん',
          choices: ['A', 'B', 'C', 'D'],
          answerIndex: 0,
          explanation: '解説',
        }],
      }),
    };
  });
  const quizRes = await generateQuiz.run({
    auth: stuAuth,
    data: { subject: '数学', topic: 'S202601 部長さん 佐藤さん', language: 'ja' },
  });
  assert.equal(quizRes.questions[0].question, 'S202601 部長さん 佐藤さん');

  // 4) analyzeAssignmentSubmission (text/plain)
  setGeminiGenerateContentForTest(async (cfg) => {
    captured.push({ fn: 'analyzeAssignmentSubmission', payload: JSON.stringify(cfg.contents) });
    return {
      text: JSON.stringify({
        completionPercent: 85,
        missingParts: ['[PERSON_1]さん問題'],
        advice: '[STUDENT_ID_1] 部長さん OK',
      }),
    };
  });
  const subRes = await analyzeAssignmentSubmission.run({
    auth: stuAuth,
    data: {
      subject: '数学',
      fileBase64: Buffer.from('S202601 部長さん 佐藤さん の解答', 'utf8').toString('base64'),
      mimeType: 'text/plain',
      language: 'ja',
    },
  });
  assert.equal(subRes.advice, 'S202601 部長さん OK');
  assert.deepEqual(subRes.missingParts, ['佐藤さん問題']);

  assert.equal(captured.length, 4);
  for (const c of captured) {
    assert.ok(!c.payload.includes('S202601'), `S202601 leaked in ${c.fn}`);
    assert.ok(!c.payload.includes('佐藤'), `佐藤 leaked in ${c.fn}`);
    assert.ok(c.payload.includes('[STUDENT_ID_1]'), `studentIdPattern missing in ${c.fn}`);
    assert.ok(c.payload.includes('部長さん'), `extraHonorificExceptions missing in ${c.fn}`);
  }
});

// ---------------------------------------------------------------------------
// 11. Bounded input length (<= 6000 chars) and latency verification for school regexes
// ---------------------------------------------------------------------------
test('School studentIdPatterns execute in <=6000-char windows and finish rapidly under timing budget', () => {
  assert.equal(MAX_SCHOOL_REGEX_INPUT_CHARS, 6000);

  const longPrefix = `${'A'.repeat(5994)} `;
  const boundaryId = 'S202699'; // crosses 6000-char boundary (5995..6002)
  const longSuffix = ` ${'B'.repeat(6500)}`;
  const fullText = `${longPrefix}${boundaryId}${longSuffix} S202601`;

  // Verify no individual window passed to boundedSchoolMatches exceeds 6000 chars
  const pat = '\\bS\\d{6}\\b';
  assert.equal(validateSafeRegexPattern(pat).ok, true);

  let maxSliceLen = 0;
  const wrappedRe = {
    source: pat,
    flags: 'g',
    lastIndex: 0,
    [Symbol.matchAll](str) {
      if (str.length > maxSliceLen) maxSliceLen = str.length;
      return str.matchAll(new RegExp(pat, 'g'));
    },
  };
  const matches = [...boundedSchoolMatches(wrappedRe, fullText)];
  assert.ok(maxSliceLen <= 6000, `Expected max slice <= 6000, got ${maxSliceLen}`);
  assert.deepEqual(matches.map((m) => m.text), ['S202699', 'S202601']);

  // Measure worst-case execution time for all allowed pattern classes across 12,500 chars
  const patterns = [
    '\\bS\\d{6}\\b',
    '[A-Z]{2}\\d{4,6}',
    '(?:19|20)\\d{2}-\\d{4}',
    'STU-\\d{5,8}',
    '[0-9]{2}[A-Z][0-9]{4}',
  ];
  const adversarialText = 'STU-9999X 1999-ABC '.repeat(700); // > 13,000 chars near-matches
  for (const p of patterns) {
    const t0 = performance.now();
    const session = new MaskingSession();
    maskPiiPatterns(adversarialText, session, { extraPatterns: [p] });
    const elapsedMs = performance.now() - t0;
    assert.ok(elapsedMs < 50, `Pattern ${p} took ${elapsedMs.toFixed(2)}ms (>= 50ms budget)`);
  }
});

// ---------------------------------------------------------------------------
// 12. Shared JSON parity: school_policy_defaults.json & error_reasons.json
// ---------------------------------------------------------------------------
test('DEFAULT_SCHOOL_POLICY matches shared/school_policy_defaults.json exactly', () => {
  const sharedDefaults = JSON.parse(
    readFileSync(new URL('../../shared/school_policy_defaults.json', import.meta.url), 'utf8'),
  );
  assert.deepEqual(DEFAULT_SCHOOL_POLICY, sharedDefaults);
});

test('functions/shared/error_reasons.json matches shared/error_reasons.json and ERROR_REASONS', async () => {
  const { ERROR_REASONS } = await import('../shared/error_reasons.js');
  const rootReasons = JSON.parse(
    readFileSync(new URL('../../shared/error_reasons.json', import.meta.url), 'utf8'),
  );
  const fnReasons = JSON.parse(
    readFileSync(new URL('../shared/error_reasons.json', import.meta.url), 'utf8'),
  );
  assert.deepEqual(fnReasons, rootReasons);
  assert.deepEqual(ERROR_REASONS, rootReasons);
});
