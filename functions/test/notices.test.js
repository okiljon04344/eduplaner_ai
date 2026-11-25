import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  NOTICE_PRIORITIES,
  validateNotice,
  noticePush,
  publishNotice,
  deleteNotice,
  updateNotice,
} from '../school/notices.js';
import { noticeReadTarget } from '../school/overrides.js';

// Minimal in-memory Firestore for notices tests (FakeDb pattern).
class FakeDb {
  constructor() {
    this.docs = new Map();
    this.autoIdCounter = 0;
  }

  seed(path, data) {
    this.docs.set(path, structuredClone(data));
  }

  ref(path) {
    return {
      path,
      id: path.split('/').pop(),
      get: async () => this.snap(path),
      set: async (d, opts) => {
        this.docs.set(path, structuredClone(opts?.merge ? { ...this.docs.get(path), ...d } : d));
      },
      delete: async () => {
        this.docs.delete(path);
      },
    };
  }

  snap(path) {
    const d = this.docs.get(path);
    return {
      exists: d !== undefined,
      id: path.split('/').pop(),
      ref: this.ref(path),
      data: () => structuredClone(d),
    };
  }

  collection(name) {
    return {
      doc: (id) => {
        const docId = id ?? `notice${++this.autoIdCounter}`;
        return this.ref(`${name}/${docId}`);
      },
    };
  }
}

const SCHOOL = {
  grades: [1, 2, 3],
  courses: ['農業', '観光'],
};

test('NOTICE_PRIORITIES includes normal and urgent', () => {
  assert.deepEqual(NOTICE_PRIORITIES, ['normal', 'urgent']);
});

test('validateNotice accepts valid notice and trims title and body', () => {
  const input = {
    grade: 1,
    course: '農業',
    title: '  持ち物連絡  ',
    body: '  作業着と手袋を持参すること。  ',
    priority: 'normal',
  };
  const validated = validateNotice(input, SCHOOL);
  assert.deepEqual(validated, {
    grade: 1,
    course: '農業',
    title: '持ち物連絡',
    body: '作業着と手袋を持参すること。',
    priority: 'normal',
    category: 'contact',
    subject: '',
    link: '',
  });
});

test('validateNotice allows course to be null or omitted for whole grade', () => {
  const withNull = validateNotice({ grade: 2, course: null, title: '学年集会' }, SCHOOL);
  assert.equal(withNull.grade, 2);
  assert.equal(withNull.course, null);
  assert.equal(withNull.title, '学年集会');
  assert.equal(withNull.body, '');
  assert.equal(withNull.priority, 'normal');

  const omitted = validateNotice({ grade: '2', title: '学年集会' }, SCHOOL);
  assert.equal(omitted.grade, 2);
  assert.equal(omitted.course, null);
});

test('validateNotice rejects unknown grade', () => {
  assert.throws(
    () => validateNotice({ grade: 4, course: '農業', title: '連絡' }, SCHOOL),
    (err) => err.code === 'invalid-argument' && err.message.includes('Unknown grade'),
  );
  assert.throws(
    () => validateNotice({ grade: 'abc', course: '農業', title: '連絡' }, SCHOOL),
    (err) => err.code === 'invalid-argument' && err.message.includes('Unknown grade'),
  );
});

test('validateNotice rejects unknown course', () => {
  assert.throws(
    () => validateNotice({ grade: 1, course: '工業', title: '連絡' }, SCHOOL),
    (err) => err.code === 'invalid-argument' && err.message.includes('Unknown course'),
  );
});

test('validateNotice rejects empty or too long title', () => {
  assert.throws(
    () => validateNotice({ grade: 1, course: '農業', title: '' }, SCHOOL),
    (err) => err.code === 'invalid-argument' && err.message.includes('title must be 1-60 chars'),
  );
  assert.throws(
    () => validateNotice({ grade: 1, course: '農業', title: '   ' }, SCHOOL),
    (err) => err.code === 'invalid-argument' && err.message.includes('title must be 1-60 chars'),
  );
  assert.throws(
    () => validateNotice({ grade: 1, course: '農業', title: null }, SCHOOL),
    (err) => err.code === 'invalid-argument' && err.message.includes('title must be 1-60 chars'),
  );
  assert.throws(
    () => validateNotice({ grade: 1, course: '農業', title: 'x'.repeat(61) }, SCHOOL),
    (err) => err.code === 'invalid-argument' && err.message.includes('title must be 1-60 chars'),
  );
});

test('validateNotice rejects body exceeding 1000 characters', () => {
  const ok = validateNotice({ grade: 1, course: '農業', title: 'OK', body: 'a'.repeat(1000) }, SCHOOL);
  assert.equal(ok.body.length, 1000);

  assert.throws(
    () => validateNotice({ grade: 1, course: '農業', title: 'NG', body: 'a'.repeat(1001) }, SCHOOL),
    (err) => err.code === 'invalid-argument' && err.message.includes('body must be at most 1000 chars'),
  );
});

