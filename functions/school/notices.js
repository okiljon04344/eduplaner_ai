import { HttpsError } from 'firebase-functions/https';
import { pt } from './push_i18n.js';
import { noticeReadTarget } from './overrides.js';

// お知らせボード (§9.2-4): a teacher's message to one class or a whole grade.
// Written only by Cloud Functions; students of the school read it and mark
// it read in Firestore (school_reads, see readTarget in overrides.js).
// UZ: お知らせボード (§9.2-4): o'qituvchining bitta sinfga yoki butun kursga xabari.
// Faqat Cloud Functions tomonidan yoziladi; maktab talabalari uni o'qiydi va
// Firestore'da o'qilgan deb belgilaydi (school_reads, overrides.js dagi readTarget ga qarang).
export const NOTICE_PRIORITIES = ['normal', 'urgent'];
const MAX_TITLE = 60;
const MAX_BODY = 1000;
const MAX_SUBJECT = 100;
const NOTICE_CATEGORIES = ['change', 'contact', 'assignment'];
// Links only (no file storage): https, no whitespace, bounded length.
// UZ: Faqat havolalar (fayl saqlash joyi yo'q): https, bo'sh joylarsiz, chegaralangan uzunlik.
const LINK_RE = /^https:\/\/[^\s]{1,490}$/;

const bad = (m) => { throw new HttpsError('invalid-argument', m); };

/** Validated notice input; course null = every course of the grade. */
// UZ: Tasdiqlangan bildirishnoma kiritmasi; course null = bosqichning har bir kursi.
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
  const category = d.category ?? 'contact';
  if (!NOTICE_CATEGORIES.includes(category)) bad('Unknown category.');
  const subject = typeof d.subject === 'string' ? d.subject.trim() : '';
  if (subject.length > MAX_SUBJECT) bad(`subject must be at most ${MAX_SUBJECT} chars.`);
  const link = typeof d.link === 'string' ? d.link.trim() : '';
  if (link && !LINK_RE.test(link)) bad('link must be an https URL.');
  return { grade, course, title, body, priority, category, subject, link };
}

/// Append-only record of who posted, corrected or deleted a notice. The
/// collection has no client rule, so only Cloud Functions touch it.
///
/// UZ: Bildirishnomani kim joylashtirgani, tuzatgani yoki o'chirgani haqidagi faqat qo'shiladigan
/// (append-only) yozuv. To'plamda mijoz qoidasi yo'q, shuning uchun unga faqat Cloud Functions tegadi.
const logNotice = (db, domain, noticeId, action, uid, at, notice) =>
  db.collection('school_notice_log').doc().set({ domain, noticeId, action, by: uid, at, ...(notice ? { notice } : {}) });

/** Push for one notice: urgent gets its own title; body is the teacher's title. */
// UZ: Bitta bildirishnoma uchun push: urgent o'z sarlavhasiga ega bo'ladi; body - o'qituvchi sarlavhasi.
export const noticePush = (notice) => (lang) => ({
  title: pt(lang, notice.priority === 'urgent' ? 'push_notice_urgent' : 'push_notice_title'),
  body: notice.title,
});

/**
 * Saves [notice] and pushes it to its class (or grade). `notifyClass(grade,
 * course, message, route)` is injected. Returns {id, pushed}.
 * UZ: [notice] ni saqlaydi va uni o'z sinfiga (yoki kursiga) push qiladi. `notifyClass(grade,
 * course, message, route)` inyeksiya qilinadi. {id, pushed} qaytaradi.
 */
export async function publishNotice(domain, notice, author, { db, now, notifyClass }) {
  const ref = db.collection('school_notices').doc();
  const at = now();
  await ref.set({
    domain,
    ...notice,
    createdBy: author.uid,
    createdByName: author.name ?? '',
    createdAt: at,
  });
  await logNotice(db, domain, ref.id, 'create', author.uid, at, notice);
  const pushed = await notifyClass(notice.grade, notice.course, noticePush(notice), '/home');
  return { id: ref.id, pushed };
}

/** Only the author or a school admin deletes; also drops its 既読 receipts. */
// UZ: Faqat muallif yoki maktab admini o'chiradi; uning 既読 kvitansiyalarini ham olib tashlaydi.
/// The notice [id] of [domain], if [uid] wrote it or is an admin.
///
/// UZ: Agar [uid] uni yozgan bo'lsa yoki admin bo'lsa, [domain] ning [id] bildirishnomasi.
async function ownNotice(db, domain, id, uid, isAdmin) {
  if (typeof id !== 'string' || !/^[A-Za-z0-9]{1,40}$/.test(id)) bad('A valid notice id is required.');
  const ref = db.collection('school_notices').doc(id);
  const snap = await ref.get();
  if (!snap.exists || snap.data().domain !== domain) {
    throw new HttpsError('not-found', 'Notice not found.');
  }
  if (snap.data().createdBy !== uid && !isAdmin) {
    throw new HttpsError('permission-denied', 'Only the author or an admin can change this notice.');
  }
  return { ref, data: snap.data() };
}

/// 訂正: the author corrects the text of a sent notice. The addressed class
/// stays fixed (a different class would need a new push) and no push is
/// re-sent; students see a 訂正 stamp from `editedAt`.
///
/// UZ: 訂正: muallif yuborilgan bildirishnoma matnini tuzatadi. Qaratilgan sinf
/// o'zgarmay qoladi (boshqa sinfga yangi push kerak bo'lardi) va qayta push
/// yuborilmaydi; talabalar `editedAt` orqali 訂正 belgisini ko'rishadi.
export async function updateNotice(domain, id, notice, uid, isAdmin, { db, now }) {
  const { ref, data } = await ownNotice(db, domain, id, uid, isAdmin);
  if (notice.grade !== data.grade || (notice.course ?? null) !== (data.course ?? null)) {
    bad('The addressed class cannot be changed.');
  }
  const at = now();
  const { title, body, priority, category, subject, link } = notice;
  await ref.set({ title, body, priority, category, subject, link, editedAt: at }, { merge: true });
  await logNotice(db, domain, id, 'edit', uid, at, notice);
  return { ok: true };
}

export async function deleteNotice(domain, id, uid, isAdmin, { db, removeReads, now = () => new Date() }) {
  const { ref } = await ownNotice(db, domain, id, uid, isAdmin);
  await ref.delete();
  await logNotice(db, domain, id, 'delete', uid, now());
  await removeReads?.(noticeReadTarget(id));
  return { ok: true };
}
