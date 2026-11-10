import { HttpsError } from 'firebase-functions/https';
import { pt } from './push_i18n.js';
import { rtdbKey } from './overrides.js';

// お知らせボード (§9.2-4): a teacher's message to one class or a whole grade.
// Written only by Cloud Functions; students of the school read it and mark
// it read in RTDB (reads/{domain}/notices/{id}/{uid}, same rules as 既読).
export const NOTICE_PRIORITIES = ['normal', 'urgent'];
const MAX_TITLE = 60;
const MAX_BODY = 1000;

const bad = (m) => { throw new HttpsError('invalid-argument', m); };

/** Validated notice input; course null = every course of the grade. */
export function validateNotice(input, school) {
  const d = input ?? {};
  const grade = Number(d.grade);
  if (!(school.grades ?? []).includes(grade)) bad('Unknown grade.');
  const course = d.course ?? null;
  if (course !== null && !(school.courses ?? []).includes(course)) bad('Unknown course.');
  const title = typeof d.title === 'string' ? d.title.trim() : '';
  if (!title || title.length > MAX_TITLE) bad(`title must be 1-${MAX_TITLE} chars.`);
  const body = typeof d.body === 'string' ? d.body.trim() : '';
  if (body.length > MAX_BODY) bad(`body must be at most ${MAX_BODY} chars.`);
  const priority = d.priority ?? 'normal';
  if (!NOTICE_PRIORITIES.includes(priority)) bad('Unknown priority.');
  return { grade, course, title, body, priority };
}

/** `reads/{domain}/notices/{id}` — one student uid per 既読. */
export const noticeReadsPath = (domain, id) => `reads/${rtdbKey(domain)}/notices/${rtdbKey(id)}`;

/** Push for one notice: urgent gets its own title; body is the teacher's title. */
export const noticePush = (notice) => (lang) => ({
  title: pt(lang, notice.priority === 'urgent' ? 'push_notice_urgent' : 'push_notice_title'),
  body: notice.title,
});

/**
 * Saves [notice] and pushes it to its class (or grade). `notifyClass(grade,
 * course, message, route)` is injected. Returns {id, pushed}.
 */
export async function publishNotice(domain, notice, author, { db, now, notifyClass }) {
  const ref = db.collection('school_notices').doc();
  await ref.set({
    domain,
    ...notice,
    createdBy: author.uid,
    createdByName: author.name ?? '',
    createdAt: now(),
  });
  const pushed = await notifyClass(notice.grade, notice.course, noticePush(notice), '/home');
  return { id: ref.id, pushed };
}

/** Only the author or a school admin deletes; also drops its 既読 receipts. */
export async function deleteNotice(domain, id, uid, isAdmin, { db, removeReads }) {
  if (typeof id !== 'string' || !/^[A-Za-z0-9]{1,40}$/.test(id)) bad('A valid notice id is required.');
  const ref = db.collection('school_notices').doc(id);
  const snap = await ref.get();
  if (!snap.exists || snap.data().domain !== domain) {
    throw new HttpsError('not-found', 'Notice not found.');
  }
  if (snap.data().createdBy !== uid && !isAdmin) {
    throw new HttpsError('permission-denied', 'Only the author or an admin can delete this notice.');
  }
  await ref.delete();
  await removeReads?.(noticeReadsPath(domain, id));
  return { ok: true };
}