test('validateNotice rejects bad priority', () => {
  assert.throws(
    () => validateNotice({ grade: 1, course: '農業', title: '連絡', priority: 'high' }, SCHOOL),
    (err) => err.code === 'invalid-argument' && err.message.includes('Unknown priority'),
  );
  assert.throws(
    () => validateNotice({ grade: 1, course: '農業', title: '連絡', priority: 123 }, SCHOOL),
    (err) => err.code === 'invalid-argument' && err.message.includes('Unknown priority'),
  );
});

test('noticeReadTarget names the notice', () => {
  assert.equal(noticeReadTarget('notice123'), 'n_notice123');
});

test('noticePush formats urgent vs normal title in ja and en with notice title as body', () => {
  const normalNotice = { title: '明日の連絡', priority: 'normal' };
  const normalPush = noticePush(normalNotice);
  assert.deepEqual(normalPush('ja'), {
    title: 'お知らせ',
    body: '明日の連絡',
  });
  assert.deepEqual(normalPush('en'), {
    title: 'Notice',
    body: '明日の連絡',
  });

  const urgentNotice = { title: '台風による休校措置', priority: 'urgent' };
  const urgentPush = noticePush(urgentNotice);
  assert.deepEqual(urgentPush('ja'), {
    title: '【緊急】お知らせ',
    body: '台風による休校措置',
  });
  assert.deepEqual(urgentPush('en'), {
    title: '[Urgent] Notice',
    body: '台風による休校措置',
  });
});

test('publishNotice saves doc with domain/createdBy/createdByName and calls notifyClass with route /home', async () => {
  const db = new FakeDb();
  const domain = 'school.example.jp';
  const notice = {
    grade: 2,
    course: '観光',
    title: '実習集合場所の変更',
    body: '正門前に9:00集合',
    priority: 'urgent',
  };
  const author = { uid: 'teacher_42', name: '鈴木' };
  const fixedNow = new Date('2026-11-10T10:00:00Z');

  let notifiedGrade = null;
  let notifiedCourse = null;
  let notifiedMessage = null;
  let notifiedRoute = null;

  const notifyClass = async (grade, course, message, route) => {
    notifiedGrade = grade;
    notifiedCourse = course;
    notifiedMessage = message;
    notifiedRoute = route;
    return 30;
  };

  const res = await publishNotice(domain, notice, author, {
    db,
    now: () => fixedNow,
    notifyClass,
  });

  assert.equal(res.pushed, 30);
  assert.ok(typeof res.id === 'string' && res.id.length > 0);

  const saved = db.docs.get(`school_notices/${res.id}`);
  assert.equal(saved.domain, domain);
  assert.equal(saved.grade, 2);
  assert.equal(saved.course, '観光');
  assert.equal(saved.title, '実習集合場所の変更');
  assert.equal(saved.body, '正門前に9:00集合');
  assert.equal(saved.priority, 'urgent');
  assert.equal(saved.createdBy, 'teacher_42');
  assert.equal(saved.createdByName, '鈴木');
  assert.deepEqual(saved.createdAt, fixedNow);

  assert.equal(notifiedGrade, 2);
  assert.equal(notifiedCourse, '観光');
  assert.equal(notifiedRoute, '/home');
  assert.equal(typeof notifiedMessage, 'function');
  assert.deepEqual(notifiedMessage('ja'), {
    title: '【緊急】お知らせ',
    body: '実習集合場所の変更',
  });
});

test('publishNotice uses empty string when author name is null or undefined', async () => {
  const db = new FakeDb();
  const notice = {
    grade: 1,
    course: null,
    title: '学年全体への連絡',
    body: '',
    priority: 'normal',
  };
  const res = await publishNotice('school.test', notice, { uid: 'u1' }, {
    db,
    now: () => new Date('2026-11-10T00:00:00Z'),
    notifyClass: async () => 0,
  });
  const saved = db.docs.get(`school_notices/${res.id}`);
  assert.equal(saved.createdByName, '');
  assert.equal(saved.course, null);
});

test('deleteNotice rejects invalid notice id', async () => {
  const db = new FakeDb();
  const badIds = [null, undefined, '', 123, 'id with space', 'a'.repeat(41), 'invalid/id', 'bad!id'];
  for (const id of badIds) {
    await assert.rejects(
      deleteNotice('school.test', id, 'u1', false, { db }),
      (err) => err.code === 'invalid-argument' && err.message.includes('A valid notice id is required'),
    );
  }
});

