import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  PROGRESS_STATUSES,
  validateAssignment,
  assignmentPush,
  studentAssignmentId,
  publishAssignment,
  deleteAssignment,
  mirrorProgress,
} from '../school/assignments.js';

class FakeQuery {
  constructor(db, collectionName, filters = []) {
    this.db = db;
    this.collectionName = collectionName;
    this.filters = filters;
  }

  where(field, op, value) {
    return new FakeQuery(this.db, this.collectionName, [...this.filters, { field, op, value }]);
  }

  async get() {
    const prefix = `${this.collectionName}/`;
    const matchingDocs = [];
    for (const [path, data] of this.db.docs.entries()) {
      if (!path.startsWith(prefix)) continue;
      const sub = path.slice(prefix.length);
      if (sub.includes('/')) continue;

      let match = true;
      for (const { field, op, value } of this.filters) {
        if (op === '==') {
          if (data[field] !== value) {
            match = false;
            break;
          }
        }
      }
      if (match) {
        matchingDocs.push(this.db.snap(path));
      }
    }
    return { docs: matchingDocs };
  }
}

// Minimal in-memory Firestore for assignments tests (FakeDb pattern).
class FakeDb {
  constructor() {
    this.docs = new Map();
    this.autoIdCounter = 0;
    this.batchCommitCount = 0;
    this.updateError = null;
  }

  seed(path, data) {
    this.docs.set(path, structuredClone(data));
  }

