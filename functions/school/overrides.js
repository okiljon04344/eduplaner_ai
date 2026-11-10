import { HttpsError } from 'firebase-functions/https';
import { dayDocId } from './timetable_xlsx.js';
import { formatPushDate, pt } from './push_i18n.js';

// Teacher input (第2段階 §9): instant lesson changes that win over the synced
// school file until the file catches up. One doc per class-day, keyed like
// school_days, so the app can `get` it by id (rules allow no list queries).
export const OVERRIDE_KINDS = ['cancelled', 'room', 'makeup', 'memo'];
const FEED_MAX = 30;
const MAX_TEXT = 100;
const MAX_NOTE = 200;
const ISO_RE = /^\d{4}-\d{2}-\d{2}$/;
const EMAIL_RE = /^[^\s@]+@[^\s@]+$/;

const bad = (m) => { throw new HttpsError('invalid-argument', m); };
const text = (v, max, name) => {
  if (v === undefined || v === null) return '';
  if (typeof v !== 'string' || v.length > max) bad(`${name} must be a string of at most ${max} chars.`);
  return v.trim();
};

export const isTeacher = (school, uid, email) =>
  (school?.admins ?? []).includes(uid) ||
  (school?.teachers ?? []).includes(String(email ?? '').toLowerCase());

/** Lowercased email of any domain (test accounts), or invalid-argument. */
export function normalizeEmail(email) {
  const e = String(email ?? '').trim().toLowerCase();
  if (e.length > 200 || !EMAIL_RE.test(e)) bad('A valid email is required.');
  return e;
}

/** Lowercased teacher email of [domain], or invalid-argument. */
export function normalizeTeacherEmail(email, domain) {
  const e = String(email ?? '').trim().toLowerCase();
  if (e.length > 200 || !EMAIL_RE.test(e) || e.split('@').pop() !== domain) {
    bad('A school email of this domain is required.');
  }
  return e;
}

/**
 * Validates a publish request against the school's synced grades/courses/periods.
 * kind 'clear' removes the teacher input for that slot.
 */
export function validateOverride(input, school, todayIso) {
  const d = input ?? {};
  const grade = Number(d.grade);
  if (!(school.grades ?? []).includes(grade)) bad('Unknown grade.');
  if (!(school.courses ?? []).includes(d.course)) bad('Unknown course.');
  if (typeof d.date !== 'string' || !ISO_RE.test(d.date) || d.date < todayIso) {
    bad('date must be today or later (YYYY-MM-DD).');
  }
  if (!(school.periods ?? []).some((p) => p.key === d.period)) bad('Unknown period.');
  if (d.kind !== 'clear' && !OVERRIDE_KINDS.includes(d.kind)) bad('Unknown kind.');
  const ov = {
    grade,
    course: d.course,
    date: d.date,
    period: d.period,
    kind: d.kind,
    subject: text(d.subject, MAX_TEXT, 'subject'),
    teacher: text(d.teacher, MAX_TEXT, 'teacher'),
    room: text(d.room, MAX_TEXT, 'room'),
    note: text(d.note, MAX_NOTE, 'note'),
  };
  if (ov.kind === 'room' && !ov.room) bad('room is required.');
  if (ov.kind === 'makeup' && !ov.subject) bad('subject is required.');
  if (ov.kind === 'memo' && !ov.note) bad('note is required.');
  return ov;
}

/** Validated teacherProfiles entry: timetable name + optional homeroom class. */
export function teacherProfileOf(input, school) {
  const d = input ?? {};
  const name = text(d.name, 50, 'name');
  const h = d.homeroom;
  if (h === undefined || h === null) return { name, homeroom: null };
  const grade = Number(h.grade);
  if (!(school.grades ?? []).includes(grade) || !(school.courses ?? []).includes(h.course)) {
    bad('Unknown homeroom class.');
  }
  return { name, homeroom: { grade, course: h.course } };
}

/**
 * Edit scope (§9.3): an admin, the class's homeroom teacher (担任), or the
 * teacher named in the lesson cell. An empty slot (補講) is open to anyone who
 * teaches that class on that day. Names come from schools.teacherProfiles.
 */
export function canEditSlot(school, uid, email, ov, base, daySlots = []) {
  if ((school?.admins ?? []).includes(uid)) return true;
  const p = school?.teacherProfiles?.[String(email ?? '').toLowerCase()];
  if (!p) return false;
  if (p.homeroom && Number(p.homeroom.grade) === ov.grade && p.homeroom.course === ov.course) return true;
  const name = String(p.name ?? '').trim();
  if (!name) return false;
  if (base) return String(base.teacher ?? '').includes(name);
  return daySlots.some((s) => String(s.teacher ?? '').includes(name));
}

/** True when the school file's [slot] already shows what the teacher entered. */
export function matchesOverride(item, slot) {
  if (!slot) return false;
  switch (item.kind) {
    case 'cancelled': return slot.status === 'cancelled';
    case 'room': return slot.room === item.room;
    case 'makeup': return slot.subject === item.subject;
    case 'memo': return slot.note === item.note;
    default: return false;
  }
}