test('deleteNotice rejects not-found doc', async () => {
  const db = new FakeDb();
  await assert.rejects(
    deleteNotice('school.test', 'nonexistent', 'u1', false, { db }),
    (err) => err.code === 'not-found' && err.message.includes('Notice not found'),
  );
});

test('deleteNotice rejects notice belonging to another domain', async () => {
  const db = new FakeDb();
  db.seed('school_notices/n1', { domain: 'other.school.jp', createdBy: 'u1' });
  await assert.rejects(
    deleteNotice('school.test', 'n1', 'u1', false, { db }),
    (err) => err.code === 'not-found' && err.message.includes('Notice not found'),
  );
});

test('deleteNotice rejects non-author non-admin user with permission-denied', async () => {
  const db = new FakeDb();
  db.seed('school_notices/n1', { domain: 'school.test', createdBy: 'author_uid' });
  await assert.rejects(
    deleteNotice('school.test', 'n1', 'different_uid', false, { db }),
    (err) => err.code === 'permission-denied' && err.message.includes('Only the author or an admin'),
  );
  // Doc must still exist
  assert.ok(db.docs.has('school_notices/n1'));
});

test('deleteNotice allows author to delete and calls removeReads with the notice target', async () => {
  const db = new FakeDb();
  db.seed('school_notices/n1', { domain: 'school.example.jp', createdBy: 'author_uid' });
  let removedPath = null;
  const removeReads = async (path) => {
    removedPath = path;
  };

  const res = await deleteNotice('school.example.jp', 'n1', 'author_uid', false, { db, removeReads });
  assert.deepEqual(res, { ok: true });
  assert.equal(db.docs.has('school_notices/n1'), false);
  assert.equal(removedPath, 'n_n1');
});

test('deleteNotice allows admin to delete even if not the author', async () => {
  const db = new FakeDb();
  db.seed('school_notices/n2', { domain: 'school.example.jp', createdBy: 'author_uid' });
  let removedPath = null;
  const removeReads = async (path) => {
    removedPath = path;
  };

  const res = await deleteNotice('school.example.jp', 'n2', 'admin_uid', true, { db, removeReads });
  assert.deepEqual(res, { ok: true });
  assert.equal(db.docs.has('school_notices/n2'), false);
  assert.equal(removedPath, 'n_n2');
});

test('validateNotice checks category, subject tag and https link', () => {
  const base = { grade: 1, course: '農業', title: 't' };
  const v = validateNotice({ ...base, category: 'change', subject: ' 数学 ', link: ' https://drive.google.com/x ' }, SCHOOL);
  assert.equal(v.category, 'change');
  assert.equal(v.subject, '数学');
  assert.equal(v.link, 'https://drive.google.com/x');
  const bad = (o) => assert.throws(() => validateNotice({ ...base, ...o }, SCHOOL), { code: 'invalid-argument' });
  bad({ category: 'chat' });
  bad({ subject: 'x'.repeat(101) });
  bad({ link: 'http://example.com' });
  bad({ link: 'javascript:alert(1)' });
  bad({ link: 'https://a b' });
});

test('updateNotice corrects text, keeps the class fixed, and logs every action', async () => {
  const db = new FakeDb();
  const now = () => new Date('2026-11-13T00:00:00Z');
  const first = validateNotice({ grade: 1, course: '農業', title: '持ち物', body: 'a' }, SCHOOL);
  const { id } = await publishNotice('s.jp', first, { uid: 't1', name: '田中' }, { db, now, notifyClass: async () => 0 });

  const fixed = validateNotice({ grade: 1, course: '農業', title: '持ち物（訂正）', body: 'b', subject: '実習' }, SCHOOL);
  await assert.rejects(updateNotice('s.jp', id, fixed, 'other', false, { db, now }), { code: 'permission-denied' });
  await assert.rejects(updateNotice('other.jp', id, fixed, 't1', false, { db, now }), { code: 'not-found' });
  const moved = validateNotice({ grade: 2, course: '農業', title: 'x' }, SCHOOL);
  await assert.rejects(updateNotice('s.jp', id, moved, 't1', false, { db, now }), { code: 'invalid-argument' });

  await updateNotice('s.jp', id, fixed, 't1', false, { db, now });
  const saved = db.docs.get(`school_notices/${id}`);
  assert.equal(saved.title, '持ち物（訂正）');
  assert.equal(saved.subject, '実習');
  assert.equal(saved.createdBy, 't1');
  assert.deepEqual(saved.editedAt, now());

  await deleteNotice('s.jp', id, 'admin1', true, { db, now });
  const log = [...db.docs].filter(([p]) => p.startsWith('school_notice_log/')).map(([, d]) => `${d.action}:${d.by}`);
  assert.deepEqual(log, ['create:t1', 'edit:t1', 'delete:admin1']);
});
