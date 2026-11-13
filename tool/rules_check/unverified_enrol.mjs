// Unverified school-domain account must not be able to enrol in a class.
// Run: firebase emulators:exec --only auth,firestore --project demo-rules "$(which node) tool/rules_check/unverified_enrol.mjs"
import assert from 'node:assert/strict';
const P = 'demo-rules';
const auth = 'http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1';
const fs = `http://127.0.0.1:8085/v1/projects/${P}/databases/(default)/documents`;
const post = async (url, body, token) => fetch(url, {
  method: 'POST', headers: {'Content-Type': 'application/json', ...(token ? {Authorization: `Bearer ${token}`} : {})},
  body: JSON.stringify(body)});
const signUp = async (email) => (await post(`${auth}/accounts:signUp?key=x`, {email, password: 'test-pass-123', returnSecureToken: true})).json();
const writeUser = (u, fields) => fetch(`${fs}/users/${u.localId}`, {
  method: 'PATCH', headers: {'Content-Type': 'application/json', Authorization: `Bearer ${u.idToken}`},
  body: JSON.stringify({fields})});
const str = (v) => ({stringValue: v});

const fake = await signUp(`fake${Date.now()}@school.test`);
assert.equal((await writeUser(fake, {name: str('x')})).status, 200, 'plain profile write allowed');
assert.equal((await writeUser(fake, {name: str('x'), schoolDomain: str('school.test'), grade: str('1'), course: str('農業')})).status, 403,
  'unverified email must not set schoolDomain');
// school_admin is not readable by a non-admin.
assert.equal((await fetch(`${fs}/school_admin/school.test`, {headers: {Authorization: `Bearer ${fake.idToken}`}})).status, 403);
console.log('rules check ok');
