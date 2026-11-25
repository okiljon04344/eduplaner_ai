import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import ExcelJS from 'exceljs';
import {
  syncSchool,
  syncAllSchools,
  notifySchoolChanges,
  assertLinkAllowed,
  releaseSchoolAdmin,
  tokyoToday,
} from '../school/sync.js';
import {
  validateOverride,
  describeOverride,
  publishOverride,
  isTeacher,
  normalizeTeacherEmail,
  canEditSlot,
  teacherProfileOf,
  readTarget,
} from '../school/overrides.js';
import {
  exchangeCode,
  refreshAccessToken,
  getFileMeta,
  downloadXlsx,
} from '../school/google.js';

// ---- minimal in-memory Firestore: only the calls sync.js uses ----
const isPlain = (v) => v && Object.getPrototypeOf(v) === Object.prototype;
const merge = (a, b) => {
  const out = { ...a };
  for (const [k, v] of Object.entries(b)) out[k] = isPlain(v) && isPlain(a?.[k]) ? merge(a[k], v) : v;
  return out;
};

class FakeDb {
  constructor() { this.docs = new Map(); this.batchSizes = []; }
  seed(path, data) { this.docs.set(path, structuredClone(data)); }
  ref(path) {
    return {
      path,
      id: path.split('/').pop(),
      get: async () => this.snap(path),
      set: async (d, opts) => this.put(path, d, opts),
      delete: async () => { this.docs.delete(path); },
    };
  }
  snap(path) {
    const d = this.docs.get(path);
    return { exists: d !== undefined, id: path.split('/').pop(), ref: this.ref(path), data: () => structuredClone(d) };
  }
  put(path, d, opts) {
    const next = opts?.merge ? merge(this.docs.get(path) ?? {}, d) : d;
    this.docs.set(path, structuredClone(next));
  }
  collection(name) {
    const filters = [];
    const q = {
      doc: (id) => this.ref(`${name}/${id}`),
      where: (f, op, v) => { filters.push([f, v]); return q; },
      get: async () => {
        const docs = [...this.docs.keys()]
          .filter((p) => p.startsWith(`${name}/`) && p.split('/').length === 2)
          .map((p) => this.snap(p))
          .filter((s) => filters.every(([f, v]) => s.data()[f] === v));
        return { docs, empty: docs.length === 0, size: docs.length };
      },
    };
    return q;
  }
  getAll(...refs) { return Promise.all(refs.map((r) => r.get())); }
  batch() {
    const ops = [];
    return {
      set: (ref, d) => ops.push([ref, d]),
      commit: async () => { this.batchSizes.push(ops.length); ops.forEach(([r, d]) => r.set(d)); },
    };
  }
  days() { return [...this.docs].filter(([p]) => p.startsWith('school_days/')); }
}

// ---- fixtures ----
const rows = JSON.parse(readFileSync(new URL('./fixtures/school_rows.json', import.meta.url), 'utf8'));
const xlsxOf = async (rs) => {
  const wb = new ExcelJS.Workbook();
  const ws = wb.addWorksheet('s');
  rs.forEach((r) => ws.addRow(r));
  return Buffer.from(await wb.xlsx.writeBuffer());
};
const changedRows = JSON.parse(JSON.stringify(rows).replaceAll('【203】', '【999】'));

const DOMAIN = 'school.example.jp';
const NOW = new Date('2026-10-27T00:00:00Z'); // 09:00 in Tokyo
const classes = [[1, '農業'], [1, '観光'], [2, '農業'], [2, '観光']];

function setup({ buffer, meta } = {}) {
  const db = new FakeDb();
  db.seed(`school_secrets/${DOMAIN}`, { refreshToken: 'r' });
  db.seed(`schools/${DOMAIN}`, { name: 'S', admins: ['admin1'], file: { id: 'f1' } });
  db.seed('users/admin1', { fcmToken: 'admin-token' });
  for (const [g, c] of classes) db.seed(`users/s_${g}_${c}`, { schoolDomain: DOMAIN, grade: String(g), course: c, fcmToken: `tok_${g}_${c}` });
  const pushes = [];
  const state = { buffer, meta: meta ?? { id: 'f1', name: 'tt.xlsx', mimeType: 'x', modifiedTime: 'm1' }, downloads: 0 };
  const deps = {
    db,
    now: () => NOW,
    sendMulticast: async (m) => { pushes.push(m); },
    google: {
      refreshAccessToken: async () => 'at',
      getFileMeta: async () => state.meta,
      downloadXlsx: async () => { state.downloads++; return state.buffer; },
    },
  };
  return { db, deps, pushes, state };
}
const studentPushes = (pushes) => pushes.filter((p) => !p.tokens.includes('admin-token'));