/**
 * Feed `what` (Japanese) and push builder `(lang) => {title, body}` for one
 * teacher input; memo sends no push (`push` is null).
 */
export function describeOverride(ov, base, periods) {
  const label = periods.find((p) => p.key === ov.period)?.label ?? ov.period;
  const subject = ov.kind === 'makeup' ? ov.subject : (base?.subject || ov.subject);
  const from = base?.room || '—';
  const what = {
    cancelled: '休講',
    room: `教室 ${from}→${ov.room}`,
    makeup: '補講',
    memo: 'メモ',
  }[ov.kind];
  const push = ov.kind === 'memo' ? null : (lang) => ({
    title: pt(lang, 'push_tt_title'),
    body: pt(lang, 'push_override_body', {
      kind: pt(lang, `push_kind_${ov.kind}`),
      when: `${formatPushDate(ov.date, lang)}${label}`,
      subject,
      detail: ov.kind === 'room' ? pt(lang, 'push_room_detail', { from, to: ov.room }) : '',
      note: ov.note ? pt(lang, 'push_note', { note: ov.note }) : '',
    }),
  });
  return { what, subject, push };
}

/**
 * Saves (or clears) one teacher input, adds it to the class's change feed and
 * pushes it to the class. `notifyClass(grade, course, notification)` is injected.
 */
export async function publishOverride(domain, ov, uid, { db, now, notifyClass, canEdit, resetReads }) {
  const id = dayDocId(domain, ov);
  const ref = db.collection('school_overrides').doc(id);
  // ponytail: read-modify-write, not a transaction; two teachers editing the
  // same class-day within the same second could drop one slot. Use a
  // transaction if that ever happens in practice.
  const [ovSnap, daySnap, schoolSnap] = await Promise.all([
    ref.get(),
    db.collection('school_days').doc(id).get(),
    db.collection('schools').doc(domain).get(),
  ]);
  const daySlots = daySnap.exists ? daySnap.data().slots : [];
  const base = daySlots.find((s) => s.period === ov.period) ?? null;
  if (canEdit && !canEdit(base, daySlots)) {
    throw new HttpsError('permission-denied', 'Only this lesson\'s teacher or the homeroom teacher can change it.');
  }
  const items = { ...(ovSnap.exists ? ovSnap.data().items : {}) };
  if (ov.kind === 'clear') {
    delete items[ov.period];
    await ref.set({ domain, grade: ov.grade, course: ov.course, date: ov.date, items });
    return { pushed: 0 };
  }

  const periods = schoolSnap.data()?.periods ?? [];
  const { what, subject, push } = describeOverride(ov, base, periods);
  items[ov.period] = {
    kind: ov.kind,
    subject: ov.subject,
    teacher: ov.teacher,
    room: ov.room,
    note: ov.note,
    createdBy: uid,
    createdAt: now(),
    resolved: false,
  };
  await ref.set({ domain, grade: ov.grade, course: ov.course, date: ov.date, items });

  const feedRef = db.collection('school_changes').doc(`${domain}_${ov.grade}_${ov.course}`);
  const old = (await feedRef.get()).data()?.items ?? [];
  await feedRef.set({
    items: [{ date: ov.date, period: ov.period, subject, what, at: now() }, ...old].slice(0, FEED_MAX),
  });

  // A new announcement starts its 既読 count from zero.
  await resetReads?.(ov);
  const pushed = push ? await notifyClass(ov.grade, ov.course, push) : 0;
  return { pushed };
}

/**
 * Sync-time reconciliation (§9.3): marks teacher inputs the file now matches
 * as resolved, and drops file changes a teacher already announced (§8) from
 * [changed] so students are not pushed twice. Mutates and returns [changed].
 */
export async function reconcileOverrides(domain, daysById, changed, { db, now }) {
  const snap = await db.collection('school_overrides').where('domain', '==', domain).get();
  const announced = new Set();
  for (const doc of snap.docs) {
    const data = doc.data();
    const day = daysById.get(doc.id);
    let dirty = false;
    const items = { ...data.items };
    for (const [period, item] of Object.entries(items)) {
      const slot = day?.slots.find((s) => s.period === period) ?? null;
      if (!matchesOverride(item, slot)) continue;
      announced.add(`${data.grade}|${data.course}|${data.date}|${period}`);
      if (!item.resolved) {
        items[period] = { ...item, resolved: true, resolvedAt: now() };
        dirty = true;
      }
    }
    if (dirty) await doc.ref.set({ ...data, items });
  }
  for (const c of changed) {
    c.changes = c.changes.filter((ch) => !announced.has(`${c.grade}|${c.course}|${ch.date}|${ch.period}`));
  }
  return changed.filter((c) => c.changes.length);
}

// 既読 receipts: Firestore `school_reads/{domain}_{target}_{uid}`. `target`
// names what was read; the client builds the same string (school_repository).
// A doc id cannot hold '/', so it becomes ','.
const readKey = (s) => String(s).replaceAll('/', ',');

/** Target of one announced lesson change. */
export const readTarget = (grade, course, date, period) =>
  readKey(`o_${grade}_${course}_${date}_${period}`);

/** Target of one notice. */
export const noticeReadTarget = (id) => readKey(`n_${id}`);
