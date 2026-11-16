import { HttpsError } from 'firebase-functions/https';
import { formatPushDate, pt } from './push_i18n.js';

// 課題配布 (§9.2-3): a teacher hands one assignment to a class or a whole
// grade. The server copies it into every student's own `assignments` (so it
// shows in their list like any other) and keeps a small progress doc per
// student that teachers can read. Students never see each other's progress.
// UZ: 課題配布 (§9.2-3): o'qituvchi bitta topshiriqni sinfga yoki butun kursga topshiradi.
// Server uni har bir talabaning shaxsiy `assignments` to'plamiga nusxalaydi (shunda u boshqalar kabi
// ularning ro'yxatida ko'rinadi) va o'qituvchilar o'qiy oladigan har bir talaba uchun kichik progress
// doc saqlaydi. Talabalar hech qachon bir-birining progressini ko'rmaydi.
const MAX_SUBJECT = 100;
const MAX_TITLE = 200;
const MAX_DESCRIPTION = 2000;
const MAX_DUE_AHEAD_MS = 366 * 24 * 60 * 60 * 1000;
const DAY_MS = 24 * 60 * 60 * 1000;
const BATCH_MAX = 200; // two writes per student, under the 500 batch ceiling
export const PROGRESS_STATUSES = ['notStarted', 'inProgress', 'completed'];

const bad = (m) => { throw new HttpsError('invalid-argument', m); };
const text = (v, max, name, required) => {
  const s = typeof v === 'string' ? v.trim() : '';
  if ((required && !s) || s.length > max) bad(`${name} must be ${required ? '1' : '0'}-${max} chars.`);
  return s;
};

/** Validated input; course null = every course of the grade. dueAt is epoch ms. */
// UZ: Tasdiqlangan kiritish ma'lumotlari; course null = bosqichning har bir kursi. dueAt bu epoch ms.
export function validateAssignment(input, school, now) {
  const d = input ?? {};
  const grade = Number(d.grade);
  if (!(school.grades ?? []).includes(grade)) bad('Unknown grade.');
  const course = d.course ?? null;
  if (course !== null && !(school.courses ?? []).includes(course)) bad('Unknown course.');
  const dueMs = Number(d.dueAt);
  if (!Number.isFinite(dueMs) || dueMs < now.getTime() - DAY_MS || dueMs > now.getTime() + MAX_DUE_AHEAD_MS) {
    bad('dueAt must be a time from today to one year ahead.');
  }
  return {
    grade,
    course,
    subject: text(d.subject, MAX_SUBJECT, 'subject', true),
    title: text(d.title, MAX_TITLE, 'title', true),
    description: text(d.description, MAX_DESCRIPTION, 'description', false),
    dueAt: new Date(dueMs),
  };
}

// Japan has no DST, so +9h gives the Tokyo calendar date of the deadline.
// UZ: Yaponiyada DST (yozgi vaqt) yo'q, shuning uchun +9h muddatning Tokyo taqvim sanasini beradi.
const tokyoIso = (date) => new Date(date.getTime() + 9 * 60 * 60 * 1000).toISOString().slice(0, 10);

/** Push for a new assignment: "IT概論2：レポート提出（期限: 11/5（木））". */
// UZ: Yangi topshiriq uchun push: "IT概論2：レポート提出（期限: 11/5（木））".
export const assignmentPush = (a) => (lang) => ({
  title: pt(lang, 'push_assignment_title'),
  body: pt(lang, 'push_assignment_body', {
    subject: a.subject,
    title: a.title,
    when: formatPushDate(tokyoIso(a.dueAt), lang),
  }),
});

export const studentAssignmentId = (sourceId, uid) => `${sourceId}_${uid}`;

/**
 * Saves the assignment, copies it to each student of the class and pushes
 * it. `notifyClass(grade, course, message, route)` is injected.
 * Returns {id, students, pushed}.
 * UZ: Topshiriqni saqlaydi, uni sinfdagi har bir talabaga nusxalaydi va push xabarnoma yuboradi.
 * `notifyClass(grade, course, message, route)` inyeksiya qilinadi. {id, students, pushed} qaytaradi.
 */