test('syncSchool writes days and sends one push per changed class', async () => {
  const t = setup({ buffer: await xlsxOf(rows) });
  const link = await syncSchool(DOMAIN, { force: true, notify: false }, t.deps);
  assert.equal(link.status, 'ok');
  assert.equal(link.classes, 4);
  assert.equal(link.weeks, 2);
  assert.equal(t.db.days().length, 40);
  assert.ok(Math.max(...t.db.batchSizes) <= 450);
  assert.equal(t.pushes.length, 0);
  assert.equal([...t.db.docs.keys()].filter((p) => p.startsWith('school_changes/')).length, 0);
  const school = t.db.docs.get(`schools/${DOMAIN}`);
  assert.equal(school.sync.status, 'ok');
  assert.equal(school.file.id, 'f1');
  assert.equal(school.file.modifiedTime, 'm1');
  assert.equal(school.periods.length, 4);

  // Pre-seed a full change feed for one class, then re-sync with a changed file.
  const old = Array.from({ length: 30 }, (_, i) => ({ date: '2026-09-01', period: '1-2', subject: `old${i}`, what: '変更' }));
  t.db.seed(`school_changes/${DOMAIN}_1_農業`, { items: old });
  t.state.buffer = await xlsxOf(changedRows);
  t.state.meta = { ...t.state.meta, modifiedTime: 'm2' };
  const res = await syncSchool(DOMAIN, { force: false, notify: true }, t.deps);
  assert.equal(res.status, 'ok');
  assert.ok(res.changes > 0);

  const changeDocs = [...t.db.docs.keys()].filter((p) => p.startsWith('school_changes/'));
  const pushes = studentPushes(t.pushes);
  assert.equal(changeDocs.length, 4); // every class has a 【203】 room on a future date
  assert.equal(pushes.length, 4); // one multicast per changed class
  for (const p of pushes) {
    assert.equal(p.notification.title, '時間割の変更');
    assert.equal(p.android.notification.channelId, 'eduplanner_reminders');
    assert.equal(p.tokens.length, 1);
  }
  const feed = t.db.docs.get(`school_changes/${DOMAIN}_1_農業`);
  assert.equal(feed.items.length, 30);
  assert.notEqual(feed.items[0].subject, 'old0');
  assert.ok(feed.items[0].at instanceof Date);
  assert.match(feed.items[0].what, /教室/);
  // Unchanged day docs are not rewritten.
  assert.ok(t.db.batchSizes.at(-1) < 40);
});

test('syncSchool treats new weeks and new classes as no change', async () => {
  const t = setup({ buffer: await xlsxOf(rows) });
  await syncSchool(DOMAIN, { force: true, notify: false }, t.deps);
  // Simulate a file that grew: January week and a whole class are new.
  for (const [path] of t.db.days()) {
    if (path.includes('_20270') || path.includes('_2_観光_')) t.db.docs.delete(path);
  }
  const missing = 40 - t.db.days().length;
  assert.ok(missing > 10);
  const res = await syncSchool(DOMAIN, { force: true, notify: true }, t.deps);
  assert.equal(res.status, 'ok');
  assert.equal(res.changes, 0);
  assert.equal(t.pushes.length, 0);
  assert.equal([...t.db.docs.keys()].filter((p) => p.startsWith('school_changes/')).length, 0);
  assert.equal(t.db.days().length, 40);
  assert.equal(t.db.batchSizes.at(-1), missing);
});

test('syncSchool skips when modifiedTime unchanged', async () => {
  const t = setup({ buffer: await xlsxOf(rows) });
  t.db.seed(`schools/${DOMAIN}`, { admins: ['admin1'], file: { id: 'f1', modifiedTime: 'm1' }, sync: { status: 'ok' } });
  const res = await syncSchool(DOMAIN, { force: false, notify: true }, t.deps);
  assert.equal(res.status, 'skipped');
  assert.equal(t.state.downloads, 0);
  const school = t.db.docs.get(`schools/${DOMAIN}`);
  assert.equal(school.sync.status, 'ok');
  assert.equal(school.sync.lastRunAt.getTime(), NOW.getTime());
});

