import { test } from 'node:test';
import assert from 'node:assert/strict';
import { classKey, classSizes } from '../school/class_sizes.js';

class FakeDb {
  constructor() {
    this.docs = new Map();
  }

  seed(path, data) {
    this.docs.set(path, structuredClone(data));
  }

  collection(name) {
    return this._query(name, []);
  }

  _query(collectionName, filters) {
    return {
      where: (field, op, val) => this._query(collectionName, [...filters, [field, op, val]]),
      count: () => ({
        get: async () => {
          const matching = [...this.docs.entries()].filter(([path, data]) => {
            if (!path.startsWith(`${collectionName}/`)) return false;
            return filters.every(([field, op, val]) => {
              if (op === '==') return data[field] === val;
              return false;
            });
          });
          return {
            data: () => ({ count: matching.length }),
          };
        },
      }),
    };
  }
}

test('classKey formats <grade>_<course>', () => {
  assert.equal(classKey(1, '農業'), '1_農業');
  assert.equal(classKey('2', '観光'), '2_観光');
  assert.equal(classKey(3, '情報処理'), '3_情報処理');
});

test('classSizes returns keys for every grade x course with counts (0 when nobody)', async () => {
  const db = new FakeDb();
  const domain = 'school.example.jp';
  const school = {
    grades: [1, 2, 3],
    courses: ['農業', '観光'],
  };

  // Seed users
  db.seed('users/u1', { schoolDomain: domain, grade: '1', course: '農業' });
  db.seed('users/u2', { schoolDomain: domain, grade: '1', course: '農業' });
  db.seed('users/u3', { schoolDomain: domain, grade: '1', course: '観光' });
  db.seed('users/u4', { schoolDomain: domain, grade: '2', course: '観光' });
  db.seed('users/u5', { schoolDomain: domain, grade: '2', course: '観光' });
  db.seed('users/u6', { schoolDomain: domain, grade: '2', course: '観光' });

  const sizes = await classSizes(domain, school, { db });

  assert.deepEqual(sizes, {
    '1_農業': 2,
    '1_観光': 1,
    '2_農業': 0,
    '2_観光': 3,
    '3_農業': 0,
    '3_観光': 0,
  });
});

test('classSizes handles zero classes (empty grades, courses, or school)', async () => {
  const db = new FakeDb();
  const domain = 'school.example.jp';

  // Empty grades
  assert.deepEqual(await classSizes(domain, { grades: [], courses: ['農業'] }, { db }), {});
  // Empty courses
  assert.deepEqual(await classSizes(domain, { grades: [1], courses: [] }, { db }), {});
  // Empty school object
  assert.deepEqual(await classSizes(domain, {}, { db }), {});
  // Null school
  assert.deepEqual(await classSizes(domain, null, { db }), {});

  // All classes have 0 enrolled students when nobody is seeded
  const school = { grades: [1, 2], courses: ['普通科'] };
  assert.deepEqual(await classSizes(domain, school, { db }), {
    '1_普通科': 0,
    '2_普通科': 0,
  });
});

test('classSizes matches String(grade) correctly', async () => {
  const db = new FakeDb();
  const domain = 'school.example.jp';

  // School has numeric grades, but user documents store grade as String
  const school = {
    grades: [1, 2],
    courses: ['情報'],
  };

  db.seed('users/u1', { schoolDomain: domain, grade: '1', course: '情報' });
  db.seed('users/u2', { schoolDomain: domain, grade: '2', course: '情報' });
  // User with grade 3 should not be counted in grade 1 or 2
  db.seed('users/u3', { schoolDomain: domain, grade: '3', course: '情報' });

  const sizes = await classSizes(domain, school, { db });

  assert.equal(sizes['1_情報'], 1);
  assert.equal(sizes['2_情報'], 1);

  // Also verify when school.grades has string representations
  const schoolWithStringGrades = {
    grades: ['1', '2'],
    courses: ['情報'],
  };
  const sizesFromString = await classSizes(domain, schoolWithStringGrades, { db });
  assert.equal(sizesFromString['1_情報'], 1);
  assert.equal(sizesFromString['2_情報'], 1);
});

test('classSizes ignores users from other school domains', async () => {
  const db = new FakeDb();
  const targetDomain = 'our-school.ed.jp';
  const otherDomain = 'other-school.ed.jp';

  const school = {
    grades: [1],
    courses: ['普通科'],
  };

  // Seed user in target school
  db.seed('users/u_target', { schoolDomain: targetDomain, grade: '1', course: '普通科' });
  // Seed user in other school with matching grade and course
  db.seed('users/u_other', { schoolDomain: otherDomain, grade: '1', course: '普通科' });
  // Seed user with no domain
  db.seed('users/u_no_domain', { schoolDomain: null, grade: '1', course: '普通科' });

  const sizes = await classSizes(targetDomain, school, { db });

  assert.deepEqual(sizes, {
    '1_普通科': 1,
  });
});