export async function publishAssignment(domain, a, author, { db, now, notifyClass }) {
  let query = db.collection('users')
    .where('schoolDomain', '==', domain)
    .where('grade', '==', String(a.grade));
  if (a.course != null) query = query.where('course', '==', a.course);
  // The author may have a student profile of the same class: not a recipient.
  // UZ: Muallif xuddi shu sinfning talaba profiliga ega bo'lishi mumkin: u qabul qiluvchi emas.
  const students = (await query.get()).docs.filter((d) => d.id !== author.uid);

  const ref = db.collection('school_assignments').doc();
  const at = now();
  await ref.set({
    domain,
    ...a,
    createdBy: author.uid,
    createdByName: author.name ?? '',
    createdAt: at,
    total: students.length,
  });

  for (let i = 0; i < students.length; i += BATCH_MAX) {
    const batch = db.batch();
    for (const s of students.slice(i, i + BATCH_MAX)) {
      const id = studentAssignmentId(ref.id, s.id);
      batch.set(db.collection('assignments').doc(id), {
        userId: s.id,
        title: a.title,
        subject: a.subject,
        description: a.description || null,
        dueDate: a.dueAt,
        status: 'notStarted',
        difficulty: 1,
        progress: 0,
        createdAt: at,
        aiMissingParts: [],
        sourceId: ref.id,
        sourceDomain: domain,
        sourceTeacher: author.name ?? '',
      });
      batch.set(db.collection('school_assignment_progress').doc(id), {
        domain,
        sourceId: ref.id,
        uid: s.id,
        name: String(s.data().name ?? '').slice(0, 200),
        status: 'notStarted',
        progress: 0,
        updatedAt: at,
      });
    }
    await batch.commit();
  }

  const pushed = await notifyClass(a.grade, a.course, assignmentPush(a), '/assignments');
  return { id: ref.id, students: students.length, pushed };
}

/**
 * Only the author or a school admin deletes. Removes the students' copies and
 * progress docs too. `deleteQuery(query)` is injected.
 * UZ: Faqat muallif yoki maktab admini o'chiradi. Talabalarning nusxalari va progress
 * hujjatlarini ham olib tashlaydi. `deleteQuery(query)` inyeksiya qilinadi.
 */
export async function deleteAssignment(domain, id, uid, isAdmin, { db, deleteQuery }) {
  if (typeof id !== 'string' || !/^[A-Za-z0-9]{1,40}$/.test(id)) bad('A valid assignment id is required.');
  const ref = db.collection('school_assignments').doc(id);
  const snap = await ref.get();
  if (!snap.exists || snap.data().domain !== domain) {
    throw new HttpsError('not-found', 'Assignment not found.');
  }
  if (snap.data().createdBy !== uid && !isAdmin) {
    throw new HttpsError('permission-denied', 'Only the author or an admin can delete this assignment.');
  }
  await Promise.all([
    deleteQuery(db.collection('assignments').where('sourceId', '==', id)),
    deleteQuery(db.collection('school_assignment_progress').where('sourceId', '==', id)),
  ]);
  await ref.delete();
  return { ok: true };
}

/**
 * Trigger body for `assignments/{id}` updates: mirrors a distributed
 * assignment's status/progress into its teacher-readable progress doc.
 * Returns true when it wrote.
 * UZ: `assignments/{id}` yangilanishlari uchun trigger tanasi: tarqatilgan topshiriqning
 * status/progress qiymatlarini o'qituvchi o'qiy oladigan progress hujjatiga aks ettiradi.
 * Yozilganda true qaytaradi.
 */
export async function mirrorProgress(id, before, after, { db, now }) {
  if (!after?.sourceId || !after.sourceDomain) return false;
  if (before?.status === after.status && before?.progress === after.progress) return false;
  const status = PROGRESS_STATUSES.includes(after.status) ? after.status : 'notStarted';
  const progress = Math.min(1, Math.max(0, Number(after.progress) || 0));
  // update, not set: a progress doc removed with its assignment stays gone.
  // UZ: set emas, update: topshirig'i bilan birga o'chirilgan progress hujjati o'chirilganicha qoladi.
  try {
    await db.collection('school_assignment_progress').doc(id).update({ status, progress, updatedAt: now() });
    return true;
  } catch {
    return false;
  }
}