test('syncSchool keeps previous days and records error on parse failure', async () => {
  const t = setup({ buffer: await xlsxOf(rows) });
  await syncSchool(DOMAIN, { force: true, notify: false }, t.deps);
  const before = structuredClone([...t.db.days()]);

  t.state.buffer = Buffer.from('not an xlsx');
  t.state.meta = { ...t.state.meta, modifiedTime: 'm2' };
  const res = await syncSchool(DOMAIN, { force: false, notify: true }, t.deps);
  assert.equal(res.status, 'error');
  assert.deepEqual(t.db.days(), before);
  const school = t.db.docs.get(`schools/${DOMAIN}`);
  assert.equal(school.sync.status, 'error');
  assert.ok(school.sync.error.length > 0 && school.sync.error.length <= 300);
  assert.equal(studentPushes(t.pushes).length, 0);
  const admin = t.pushes.filter((p) => p.tokens.includes('admin-token'));
  assert.equal(admin.length, 1);
  assert.equal(admin[0].notification.title, '時間割の取り込みに失敗しました');

  await syncSchool(DOMAIN, { force: false, notify: true }, t.deps);
  assert.equal(t.pushes.filter((p) => p.tokens.includes('admin-token')).length, 1);
});

test('notifySchoolChanges skips users without fcmToken', async () => {
  const db = new FakeDb();
  db.seed('users/a', { schoolDomain: DOMAIN, grade: '1', course: '農業', fcmToken: 'ta' });
  db.seed('users/b', { schoolDomain: DOMAIN, grade: '1', course: '農業' });
  db.seed('users/c', { schoolDomain: DOMAIN, grade: '1', course: '観光', fcmToken: 'tc' });
  const pushes = [];
  const periods = [{ key: '1-2', label: '1・2限' }];
  const changes = [{ date: '2026-10-28', period: '1-2', before: null, after: { subject: '数学', status: 'cancelled' } }];
  await notifySchoolChanges(DOMAIN, 1, '農業', changes, periods, { db, sendMulticast: async (m) => pushes.push(m) });
  assert.equal(pushes.length, 1);
  assert.deepEqual(pushes[0].tokens, ['ta']);

  pushes.length = 0;
  db.seed('users/a', { schoolDomain: DOMAIN, grade: '1', course: '農業' });
  await notifySchoolChanges(DOMAIN, 1, '農業', changes, periods, { db, sendMulticast: async (m) => pushes.push(m) });
  assert.equal(pushes.length, 0);
});

test('syncAllSchools continues after one school fails', async () => {
  const db = new FakeDb();
  db.seed('schools/a.jp', { file: { id: 'x' } });
  db.seed('schools/b.jp', { file: { id: 'y' } });
  db.seed('schools/c.jp', { name: 'no file' });
  const seen = [];
  const run = async (domain) => { seen.push(domain); if (domain === 'a.jp') throw new Error('boom'); };
  await syncAllSchools({ db }, run);
  assert.deepEqual(seen.sort(), ['a.jp', 'b.jp']);
});

test('releaseSchoolAdmin drops the admin and their Drive token', async () => {
  const db = new FakeDb();
  db.seed('schools/a.jp', { admins: ['u1', 'u2'], file: { id: 'f' } });
  db.seed('school_secrets/a.jp', { refreshToken: 'r', linkedBy: 'u1' });
  db.seed('schools/b.jp', { admins: ['u1'], file: { id: 'g' } });
  db.seed('school_secrets/b.jp', { refreshToken: 'r', linkedBy: 'other' });
  db.seed('schools/c.jp', { admins: ['x'] });
  assert.equal(await releaseSchoolAdmin(db, 'u1', 'DEL'), 2);
  assert.deepEqual(db.docs.get('schools/a.jp'), { admins: ['u2'], file: 'DEL' });
  assert.equal(db.docs.has('school_secrets/a.jp'), false);
  assert.deepEqual(db.docs.get('schools/b.jp'), { admins: [], file: { id: 'g' } });
  assert.equal(db.docs.has('school_secrets/b.jp'), true);
  assert.deepEqual(db.docs.get('schools/c.jp'), { admins: ['x'] });
});

