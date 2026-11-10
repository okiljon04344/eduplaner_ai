import { test } from 'node:test';
import assert from 'node:assert/strict';
import { getFirestore } from 'firebase-admin/firestore';
import { getMessaging } from 'firebase-admin/messaging';
import { logger } from 'firebase-functions';
import {
  mapGeminiError,
  truncatedJson,
  validateDocxZip,
  extractJson,
  requireAuth,
  replyLanguageOf,
  AI_DAILY_LIMIT,
  enforceAiQuota,
  refundAiQuota,
  GROUP_CODE_LENGTH,
  MAX_GROUP_MEMBERS,
  JOIN_DAILY_LIMIT,
  enforceJoinAttemptLimit,
  CLASS_STATUS_PUSH_COOLDOWN_MS,
  MAX_DOCX_ENTRIES,
  MAX_DOCX_UNCOMPRESSED_BYTES,
  joinGroupByCode,
  onClassStatusChanged,
} from '../index.js';

// ---------------------------------------------------------------------------
// In-memory Firestore & Messaging harness
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
const sentFCM = [];

function resetStore() {
  store.clear();
  sentFCM.length = 0;
}

const db = getFirestore();
const messagingInstance = getMessaging();

// Silence Cloud Functions logger during test runs
logger.error = () => {};
logger.warn = () => {};

messagingInstance.sendEachForMulticast = async (msg) => {
  sentFCM.push(msg);
  return { successCount: msg.tokens.length, failureCount: 0 };
};