  ref(path) {
    return {
      path,
      id: path.split('/').pop(),
      get: async () => this.snap(path),
      set: async (d) => {
        this.docs.set(path, structuredClone(d));
      },
      update: async (fields) => {
        if (this.updateError) throw this.updateError;
        const existing = this.docs.get(path);
        if (!existing) {
          throw new Error(`NOT_FOUND: No document at ${path}`);
        }
        Object.assign(existing, structuredClone(fields));
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
    const query = new FakeQuery(this, name);
    return {
      doc: (id) => {
        const docId = id ?? `assign${++this.autoIdCounter}`;
        return this.ref(`${name}/${docId}`);
      },
      where: (field, op, value) => query.where(field, op, value),
    };
  }

  batch() {
    const ops = [];
    return {
      set: (ref, data) => {
        ops.push(() => {
          this.docs.set(ref.path, structuredClone(data));
        });
      },
      commit: async () => {
        this.batchCommitCount++;
        for (const op of ops) {
          op();
        }
      },
    };
  }
}

const SCHOOL = {
  grades: [1, 2, 3],
  courses: ['情報', 'ビジネス'],
};

test('PROGRESS_STATUSES contains notStarted, inProgress, and completed', () => {
  assert.deepEqual(PROGRESS_STATUSES, ['notStarted', 'inProgress', 'completed']);
});

test('studentAssignmentId formats sourceId_uid', () => {
  assert.equal(studentAssignmentId('assign_123', 'student_456'), 'assign_123_student_456');
});

// --- validateAssignment ---

test('validateAssignment accepts valid input, trims fields, and returns dueAt as Date', () => {
  const now = new Date('2026-11-10T12:00:00Z');
  const dueMs = now.getTime() + 7 * 24 * 60 * 60 * 1000;
  const input = {
    grade: 2,
    course: '情報',
    subject: '  プログラミング演習  ',
    title: '  課題1：アルゴリズム実装  ',
    description: '  コードと実行結果を提出すること。  ',
    dueAt: dueMs,
  };

  const validated = validateAssignment(input, SCHOOL, now);
  assert.equal(validated.grade, 2);
  assert.equal(validated.course, '情報');
  assert.equal(validated.subject, 'プログラミング演習');
  assert.equal(validated.title, '課題1：アルゴリズム実装');
  assert.equal(validated.description, 'コードと実行結果を提出すること。');
  assert.ok(validated.dueAt instanceof Date);
  assert.equal(validated.dueAt.getTime(), dueMs);
});

test('validateAssignment allows course to be null or omitted for whole grade', () => {
  const now = new Date('2026-11-10T12:00:00Z');
  const dueMs = now.getTime() + 24 * 60 * 60 * 1000;

  const withNull = validateAssignment({
    grade: 1,
    course: null,
    subject: '数学',
    title: 'レポート',
    dueAt: dueMs,
  }, SCHOOL, now);
  assert.equal(withNull.grade, 1);
  assert.equal(withNull.course, null);

  const omitted = validateAssignment({
    grade: '3',
    subject: '英語',
    title: 'エッセイ',
    dueAt: dueMs,
  }, SCHOOL, now);
  assert.equal(omitted.grade, 3);
  assert.equal(omitted.course, null);
  assert.equal(omitted.description, '');
});

test('validateAssignment rejects unknown grade', () => {
  const now = new Date('2026-11-10T12:00:00Z');
  const dueMs = now.getTime() + 24 * 60 * 60 * 1000;

  assert.throws(
    () => validateAssignment({ grade: 4, course: '情報', subject: '数学', title: '課題', dueAt: dueMs }, SCHOOL, now),
    (err) => err.code === 'invalid-argument' && err.message.includes('Unknown grade'),
  );

  assert.throws(
    () => validateAssignment({ grade: 'abc', course: '情報', subject: '数学', title: '課題', dueAt: dueMs }, SCHOOL, now),
    (err) => err.code === 'invalid-argument' && err.message.includes('Unknown grade'),
  );

  assert.throws(
    () => validateAssignment({ course: '情報', subject: '数学', title: '課題', dueAt: dueMs }, SCHOOL, now),
    (err) => err.code === 'invalid-argument' && err.message.includes('Unknown grade'),
  );
});

test('validateAssignment rejects unknown course', () => {
  const now = new Date('2026-11-10T12:00:00Z');
  const dueMs = now.getTime() + 24 * 60 * 60 * 1000;

  assert.throws(
    () => validateAssignment({ grade: 1, course: 'デザイン', subject: '美術', title: 'デッサン', dueAt: dueMs }, SCHOOL, now),
    (err) => err.code === 'invalid-argument' && err.message.includes('Unknown course'),
  );
});

test('validateAssignment rejects empty or too long subject and title', () => {
  const now = new Date('2026-11-10T12:00:00Z');
  const dueMs = now.getTime() + 24 * 60 * 60 * 1000;

  // empty subject
  for (const emptySub of ['', '   ', null, undefined]) {
    assert.throws(
      () => validateAssignment({ grade: 1, course: '情報', subject: emptySub, title: '課題', dueAt: dueMs }, SCHOOL, now),
      (err) => err.code === 'invalid-argument' && err.message.includes('subject must be 1-100 chars'),
    );
  }

  // subject too long (> 100)
  assert.throws(
    () => validateAssignment({ grade: 1, course: '情報', subject: 'x'.repeat(101), title: '課題', dueAt: dueMs }, SCHOOL, now),
    (err) => err.code === 'invalid-argument' && err.message.includes('subject must be 1-100 chars'),
  );

  // empty title
  for (const emptyTitle of ['', '   ', null, undefined]) {
    assert.throws(
      () => validateAssignment({ grade: 1, course: '情報', subject: '数学', title: emptyTitle, dueAt: dueMs }, SCHOOL, now),
      (err) => err.code === 'invalid-argument' && err.message.includes('title must be 1-200 chars'),
    );
  }

  // title too long (> 200)
  assert.throws(
    () => validateAssignment({ grade: 1, course: '情報', subject: '数学', title: 'x'.repeat(201), dueAt: dueMs }, SCHOOL, now),
    (err) => err.code === 'invalid-argument' && err.message.includes('title must be 1-200 chars'),
  );
});

test('validateAssignment rejects description exceeding 2000 characters', () => {
  const now = new Date('2026-11-10T12:00:00Z');
  const dueMs = now.getTime() + 24 * 60 * 60 * 1000;

  const ok = validateAssignment({
    grade: 1,
    course: '情報',
    subject: '数学',
    title: '課題',
    description: 'd'.repeat(2000),
    dueAt: dueMs,
  }, SCHOOL, now);
  assert.equal(ok.description.length, 2000);

  assert.throws(
    () => validateAssignment({
      grade: 1,
      course: '情報',
      subject: '数学',
      title: '課題',
      description: 'd'.repeat(2001),
      dueAt: dueMs,
    }, SCHOOL, now),
    (err) => err.code === 'invalid-argument' && err.message.includes('description must be 0-2000 chars'),
  );
});

test('validateAssignment rejects dueAt that is not a finite number', () => {
  const now = new Date('2026-11-10T12:00:00Z');
  const badDueValues = ['not-a-number', NaN, null, undefined, Infinity, -Infinity];

  for (const badDue of badDueValues) {
    assert.throws(
      () => validateAssignment({ grade: 1, course: '情報', subject: '数学', title: '課題', dueAt: badDue }, SCHOOL, now),
      (err) => err.code === 'invalid-argument' && err.message.includes('dueAt must be a time from today to one year ahead'),
    );
  }
});

test('validateAssignment rejects dueAt more than a day in the past', () => {
  const now = new Date('2026-11-10T12:00:00Z');
  const dayMs = 24 * 60 * 60 * 1000;

  // Exactly more than 1 day in the past by 1ms
  assert.throws(
    () => validateAssignment({
      grade: 1,
      course: '情報',
      subject: '数学',
      title: '課題',
      dueAt: now.getTime() - dayMs - 1,
    }, SCHOOL, now),
    (err) => err.code === 'invalid-argument' && err.message.includes('dueAt must be a time from today to one year ahead'),
  );

  // Exactly 1 day in the past is permitted (dueMs >= now.getTime() - DAY_MS)
  const valid = validateAssignment({
    grade: 1,
    course: '情報',
    subject: '数学',
    title: '課題',
    dueAt: now.getTime() - dayMs,
  }, SCHOOL, now);
  assert.ok(valid.dueAt instanceof Date);
});

test('validateAssignment rejects dueAt more than a year ahead', () => {
  const now = new Date('2026-11-10T12:00:00Z');
  const maxAheadMs = 366 * 24 * 60 * 60 * 1000;

  // More than 366 days ahead by 1ms
  assert.throws(
    () => validateAssignment({
      grade: 1,
      course: '情報',
      subject: '数学',
      title: '課題',
      dueAt: now.getTime() + maxAheadMs + 1,
    }, SCHOOL, now),
    (err) => err.code === 'invalid-argument' && err.message.includes('dueAt must be a time from today to one year ahead'),
  );

  // Exactly 366 days ahead is permitted
  const valid = validateAssignment({
    grade: 1,
    course: '情報',
    subject: '数学',
    title: '課題',
    dueAt: now.getTime() + maxAheadMs,
  }, SCHOOL, now);
  assert.ok(valid.dueAt instanceof Date);
});

// --- assignmentPush ---

test('assignmentPush formats ja and en text with subject, title, and due date', () => {
  // 2026-11-05T03:00:00Z + 9h (JST) is 2026-11-05 12:00 (Thursday / 木)
  const dueAt = new Date('2026-11-05T03:00:00Z');
  const a = {
    subject: 'IT概論2',
    title: '中間レポート提出',
    dueAt,
  };

  const pushFn = assignmentPush(a);

  // Japanese push
  const ja = pushFn('ja');
  assert.equal(ja.title, '新しい課題');
  assert.ok(ja.body.includes('IT概論2'));
  assert.ok(ja.body.includes('中間レポート提出'));
  assert.ok(ja.body.includes('11/5'));
  assert.ok(ja.body.includes('木'));

  // English push
  const en = pushFn('en');
  assert.equal(en.title, 'New assignment');
  assert.ok(en.body.includes('IT概論2'));
  assert.ok(en.body.includes('中間レポート提出'));
  assert.ok(en.body.includes('11/5'));
});

// --- publishAssignment ---

test('publishAssignment writes school_assignments doc and student docs with exact fields', async () => {
  const db = new FakeDb();
  const domain = 'school.example.jp';
  const author = { uid: 'teacher_10', name: '佐藤教員' };
  const fixedNow = new Date('2026-11-10T10:00:00Z');
  const fixedDue = new Date('2026-11-17T15:00:00Z');

  // Seed students in users collection
  db.seed('users/stu_1', { schoolDomain: domain, grade: '2', course: '情報', name: '山田太郎' });
  db.seed('users/stu_2', { schoolDomain: domain, grade: '2', course: '情報', name: '田中花子' });
  // Mismatched users that should not receive the assignment
  db.seed('users/other_domain', { schoolDomain: 'other.domain.jp', grade: '2', course: '情報', name: '他校生徒' });
  db.seed('users/other_grade', { schoolDomain: domain, grade: '1', course: '情報', name: '1年生徒' });
  db.seed('users/other_course', { schoolDomain: domain, grade: '2', course: 'ビジネス', name: '別コース生徒' });

  const assignment = {
    grade: 2,
    course: '情報',
    subject: 'Web開発演習',
    title: '課題2：API連携',
    description: 'Firebase Functionsと連携するアプリを作成せよ。',
    dueAt: fixedDue,
  };

  let notifiedGrade = null;
  let notifiedCourse = null;
  let notifiedMessage = null;
  let notifiedRoute = null;

  const notifyClass = async (grade, course, message, route) => {
    notifiedGrade = grade;
    notifiedCourse = course;
    notifiedMessage = message;
    notifiedRoute = route;
    return 2;
  };

  const res = await publishAssignment(domain, assignment, author, {
    db,
    now: () => fixedNow,
    notifyClass,
  });

  assert.equal(res.students, 2);
  assert.equal(res.pushed, 2);
  assert.ok(typeof res.id === 'string' && res.id.length > 0);

  // Check school_assignments doc
  const schoolAssignDoc = db.docs.get(`school_assignments/${res.id}`);
  assert.deepEqual(schoolAssignDoc, {
    domain,
    grade: 2,
    course: '情報',
    subject: 'Web開発演習',
    title: '課題2：API連携',
    description: 'Firebase Functionsと連携するアプリを作成せよ。',
    dueAt: fixedDue,
    createdBy: 'teacher_10',
    createdByName: '佐藤教員',
    createdAt: fixedNow,
    total: 2,
  });

  // Check assignments docs and school_assignment_progress docs for each student
  for (const stuId of ['stu_1', 'stu_2']) {
    const studentDocId = `${res.id}_${stuId}`;

    const assignDoc = db.docs.get(`assignments/${studentDocId}`);
    assert.deepEqual(assignDoc, {
      userId: stuId,
      title: '課題2：API連携',
      subject: 'Web開発演習',
      description: 'Firebase Functionsと連携するアプリを作成せよ。',
      dueDate: fixedDue,
      status: 'notStarted',
      difficulty: 1,
      progress: 0,
      createdAt: fixedNow,
      aiMissingParts: [],
      sourceId: res.id,
      sourceDomain: domain,
      sourceTeacher: '佐藤教員',
    });

    const studentName = stuId === 'stu_1' ? '山田太郎' : '田中花子';
    const progressDoc = db.docs.get(`school_assignment_progress/${studentDocId}`);
    assert.deepEqual(progressDoc, {
      domain,
      sourceId: res.id,
      uid: stuId,
      name: studentName,
      status: 'notStarted',
      progress: 0,
      updatedAt: fixedNow,
    });
  }

  // Ensure other users did not get assignments
  assert.equal(db.docs.has(`assignments/${res.id}_other_domain`), false);
  assert.equal(db.docs.has(`assignments/${res.id}_other_grade`), false);
  assert.equal(db.docs.has(`assignments/${res.id}_other_course`), false);

  // Verify notifyClass call parameters
  assert.equal(notifiedGrade, 2);
  assert.equal(notifiedCourse, '情報');
  assert.equal(notifiedRoute, '/assignments');
  assert.equal(typeof notifiedMessage, 'function');
  const pushJa = notifiedMessage('ja');
  assert.equal(pushJa.title, '新しい課題');
  assert.ok(pushJa.body.includes('Web開発演習'));
});

test('publishAssignment excludes the author even if they match the class query', async () => {
  const db = new FakeDb();
  const domain = 'school.example.jp';
  const authorUid = 'teacher_student_mix';
  const author = { uid: authorUid, name: '先生兼受講生' };
  const fixedNow = new Date('2026-11-10T10:00:00Z');

  // Both the author and another student match the class query
  db.seed(`users/${authorUid}`, { schoolDomain: domain, grade: '3', course: '情報', name: '先生兼受講生' });
  db.seed('users/stu_real', { schoolDomain: domain, grade: '3', course: '情報', name: '正規生徒' });

  const assignment = {
    grade: 3,
    course: '情報',
    subject: '総合演習',
    title: '卒業制作',
    description: '',
    dueAt: new Date('2026-12-01T00:00:00Z'),
  };

  const res = await publishAssignment(domain, assignment, author, {
    db,
    now: () => fixedNow,
    notifyClass: async () => 1,
  });

  // Only the real student is counted and received docs
  assert.equal(res.students, 1);
  const schoolAssignDoc = db.docs.get(`school_assignments/${res.id}`);
  assert.equal(schoolAssignDoc.total, 1);

  assert.equal(db.docs.has(`assignments/${res.id}_${authorUid}`), false);
  assert.equal(db.docs.has(`school_assignment_progress/${res.id}_${authorUid}`), false);

  assert.equal(db.docs.has(`assignments/${res.id}_stu_real`), true);
  assert.equal(db.docs.has(`school_assignment_progress/${res.id}_stu_real`), true);
});

test('publishAssignment with course null queries only by domain and grade', async () => {
  const db = new FakeDb();
  const domain = 'school.example.jp';
  const author = { uid: 'teacher_grade_head', name: '学年主任' };

  // Students in grade 1 across different courses, plus course null
  db.seed('users/stu_c1', { schoolDomain: domain, grade: '1', course: '情報', name: '情報生' });
  db.seed('users/stu_c2', { schoolDomain: domain, grade: '1', course: 'ビジネス', name: 'ビジネス生' });
  db.seed('users/stu_c_null', { schoolDomain: domain, grade: '1', course: null, name: '無所属生' });
  db.seed('users/stu_g2', { schoolDomain: domain, grade: '2', course: '情報', name: '2年生' });

  const assignment = {
    grade: 1,
    course: null,
    subject: '一般教養',
    title: '全学年共通課題',
    description: null,
    dueAt: new Date('2026-11-20T00:00:00Z'),
  };

  let notifiedCourse = 'NOT_CALLED';
  const res = await publishAssignment(domain, assignment, author, {
    db,
    now: () => new Date('2026-11-10T00:00:00Z'),
    notifyClass: async (grade, course) => {
      notifiedCourse = course;
      return 3;
    },
  });

  assert.equal(res.students, 3);
  assert.equal(notifiedCourse, null);

  assert.ok(db.docs.has(`assignments/${res.id}_stu_c1`));
  assert.ok(db.docs.has(`assignments/${res.id}_stu_c2`));
  assert.ok(db.docs.has(`assignments/${res.id}_stu_c_null`));
  assert.equal(db.docs.has(`assignments/${res.id}_stu_g2`), false);
});

test('publishAssignment splits more than 200 students across batches', async () => {
  const db = new FakeDb();
  const domain = 'large.school.jp';
  const author = { uid: 'teacher_large', name: '大講義担当' };
  const studentCount = 210;

  for (let i = 1; i <= studentCount; i++) {
    db.seed(`users/student_${i}`, {
      schoolDomain: domain,
      grade: '1',
      course: '情報',
      name: `生徒${i}`,
    });
  }

  const assignment = {
    grade: 1,
    course: '情報',
    subject: '大規模テスト',
    title: 'バッチ分割検証課題',
    description: '200名以上のバッチテスト',
    dueAt: new Date('2026-11-30T00:00:00Z'),
  };

  const res = await publishAssignment(domain, assignment, author, {
    db,
    now: () => new Date('2026-11-10T00:00:00Z'),
    notifyClass: async () => studentCount,
  });

  assert.equal(res.students, studentCount);
  // BATCH_MAX is 200, so 210 students should result in 2 batch commits (200 + 10)
  assert.equal(db.batchCommitCount, 2);

  const schoolAssignDoc = db.docs.get(`school_assignments/${res.id}`);
  assert.equal(schoolAssignDoc.total, studentCount);

  // Check first and last student docs
  assert.ok(db.docs.has(`assignments/${res.id}_student_1`));
  assert.ok(db.docs.has(`school_assignment_progress/${res.id}_student_1`));
  assert.ok(db.docs.has(`assignments/${res.id}_student_210`));
  assert.ok(db.docs.has(`school_assignment_progress/${res.id}_student_210`));
});

// --- deleteAssignment ---

test('deleteAssignment rejects invalid assignment id', async () => {
  const db = new FakeDb();
  const badIds = [null, undefined, '', 123, 'id with space', 'a'.repeat(41), 'invalid/id', 'bad!id', 'with_underscore'];
  for (const id of badIds) {
    await assert.rejects(
      deleteAssignment('school.jp', id, 'teacher_1', false, { db, deleteQuery: async () => {} }),
      (err) => err.code === 'invalid-argument' && err.message.includes('A valid assignment id is required'),
    );
  }
});

test('deleteAssignment rejects not-found doc', async () => {
  const db = new FakeDb();
  await assert.rejects(
    deleteAssignment('school.jp', 'nonexistent', 'teacher_1', false, { db, deleteQuery: async () => {} }),
    (err) => err.code === 'not-found' && err.message.includes('Assignment not found'),
  );
});

test('deleteAssignment rejects assignment belonging to another domain', async () => {
  const db = new FakeDb();
  db.seed('school_assignments/as1', { domain: 'other.domain.jp', createdBy: 'teacher_1' });

  await assert.rejects(
    deleteAssignment('school.jp', 'as1', 'teacher_1', false, { db, deleteQuery: async () => {} }),
    (err) => err.code === 'not-found' && err.message.includes('Assignment not found'),
  );
  // Doc should still exist
  assert.ok(db.docs.has('school_assignments/as1'));
});

test('deleteAssignment rejects non-author non-admin user with permission-denied', async () => {
  const db = new FakeDb();
  db.seed('school_assignments/as1', { domain: 'school.jp', createdBy: 'author_uid' });

  await assert.rejects(
    deleteAssignment('school.jp', 'as1', 'different_uid', false, { db, deleteQuery: async () => {} }),
    (err) => err.code === 'permission-denied' && err.message.includes('Only the author or an admin can delete'),
  );
  assert.ok(db.docs.has('school_assignments/as1'));
});

test('deleteAssignment allows author to delete and calls deleteQuery for both collections filtered by sourceId', async () => {
  const db = new FakeDb();
  const id = 'asTarget1';
  db.seed(`school_assignments/${id}`, { domain: 'school.jp', createdBy: 'author_uid' });

  const deletedQueries = [];
  const deleteQuery = async (query) => {
    deletedQueries.push(query);
  };

  const res = await deleteAssignment('school.jp', id, 'author_uid', false, { db, deleteQuery });
  assert.deepEqual(res, { ok: true });
  assert.equal(db.docs.has(`school_assignments/${id}`), false);

  assert.equal(deletedQueries.length, 2);
  const collections = deletedQueries.map((q) => q.collectionName);
  assert.ok(collections.includes('assignments'));
  assert.ok(collections.includes('school_assignment_progress'));

  for (const q of deletedQueries) {
    const filter = q.filters.find((f) => f.field === 'sourceId');
    assert.ok(filter, 'Must filter by sourceId');
    assert.equal(filter.op, '==');
    assert.equal(filter.value, id);
  }
});

test('deleteAssignment allows admin to delete even if not author', async () => {
  const db = new FakeDb();
  const id = 'asAdminTarget1';
  db.seed(`school_assignments/${id}`, { domain: 'school.jp', createdBy: 'author_uid' });

  const deletedQueries = [];
  const deleteQuery = async (query) => {
    deletedQueries.push(query);
  };

  const res = await deleteAssignment('school.jp', id, 'admin_uid', true, { db, deleteQuery });
  assert.deepEqual(res, { ok: true });
  assert.equal(db.docs.has(`school_assignments/${id}`), false);
  assert.equal(deletedQueries.length, 2);
});

// --- mirrorProgress ---

test('mirrorProgress returns false and does not write when sourceId or sourceDomain is missing', async () => {
  const db = new FakeDb();
  const now = () => new Date('2026-11-10T10:00:00Z');

  // null or undefined after
  assert.equal(await mirrorProgress('as1_u1', null, null, { db, now }), false);
  assert.equal(await mirrorProgress('as1_u1', {}, undefined, { db, now }), false);

  // missing sourceId
  assert.equal(await mirrorProgress('as1_u1', {}, { sourceDomain: 'school.jp', status: 'inProgress' }, { db, now }), false);

  // missing sourceDomain
  assert.equal(await mirrorProgress('as1_u1', {}, { sourceId: 'as1', status: 'inProgress' }, { db, now }), false);

  // personal assignment with neither sourceId nor sourceDomain
  assert.equal(await mirrorProgress('personal_1', {}, { status: 'completed', progress: 1 }, { db, now }), false);

  assert.equal(db.docs.size, 0);
});

test('mirrorProgress returns false when status and progress are unchanged', async () => {
  const db = new FakeDb();
  const now = () => new Date('2026-11-10T10:00:00Z');
  db.seed('school_assignment_progress/as1_u1', { status: 'inProgress', progress: 0.5 });

  const before = { sourceId: 'as1', sourceDomain: 'school.jp', status: 'inProgress', progress: 0.5 };
  const after = { sourceId: 'as1', sourceDomain: 'school.jp', status: 'inProgress', progress: 0.5, title: 'new title' };

  const written = await mirrorProgress('as1_u1', before, after, { db, now });
  assert.equal(written, false);
});

test('mirrorProgress updates progress doc with clamped progress and valid status', async () => {
  const db = new FakeDb();
  const fixedNow = new Date('2026-11-10T10:00:00Z');
  const now = () => fixedNow;

  db.seed('school_assignment_progress/as1_u1', {
    domain: 'school.jp',
    sourceId: 'as1',
    uid: 'u1',
    status: 'notStarted',
    progress: 0,
  });

  const before = { sourceId: 'as1', sourceDomain: 'school.jp', status: 'notStarted', progress: 0 };
  const after = { sourceId: 'as1', sourceDomain: 'school.jp', status: 'completed', progress: 1.5 };

  const written = await mirrorProgress('as1_u1', before, after, { db, now });
  assert.equal(written, true);

  const updated = db.docs.get('school_assignment_progress/as1_u1');
  assert.equal(updated.status, 'completed');
  // Clamped to 1
  assert.equal(updated.progress, 1);
  assert.deepEqual(updated.updatedAt, fixedNow);

  // Also test clamping below 0
  const afterNegative = { sourceId: 'as1', sourceDomain: 'school.jp', status: 'inProgress', progress: -0.5 };
  const writtenNegative = await mirrorProgress('as1_u1', after, afterNegative, { db, now });
  assert.equal(writtenNegative, true);

  const updatedNegative = db.docs.get('school_assignment_progress/as1_u1');
  assert.equal(updatedNegative.status, 'inProgress');
  assert.equal(updatedNegative.progress, 0);
});

test('mirrorProgress falls back to notStarted when status is unknown', async () => {
  const db = new FakeDb();
  const fixedNow = new Date('2026-11-10T10:00:00Z');
  const now = () => fixedNow;

  db.seed('school_assignment_progress/as1_u1', {
    status: 'inProgress',
    progress: 0.2,
  });

  const before = { sourceId: 'as1', sourceDomain: 'school.jp', status: 'inProgress', progress: 0.2 };
  const after = { sourceId: 'as1', sourceDomain: 'school.jp', status: 'custom_unknown_status', progress: 0.7 };

  const written = await mirrorProgress('as1_u1', before, after, { db, now });
  assert.equal(written, true);

  const updated = db.docs.get('school_assignment_progress/as1_u1');
  assert.equal(updated.status, 'notStarted');
  assert.equal(updated.progress, 0.7);
  assert.deepEqual(updated.updatedAt, fixedNow);
});

test('mirrorProgress returns false when update throws', async () => {
  const db = new FakeDb();
  const now = () => new Date('2026-11-10T10:00:00Z');

  // Doc does not exist in school_assignment_progress, so ref.update throws NOT_FOUND
  const before = { sourceId: 'as1', sourceDomain: 'school.jp', status: 'notStarted', progress: 0 };
  const after = { sourceId: 'as1', sourceDomain: 'school.jp', status: 'completed', progress: 1 };

  const writtenMissing = await mirrorProgress('nonexistent_doc', before, after, { db, now });
  assert.equal(writtenMissing, false);

  // Forced error on update
  db.seed('school_assignment_progress/as1_u1', { status: 'notStarted', progress: 0 });
  db.updateError = new Error('Database connection failed');

  const writtenError = await mirrorProgress('as1_u1', before, after, { db, now });
  assert.equal(writtenError, false);
});