test('linkSchoolStart rejects tokens without matching hd', () => {
  const ok = {
    callerEmail: 'T@School.example.jp', callerVerified: true, tokenEmail: 't@school.example.jp',
    hd: 'school.example.jp', school: null, uid: 'u1',
    firstAdmins: ['t@school.example.jp'],
  };
  // No admin yet: only an operator-listed email may claim the school.
  assert.throws(() => assertLinkAllowed({ ...ok, firstAdmins: [] }), { code: 'permission-denied' });
  assert.throws(() => assertLinkAllowed({ ...ok, firstAdmins: [], school: { name: 'x' } }), { code: 'permission-denied' });
  assert.equal(assertLinkAllowed(ok), 'school.example.jp');
  const denied = (o) => assert.throws(() => assertLinkAllowed({ ...ok, ...o }), { code: 'permission-denied' });
  denied({ hd: undefined });
  denied({ hd: 'other.jp' });
  denied({ callerVerified: false });
  denied({ tokenEmail: 'x@school.example.jp' });
  denied({ school: { admins: ['someone'] } });
  assert.equal(assertLinkAllowed({ ...ok, school: { admins: ['u1'] } }), 'school.example.jp');
});

// ---- google.js with a stubbed fetch ----
async function withFetch(handler, fn) {
  const real = globalThis.fetch;
  const calls = [];
  globalThis.fetch = async (url, init) => { calls.push({ url: String(url), init }); return handler(String(url)); };
  try { await fn(calls); } finally { globalThis.fetch = real; }
}
const json = (o, status = 200) => new Response(JSON.stringify(o), { status });
const creds = { clientId: 'cid', clientSecret: 'sec' };

test('google helpers', async () => {
  const idToken = `h.${Buffer.from(JSON.stringify({ email: 'a@b.jp', hd: 'b.jp' })).toString('base64url')}.s`;
  await withFetch(() => json({ refresh_token: 'rt', access_token: 'at', id_token: idToken }), async (calls) => {
    const r = await exchangeCode('code1', creds);
    assert.deepEqual(r, { refreshToken: 'rt', accessToken: 'at', email: 'a@b.jp', hd: 'b.jp' });
    assert.match(calls[0].init.body.toString(), /redirect_uri=postmessage/);
    assert.match(calls[0].init.body.toString(), /grant_type=authorization_code/);
  });
  await withFetch(() => json({ access_token: 'at2' }), async (calls) => {
    assert.equal(await refreshAccessToken('rt', creds), 'at2');
    assert.match(calls[0].init.body.toString(), /grant_type=refresh_token/);
  });
  await withFetch(() => json({ error: 'x' }, 403), async () => {
    await assert.rejects(getFileMeta('at', 'f'), /403/);
  });
  await withFetch(() => new Response(new Uint8Array([1, 2, 3])), async (calls) => {
    const sheet = await downloadXlsx('at', { id: 'f', mimeType: 'application/vnd.google-apps.spreadsheet' });
    assert.ok(Buffer.isBuffer(sheet));
    assert.match(calls[0].url, /\/files\/f\/export\?mimeType=application\/vnd\.openxmlformats/);
    await downloadXlsx('at', { id: 'f', mimeType: 'application/octet-stream' });
    assert.match(calls[1].url, /\/files\/f\?alt=media&supportsAllDrives=true/);
  });
});

// ---- teacher input (school_overrides) ----
const SCHOOL = {
  grades: [1, 2],
  courses: ['農業', '観光'],
  periods: [{ key: '3-4', label: '3・4限', start: '10:40', end: '12:10' }],
  admins: ['admin1'],
  teachers: ['tanaka@school.example.jp'],
};
const OV = { grade: 1, course: '農業', date: '2026-10-29', period: '3-4' };

test('validateOverride accepts a valid input and rejects bad ones', () => {
  const ok = validateOverride({ ...OV, grade: '1', kind: 'room', room: ' 第2PC室 ' }, SCHOOL, '2026-10-27');
  assert.equal(ok.grade, 1);
  assert.equal(ok.room, '第2PC室');
  const bad = [
    { ...OV, grade: 3, kind: 'cancelled' },
    { ...OV, course: '工業', kind: 'cancelled' },
    { ...OV, date: '2026-10-26', kind: 'cancelled' },
    { ...OV, period: '9-10', kind: 'cancelled' },
    { ...OV, kind: 'holiday' },
    { ...OV, kind: 'room' },
    { ...OV, kind: 'makeup' },
    { ...OV, kind: 'memo', note: 'x'.repeat(201) },
  ];
  for (const b of bad) assert.throws(() => validateOverride(b, SCHOOL, '2026-10-27'), /./, JSON.stringify(b));
});

