import { before, test } from 'node:test';
import assert from 'node:assert/strict';

const PROJECT_ID = process.env.GCLOUD_PROJECT || 'eduplannerai-97365';
const EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8085';
const BASE_URL = `http://${EMULATOR_HOST}/v1/projects/${PROJECT_ID}/databases/(default)/documents`;
const CLEAR_URL = `http://${EMULATOR_HOST}/emulator/v1/projects/${PROJECT_ID}/databases/(default)/documents`;

function unsignedJwt({ uid, email, emailVerified = true }) {
  const header = Buffer.from(JSON.stringify({ alg: 'none', typ: 'JWT' })).toString('base64url');
  const now = Math.floor(Date.now() / 1000);
  const payload = Buffer.from(
    JSON.stringify({
      iss: `https://securetoken.google.com/${PROJECT_ID}`,
      aud: PROJECT_ID,
      auth_time: now,
      user_id: uid,
      sub: uid,
      iat: now,
      exp: now + 3600,
      email,
      email_verified: emailVerified,
      firebase: {
        identities: { email: [email] },
        sign_in_provider: 'google.com',
      },
    }),
  ).toString('base64url');
  return `${header}.${payload}.`;
}

async function fsRequest(method, docPath, { token, body } = {}) {
  const url = `${BASE_URL}/${docPath}`;
  const headers = {};
  if (token) headers.Authorization = `Bearer ${token}`;
  if (body !== undefined) headers['Content-Type'] = 'application/json';
  const res = await fetch(url, {
    method,
    headers,
    body: body !== undefined ? JSON.stringify(body) : undefined,
  });
  return { status: res.status, json: await res.json().catch(() => ({})) };
}

async function seedDoc(docPath, fields) {
  const res = await fsRequest('PATCH', docPath, {
    token: 'owner',
    body: { fields },
  });
  assert.equal(res.status, 200, `Seed failed for ${docPath}: ${JSON.stringify(res.json)}`);
}

const studentToken = unsignedJwt({ uid: 'stu_uid', email: 'student@tokyo.ac.jp' });
const teacherToken = unsignedJwt({ uid: 'tch_uid', email: 'teacher@tokyo.ac.jp' });
const adminToken = unsignedJwt({ uid: 'adm_uid', email: 'admin@tokyo.ac.jp' });
const outsiderToken = unsignedJwt({ uid: 'out_uid', email: 'outsider@gmail.com' });

const policyPatchBody = {
  fields: {
    policy: {
      mapValue: {
        fields: {
          schemaVersion: { integerValue: '1' },
        },
      },
    },
  },
};

const domainBody = { fields: { domain: { stringValue: 'tokyo.ac.jp' } } };

before(async () => {
  const cleared = await fetch(CLEAR_URL, { method: 'DELETE' });
  assert.equal(cleared.status, 200, 'Firestore emulator must be running on FIRESTORE_EMULATOR_HOST');

  await seedDoc('schools/tokyo.ac.jp', {
    name: { stringValue: 'Tokyo School' },
    admins: { arrayValue: { values: [{ stringValue: 'adm_uid' }] } },
    teachers: { arrayValue: { values: [{ stringValue: 'teacher@tokyo.ac.jp' }] } },
    policy: {
      mapValue: {
        fields: {
          schemaVersion: { integerValue: '1' },
          revision: { integerValue: '1' },
        },
      },
    },
  });
  await seedDoc('school_policy_history/h1', { domain: { stringValue: 'tokyo.ac.jp' } });
  await seedDoc('timetable_import_drafts/d1', { domain: { stringValue: 'tokyo.ac.jp' } });
  await seedDoc('timetable_import_history/ih1', { domain: { stringValue: 'tokyo.ac.jp' } });
});

// --- schools/{domain} ---
test('schools/{domain}: domain student can get school doc', async () => {
  const res = await fsRequest('GET', 'schools/tokyo.ac.jp', { token: studentToken });
  assert.equal(res.status, 200);
});

test('schools/{domain}: outsider cannot get school doc', async () => {
  const res = await fsRequest('GET', 'schools/tokyo.ac.jp', { token: outsiderToken });
  assert.equal(res.status, 403);
});

test('schools/{domain}.policy: student client write denied', async () => {
  const res = await fsRequest('PATCH', 'schools/tokyo.ac.jp?updateMask.fieldPaths=policy', {
    token: studentToken,
    body: policyPatchBody,
  });
  assert.equal(res.status, 403);
});

test('schools/{domain}.policy: teacher client write denied', async () => {
  const res = await fsRequest('PATCH', 'schools/tokyo.ac.jp?updateMask.fieldPaths=policy', {
    token: teacherToken,
    body: policyPatchBody,
  });
  assert.equal(res.status, 403);
});

test('schools/{domain}.policy: admin client direct write denied', async () => {
  const res = await fsRequest('PATCH', 'schools/tokyo.ac.jp?updateMask.fieldPaths=policy', {
    token: adminToken,
    body: policyPatchBody,
  });
  assert.equal(res.status, 403);
});

// --- school_policy_history ---
test('school_policy_history: client reads denied (student, teacher, admin)', async () => {
  for (const token of [studentToken, teacherToken, adminToken]) {
    const res = await fsRequest('GET', 'school_policy_history/h1', { token });
    assert.equal(res.status, 403);
  }
});

test('school_policy_history: client writes denied (student, teacher, admin)', async () => {
  for (const token of [studentToken, teacherToken, adminToken]) {
    const res = await fsRequest('PATCH', 'school_policy_history/h1', { token, body: domainBody });
    assert.equal(res.status, 403);
  }
});

// --- timetable_import_drafts ---
test('timetable_import_drafts: client reads denied (student, teacher, admin)', async () => {
  for (const token of [studentToken, teacherToken, adminToken]) {
    const res = await fsRequest('GET', 'timetable_import_drafts/d1', { token });
    assert.equal(res.status, 403);
  }
});

test('timetable_import_drafts: client writes denied (student, teacher, admin)', async () => {
  for (const token of [studentToken, teacherToken, adminToken]) {
    const res = await fsRequest('PATCH', 'timetable_import_drafts/d1', { token, body: domainBody });
    assert.equal(res.status, 403);
  }
});

// --- timetable_import_history ---
test('timetable_import_history: client reads denied (student, teacher, admin)', async () => {
  for (const token of [studentToken, teacherToken, adminToken]) {
    const res = await fsRequest('GET', 'timetable_import_history/ih1', { token });
    assert.equal(res.status, 403);
  }
});

test('timetable_import_history: client writes denied (student, teacher, admin)', async () => {
  for (const token of [studentToken, teacherToken, adminToken]) {
    const res = await fsRequest('PATCH', 'timetable_import_history/ih1', { token, body: domainBody });
    assert.equal(res.status, 403);
  }
});