db.collection = (col) => ({
  doc: (id) => {
    const path = `${col}/${id}`;
    return {
      id,
      path,
      ref: { id, path },
      get: async () => {
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
      const next = { ...cur };
      for (const [k, v] of Object.entries(data)) {
        if (v && Array.isArray(v.elements)) {
          const arr = Array.isArray(cur[k]) ? [...cur[k]] : [];
          for (const el of v.elements) {
            if (!arr.includes(el)) arr.push(el);
          }
          next[k] = arr;
        } else {
          next[k] = v;
        }
      }
      store.set(ref.path, next);
    },
  };
  return await callback(tx);
};

// ---------------------------------------------------------------------------
// Helper: build small ZIP buffers for validateDocxZip tests
// ---------------------------------------------------------------------------
function buildMockZip(entries, options = {}) {
  const localHeader = Buffer.alloc(30);
  localHeader.writeUInt32LE(0x04034b50, 0); // PK\x03\x04

  const cdRecords = [];
  for (const entry of entries) {
    const nameBuf = Buffer.from(entry.name || 'document.xml', 'utf8');
    const cdfh = Buffer.alloc(46 + nameBuf.length);
    cdfh.writeUInt32LE(0x02014b50, 0); // PK\x01\x02
    cdfh.writeUInt32LE(entry.uncompressedSize ?? 0, 24);
    cdfh.writeUInt16LE(nameBuf.length, 28);
    nameBuf.copy(cdfh, 46);
    cdRecords.push(cdfh);
  }
  const cdBuf = Buffer.concat(cdRecords);
  const cdOffset = localHeader.length;
  const cdSize = cdBuf.length;

  const totalEntries = options.totalEntriesOverride ?? entries.length;
  const cdOffsetVal = options.cdOffsetOverride ?? cdOffset;
  const cdSizeVal = options.cdSizeOverride ?? cdSize;

  const eocd = Buffer.alloc(22);
  eocd.writeUInt32LE(0x06054b50, 0); // PK\x05\x06
  eocd.writeUInt16LE(totalEntries, 8);
  eocd.writeUInt16LE(totalEntries, 10);
  eocd.writeUInt32LE(cdSizeVal, 12);
  eocd.writeUInt32LE(cdOffsetVal, 16);

  return Buffer.concat([localHeader, cdBuf, eocd]);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test('mapGeminiError maps quota and rate limit errors to resource-exhausted', () => {
  const fallback = 'デフォルトエラー';

  const err429 = mapGeminiError({ status: 429 }, fallback);
  assert.equal(err429.code, 'resource-exhausted');
  assert.match(err429.message, /AIの利用上限に達しました/);

  const errResponse429 = mapGeminiError({ response: { status: 429 } }, fallback);
  assert.equal(errResponse429.code, 'resource-exhausted');

  const errQuota = mapGeminiError(new Error('Resource quota exceeded'), fallback);
  assert.equal(errQuota.code, 'resource-exhausted');

  const errRateLimit = mapGeminiError(new Error('Rate limit hit for model'), fallback);
  assert.equal(errRateLimit.code, 'resource-exhausted');
});

test('mapGeminiError maps invalid argument errors to invalid-argument', () => {
  const fallback = 'デフォルトエラー';

  const err400 = mapGeminiError({ status: 400 }, fallback);
  assert.equal(err400.code, 'invalid-argument');
  assert.equal(err400.message, '入力内容を確認してください。');

  const errInvalid = mapGeminiError(new Error('Invalid contents provided'), fallback);
  assert.equal(errInvalid.code, 'invalid-argument');

  const errBadRequest = mapGeminiError(new Error('Bad request syntax'), fallback);
  assert.equal(errBadRequest.code, 'invalid-argument');
});

test('mapGeminiError maps auth/forbidden errors to internal with japanese fallback', () => {
  const fallback = '認証に失敗しました。';

  const err401 = mapGeminiError({ status: 401 }, fallback);
  assert.equal(err401.code, 'internal');
  assert.equal(err401.message, fallback);

  const err403 = mapGeminiError({ status: 403 }, fallback);
  assert.equal(err403.code, 'internal');
  assert.equal(err403.message, fallback);
});

test('mapGeminiError maps unavailable and timeout errors to unavailable', () => {
  const fallback = 'デフォルトエラー';

  const err503 = mapGeminiError({ status: 503 }, fallback);
  assert.equal(err503.code, 'unavailable');
  assert.match(err503.message, /AIサーバーが混雑しています/);

  const err504 = mapGeminiError({ code: 504 }, fallback);
  assert.equal(err504.code, 'unavailable');

  const errTimeout = mapGeminiError(new Error('Connection timeout'), fallback);
  assert.equal(errTimeout.code, 'unavailable');

  const errDeadline = mapGeminiError(new Error('Deadline exceeded for RPC'), fallback);
  assert.equal(errDeadline.code, 'unavailable');

  const errUnavailable = mapGeminiError(new Error('Service unavailable at this time'), fallback);
  assert.equal(errUnavailable.code, 'unavailable');
});

test('mapGeminiError falls back to internal with japaneseFallback on unknown errors', () => {
  const fallback = '予期せぬエラーが発生しました。';

  const errGeneric = mapGeminiError(new Error('Something random happened'), fallback);
  assert.equal(errGeneric.code, 'internal');
  assert.equal(errGeneric.message, fallback);

  const errNull = mapGeminiError(null, fallback);
  assert.equal(errNull.code, 'internal');
  assert.equal(errNull.message, fallback);
});

test('truncatedJson serializes and slices data according to limit', () => {
  const shortObj = { hello: 'world', count: 42 };
  assert.equal(truncatedJson(shortObj), JSON.stringify(shortObj));

  const longObj = { text: 'a'.repeat(200) };
  const truncated20 = truncatedJson(longObj, 20);
  assert.equal(truncated20.length, 20);
  assert.equal(truncated20, JSON.stringify(longObj).slice(0, 20));

  const hugeObj = { text: 'x'.repeat(4000) };
  assert.equal(truncatedJson(hugeObj).length, 3000);
});

test('extractJson extracts first balanced json block and strips markdown fences', () => {
  assert.equal(extractJson(null), null);
  assert.equal(extractJson(''), null);
  assert.equal(extractJson('no json here'), null);

  const plain = extractJson('{"foo": "bar", "num": 123}');
  assert.deepEqual(plain, { foo: 'bar', num: 123 });

  const fencedJson = extractJson('```json\n{"status": "ok"}\n```');
  assert.deepEqual(fencedJson, { status: 'ok' });

  const fencedPlain = extractJson('```\n{"status": "fenced"}\n```');
  assert.deepEqual(fencedPlain, { status: 'fenced' });

  const prose = extractJson('Here is your answer: {"questions": [1, 2, 3]} Hope that helps!');
  assert.deepEqual(prose, { questions: [1, 2, 3] });
});

test('replyLanguageOf and requireAuth helpers', () => {
  assert.equal(replyLanguageOf('ja'), 'Japanese');
  assert.equal(replyLanguageOf('en'), 'English');
  assert.equal(replyLanguageOf('uz'), 'Uzbek');
  assert.equal(replyLanguageOf('unknown_code'), 'Japanese');
  assert.equal(replyLanguageOf(undefined), 'Japanese');

  assert.throws(() => requireAuth({}), {
    code: 'unauthenticated',
    message: 'Login is required.',
  });
  assert.doesNotThrow(() => requireAuth({ auth: { uid: 'student1' } }));
});

test('validateDocxZip accepts valid zip buffer', () => {
  const validZip = buildMockZip([
    { name: '[Content_Types].xml', uncompressedSize: 300 },
    { name: 'word/document.xml', uncompressedSize: 1200 },
  ]);
  assert.doesNotThrow(() => validateDocxZip(validZip));
});

test('validateDocxZip rejects non-buffer, short buffer, and bad magic', () => {
  assert.throws(() => validateDocxZip('not-a-buffer'), {
    code: 'invalid-argument',
    message: 'ファイルの読み取りに失敗しました。',
  });

  assert.throws(() => validateDocxZip(null), {
    code: 'invalid-argument',
    message: 'ファイルの読み取りに失敗しました。',
  });

  assert.throws(() => validateDocxZip(Buffer.alloc(10)), {
    code: 'invalid-argument',
    message: 'ファイルの読み取りに失敗しました。',
  });

  const badMagic = Buffer.alloc(30);
  badMagic.writeUInt32LE(0x12345678, 0);
  assert.throws(() => validateDocxZip(badMagic), {
    code: 'invalid-argument',
    message: 'ファイルの読み取りに失敗しました。',
  });
});

test('validateDocxZip rejects buffer missing EOCD signature', () => {
  const noEocd = Buffer.alloc(100);
  noEocd.writeUInt32LE(0x04034b50, 0); // PK\x03\x04
  // No EOCD signature written
  assert.throws(() => validateDocxZip(noEocd), {
    code: 'invalid-argument',
    message: 'ファイルの読み取りに失敗しました。',
  });
});

test('validateDocxZip rejects too-many-files (>200 entries)', () => {
  const entries = Array.from({ length: MAX_DOCX_ENTRIES + 1 }, (_, i) => ({
    name: `file_${i}.xml`,
    uncompressedSize: 50,
  }));
  const zip = buildMockZip(entries);

  assert.throws(() => validateDocxZip(zip), {
    code: 'invalid-argument',
    message: 'ファイルサイズが大きすぎます。',
  });
});

test('validateDocxZip rejects invalid central directory bounds', () => {
  const zip = buildMockZip(
    [{ name: 'doc.xml', uncompressedSize: 100 }],
    { cdOffsetOverride: 50000, cdSizeOverride: 50000 }
  );

  assert.throws(() => validateDocxZip(zip), {
    code: 'invalid-argument',
    message: 'ファイルサイズが大きすぎます。',
  });
});

test('validateDocxZip rejects ZIP64 entry outright', () => {
  const zip64 = buildMockZip([
    { name: 'huge.xml', uncompressedSize: 0xffffffff },
  ]);

  assert.throws(() => validateDocxZip(zip64), {
    code: 'invalid-argument',
    message: 'ファイルサイズが大きすぎます。',
  });
});

test('validateDocxZip rejects over-size total uncompressed bytes (>25MB)', () => {
  const overSizeZip = buildMockZip([
    { name: 'bomb.xml', uncompressedSize: MAX_DOCX_UNCOMPRESSED_BYTES + 1024 },
  ]);

  assert.throws(() => validateDocxZip(overSizeZip), {
    code: 'invalid-argument',
    message: 'ファイルサイズが大きすぎます。',
  });
});

test('AI quota uses UTC day key and enforces AI_DAILY_LIMIT', async () => {
  resetStore();
  const uid = 'ai_user_1';
  const today = new Date().toISOString().slice(0, 10);

  // Initial call initializes counter to 1 with today's UTC day key
  await enforceAiQuota(uid);
  let record = store.get(`ai_usage/${uid}`);
  assert.equal(record.day, today);
  assert.equal(record.count, 1);

  // Subsequent call increments count
  await enforceAiQuota(uid);
  record = store.get(`ai_usage/${uid}`);
  assert.equal(record.count, 2);

  // Set counter to limit (100)
  store.set(`ai_usage/${uid}`, { day: today, count: AI_DAILY_LIMIT });
  await assert.rejects(
    () => enforceAiQuota(uid),
    {
      code: 'resource-exhausted',
      message: 'Daily AI limit reached.',
    }
  );

  // When day rolls over (yesterday's date), count resets to 1 for today
  store.set(`ai_usage/${uid}`, { day: '2026-01-01', count: AI_DAILY_LIMIT });
  await enforceAiQuota(uid);
  record = store.get(`ai_usage/${uid}`);
  assert.equal(record.day, today);
  assert.equal(record.count, 1);
});

test('refundAiQuota refunds unit only on same day and does not go negative', async () => {
  resetStore();
  const uid = 'refund_user_1';
  const today = new Date().toISOString().slice(0, 10);

  // Refund on count > 0 for today
  store.set(`ai_usage/${uid}`, { day: today, count: 5 });
  await refundAiQuota(uid);
  assert.equal(store.get(`ai_usage/${uid}`).count, 4);

  // Refund when count is 0 does not decrement below 0
  store.set(`ai_usage/${uid}`, { day: today, count: 0 });
  await refundAiQuota(uid);
  assert.equal(store.get(`ai_usage/${uid}`).count, 0);

  // Refund when day is from yesterday does not touch count
  store.set(`ai_usage/${uid}`, { day: '2026-01-01', count: 5 });
  await refundAiQuota(uid);
  assert.equal(store.get(`ai_usage/${uid}`).count, 5);
  assert.equal(store.get(`ai_usage/${uid}`).day, '2026-01-01');

  // Refund when doc does not exist does nothing
  await assert.doesNotReject(() => refundAiQuota('non_existent_user'));
});

test('enforceJoinAttemptLimit enforces JOIN_DAILY_LIMIT and rolls over daily', async () => {
  resetStore();
  const uid = 'join_user_1';
  const today = new Date().toISOString().slice(0, 10);

  // First join attempt sets joinDay and joinCount: 1
  await enforceJoinAttemptLimit(uid);
  let record = store.get(`ai_usage/${uid}`);
  assert.equal(record.joinDay, today);
  assert.equal(record.joinCount, 1);

  // Set counter to limit (15)
  store.set(`ai_usage/${uid}`, { joinDay: today, joinCount: JOIN_DAILY_LIMIT });
  await assert.rejects(
    () => enforceJoinAttemptLimit(uid),
    {
      code: 'resource-exhausted',
      message: 'Too many join attempts today. Please try again tomorrow.',
    }
  );

  // On new day, resets count to 1
  store.set(`ai_usage/${uid}`, { joinDay: '2026-01-01', joinCount: JOIN_DAILY_LIMIT });
  await enforceJoinAttemptLimit(uid);
  record = store.get(`ai_usage/${uid}`);
  assert.equal(record.joinDay, today);
  assert.equal(record.joinCount, 1);
});

test('joinGroupByCode enforces MAX_GROUP_MEMBERS check and idempotency in transaction', async () => {
  resetStore();
  const code = 'ABC123';
  assert.equal(code.length, GROUP_CODE_LENGTH);

  // 1. Group already at MAX_GROUP_MEMBERS (60)
  store.set('study_groups/full_group', {
    code,
    name: 'Full Group',
    memberIds: Array.from({ length: MAX_GROUP_MEMBERS }, (_, i) => `student_${i}`),
    createdAt: { toMillis: () => 1000 },
  });

  await assert.rejects(
    () => joinGroupByCode.run({
      auth: { uid: 'new_student' },
      data: { code },
    }),
    {
      code: 'resource-exhausted',
      message: 'This group is full.',
    }
  );

  // 2. Already a member of this group -> returns success idempotently without changing members
  const memberJoin = await joinGroupByCode.run({
    auth: { uid: 'student_0' },
    data: { code },
  });
  assert.equal(memberJoin.groupId, 'full_group');
  assert.equal(store.get('study_groups/full_group').memberIds.length, MAX_GROUP_MEMBERS);

  // 3. Group with capacity (< 60 members) -> successfully adds student
  store.set('study_groups/open_group', {
    code: 'OPEN99',
    name: 'Open Group',
    memberIds: ['member_1', 'member_2'],
    createdAt: { toMillis: () => 2000 },
  });

  const successJoin = await joinGroupByCode.run({
    auth: { uid: 'student_joiner' },
    data: { code: 'OPEN99' },
  });
  assert.equal(successJoin.groupId, 'open_group');
  const updatedMembers = store.get('study_groups/open_group').memberIds;
  assert.ok(updatedMembers.includes('student_joiner'));
  assert.equal(updatedMembers.length, 3);
});

test('onClassStatusChanged enforces 5-minute push cooldown', async () => {
  resetStore();
  assert.equal(CLASS_STATUS_PUSH_COOLDOWN_MS, 5 * 60 * 1000);

  const now = Date.now();
  let updatedFields = null;

  const mockRef = {
    update: async (fields) => {
      updatedFields = fields;
    },
  };

  // 1. Push was sent 1 minute ago (< 5 minute cooldown) -> no-op early return
  const cooldownActiveEvent = {
    data: {
      before: {
        data: () => ({
          groupId: 'group_test',
          status: 'normal',
          statusPushSentAt: { toMillis: () => now - 60000 },
        }),
      },
      after: {
        ref: mockRef,
        data: () => ({
          groupId: 'group_test',
          status: 'cancelled',
          subject: '数学',
          dayOfWeek: '月',
          period: '1-2',
          statusPushSentAt: { toMillis: () => now - 60000 },
        }),
      },
    },
  };

  updatedFields = null;
  await onClassStatusChanged.run(cooldownActiveEvent);
  assert.equal(updatedFields, null, 'Cooldown active: ref.update should not have been called');
  assert.equal(sentFCM.length, 0, 'No push should be sent during cooldown');

  // 2. Push was sent 6 minutes ago (> 5 minute cooldown) -> proceeds, updates statusPushSentAt and sends push
  store.set('study_groups/group_test', {
    memberIds: ['teacher_uid', 'student_uid'],
  });
  store.set('users/student_uid', {
    fcmToken: 'token_student_123',
  });

  const cooldownExpiredEvent = {
    data: {
      before: {
        data: () => ({
          groupId: 'group_test',
          status: 'normal',
          statusPushSentAt: { toMillis: () => now - (6 * 60 * 1000) },
        }),
      },
      after: {
        ref: mockRef,
        data: () => ({
          groupId: 'group_test',
          status: 'cancelled',
          subject: '数学',
          dayOfWeek: '月',
          period: '1-2',
          userId: 'teacher_uid',
          statusPushSentAt: { toMillis: () => now - (6 * 60 * 1000) },
        }),
      },
    },
  };

  updatedFields = null;
  await onClassStatusChanged.run(cooldownExpiredEvent);
  assert.ok(updatedFields !== null, 'Cooldown expired: statusPushSentAt should be updated');
  assert.equal(sentFCM.length, 1);
  assert.deepEqual(sentFCM[0].tokens, ['token_student_123']);
  assert.equal(sentFCM[0].notification.title, '数学が休講になりました');
});

test('onClassStatusChanged skips unshared classes, normal status, and unchanged updates', async () => {
  resetStore();
  let updated = false;
  const mockRef = { update: async () => { updated = true; } };

  // Unshared class (!after.groupId)
  await onClassStatusChanged.run({
    data: {
      before: { data: () => ({ status: 'normal' }) },
      after: { ref: mockRef, data: () => ({ status: 'cancelled' }) },
    },
  });
  assert.equal(updated, false);

  // Normal status
  await onClassStatusChanged.run({
    data: {
      before: { data: () => ({ groupId: 'g1', status: 'normal' }) },
      after: { ref: mockRef, data: () => ({ groupId: 'g1', status: 'normal' }) },
    },
  });
  assert.equal(updated, false);

  // Status, note, and date did not change
  await onClassStatusChanged.run({
    data: {
      before: { data: () => ({ groupId: 'g1', status: 'cancelled', statusNote: '休講', statusDate: { toMillis: () => 1000 } }) },
      after: { ref: mockRef, data: () => ({ groupId: 'g1', status: 'cancelled', statusNote: '休講', statusDate: { toMillis: () => 1000 } }) },
    },
  });
  assert.equal(updated, false);
});