test('isTeacher and normalizeTeacherEmail', () => {
  assert.ok(isTeacher(SCHOOL, 'admin1', 'x@y'));
  assert.ok(isTeacher(SCHOOL, 'u9', 'Tanaka@School.Example.jp'));
  assert.ok(!isTeacher(SCHOOL, 'u9', 's1234@school.example.jp'));
  assert.equal(normalizeTeacherEmail(' Suzuki@School.Example.JP ', DOMAIN), 'suzuki@school.example.jp');
  assert.throws(() => normalizeTeacherEmail('suzuki@gmail.com', DOMAIN));
  assert.throws(() => normalizeTeacherEmail('not-an-email', DOMAIN));
});

test('describeOverride builds push text; memo has no push', () => {
  const base = { subject: '英語', room: '102' };
  const room = describeOverride({ ...OV, kind: 'room', room: '第2PC室', note: '' }, base, SCHOOL.periods);
  assert.equal(room.push('ja').body, '【教室変更】10/29（木）3・4限 英語：102 → 第2PC室');
  assert.equal(room.push(undefined).title, '時間割の変更（先生より）');
  assert.match(room.push('en').body, /^\[Room change\] Thu, 10\/29 ?3・4限 英語: 102 → 第2PC室$/);
  assert.equal(room.what, '教室 102→第2PC室');
  const cancel = describeOverride({ ...OV, kind: 'cancelled', note: '自習' }, base, SCHOOL.periods);
  assert.equal(cancel.push('ja').body, '【休講】10/29（木）3・4限 英語（自習）');
  assert.equal(describeOverride({ ...OV, kind: 'memo', note: '電卓持参' }, base, SCHOOL.periods).push, null);
});

test('publishOverride saves, feeds and pushes; clear removes', async () => {
  const db = new FakeDb();
  db.seed(`schools/${DOMAIN}`, SCHOOL);
  db.seed(`school_days/${DOMAIN}_1_農業_20261029`, { slots: [{ period: '3-4', subject: '英語', room: '102' }] });
  const sent = [];
  const resets = [];
  const deps = {
    db, now: () => NOW,
    notifyClass: async (g, c, n) => { sent.push([g, c, n]); return 2; },
    resetReads: async (o) => resets.push(readTarget(o.grade, o.course, o.date, o.period)),
  };
  const id = `school_overrides/${DOMAIN}_1_農業_20261029`;

  const res = await publishOverride(DOMAIN, { ...OV, kind: 'cancelled', subject: '', teacher: '', room: '', note: '' }, 't1', deps);
  assert.equal(res.pushed, 2);
  assert.equal(sent.length, 1);
  // A new announcement resets its 既読; dots in the domain are RTDB-safe.
  assert.equal(resets[0], 'o_1_農業_2026-10-29_3-4');
  assert.equal(readTarget(1, 'a/b', '2026-10-29', '3-4'), 'o_1_a,b_2026-10-29_3-4');
  assert.doesNotMatch(resets[0], /\./);
  assert.match(sent[0][2]('ja').body, /^【休講】/);
  const doc = db.docs.get(id);
  assert.equal(doc.domain, DOMAIN);
  assert.equal(doc.items['3-4'].kind, 'cancelled');
  assert.equal(doc.items['3-4'].resolved, false);
  assert.equal(db.docs.get(`school_changes/${DOMAIN}_1_農業`).items[0].what, '休講');

  await publishOverride(DOMAIN, { ...OV, kind: 'memo', subject: '', teacher: '', room: '', note: '電卓持参' }, 't1', deps);
  assert.equal(sent.length, 1);

  await publishOverride(DOMAIN, { ...OV, kind: 'clear' }, 't1', deps);
  assert.deepEqual(db.docs.get(id).items, {});
});

test('syncSchool resolves teacher inputs the file now shows and skips their push', async () => {
  const t = setup({ buffer: await xlsxOf(rows) });
  await syncSchool(DOMAIN, { force: true, notify: false }, t.deps);
  // A teacher already announced every 203→999 room change of 1年農業.
  const items = new Map();
  for (const [path, day] of t.db.days()) {
    if (!path.includes('_1_農業_') || day.date < '2026-10-27') continue;
    for (const s of day.slots) {
      if (s.room !== '203') continue;
      const id = path.split('/')[1];
      if (!items.has(id)) items.set(id, { domain: DOMAIN, grade: 1, course: '農業', date: day.date, items: {} });
      items.get(id).items[s.period] = { kind: 'room', room: '999', resolved: false };
    }
  }
  assert.ok(items.size > 0);
  for (const [id, d] of items) t.db.seed(`school_overrides/${id}`, d);

  t.state.buffer = await xlsxOf(changedRows);
  t.state.meta = { ...t.state.meta, modifiedTime: 'm2' };
  await syncSchool(DOMAIN, { force: false, notify: true }, t.deps);

  const pushes = studentPushes(t.pushes);
  assert.equal(pushes.length, 3);
  assert.ok(!pushes.some((p) => p.tokens.includes('tok_1_農業')));
  for (const id of items.keys()) {
    for (const item of Object.values(t.db.docs.get(`school_overrides/${id}`).items)) {
      assert.equal(item.resolved, true);
    }
  }
});

test('canEditSlot: admin, homeroom, or the named lesson teacher only', () => {
  const school = {
    ...SCHOOL,
    teacherProfiles: {
      'tanaka@school.example.jp': { name: '田中', homeroom: null },
      'suzuki@school.example.jp': { name: '鈴木', homeroom: { grade: 1, course: '農業' } },
      'noname@school.example.jp': { name: '', homeroom: null },
    },
  };
  const eng = { period: '3-4', subject: '英語', teacher: '田中【102】' };
  const day = [eng, { period: '1-2', subject: '数学', teacher: '佐藤' }];
  assert.ok(canEditSlot(school, 'admin1', 'x@y', OV, eng, day));
  assert.ok(canEditSlot(school, 'u1', 'Tanaka@school.example.jp', OV, eng, day));
  assert.ok(canEditSlot(school, 'u2', 'suzuki@school.example.jp', OV, eng, day), 'homeroom');
  assert.ok(!canEditSlot(school, 'u2', 'suzuki@school.example.jp', { ...OV, course: '観光' }, eng, day));
  assert.ok(!canEditSlot(school, 'u1', 'tanaka@school.example.jp', OV, { ...eng, teacher: '佐藤' }, day));
  assert.ok(!canEditSlot(school, 'u3', 'noname@school.example.jp', OV, eng, day));
  assert.ok(!canEditSlot(school, 'u4', 'other@school.example.jp', OV, eng, day), 'no profile');
  // Empty slot (補講): anyone teaching the class that day.
  assert.ok(canEditSlot(school, 'u1', 'tanaka@school.example.jp', OV, null, day));
  assert.ok(!canEditSlot(school, 'u1', 'tanaka@school.example.jp', OV, null, [day[1]]));
});

test('teacherProfileOf validates the homeroom class', () => {
  assert.deepEqual(teacherProfileOf({ name: ' 田中 ' }, SCHOOL), { name: '田中', homeroom: null });
  assert.deepEqual(teacherProfileOf({ name: '鈴木', homeroom: { grade: '1', course: '農業' } }, SCHOOL),
    { name: '鈴木', homeroom: { grade: 1, course: '農業' } });
  assert.throws(() => teacherProfileOf({ name: 'x', homeroom: { grade: 9, course: '農業' } }, SCHOOL));
  assert.throws(() => teacherProfileOf({ name: 'x'.repeat(51) }, SCHOOL));
});

test('publishOverride refuses when canEdit says no, before writing', async () => {
  const db = new FakeDb();
  db.seed(`schools/${DOMAIN}`, SCHOOL);
  db.seed(`school_days/${DOMAIN}_1_農業_20261029`, { slots: [{ period: '3-4', subject: '英語', teacher: '佐藤' }] });
  const seen = [];
  const deps = {
    db, now: () => NOW, notifyClass: async () => 1,
    canEdit: (base, slots) => { seen.push([base?.teacher, slots.length]); return false; },
  };
  await assert.rejects(
    publishOverride(DOMAIN, { ...OV, kind: 'clear' }, 't1', deps),
    (e) => e.code === 'permission-denied',
  );
  assert.deepEqual(seen, [['佐藤', 1]]);
  assert.equal(db.docs.get(`school_overrides/${DOMAIN}_1_農業_20261029`), undefined);
});

test('tokyoToday rolls over at 15:00 UTC', () => {
  assert.equal(tokyoToday(new Date('2026-10-27T14:59:59Z')), '2026-10-27');
  assert.equal(tokyoToday(new Date('2026-10-27T15:00:00Z')), '2026-10-28');
});
