import { HttpsError } from 'firebase-functions/https';
import { xlsxToRows, parseTimetableRows, dayDocId } from './timetable_xlsx.js';
import { slotsHash, diffDays, describeChange, buildClassMessage } from './diff.js';
import { reconcileOverrides } from './overrides.js';
import { groupByLang, pt, recipientOf } from './push_i18n.js';

const BATCH_MAX = 450;
const FEED_MAX = 30;
const MULTICAST_MAX = 500;
const CHANNEL_ID = 'eduplanner_reminders';

export const domainOf = (email) => String(email ?? '').split('@')[1]?.toLowerCase() ?? '';

// Japan has no DST, so a fixed +9h offset is exact. (An Intl 'sv-SE' format
// silently falls back to en-US on small-ICU Node builds, e.g. the emulator.)
const TOKYO_OFFSET_MS = 9 * 60 * 60 * 1000;
export const tokyoToday = (date) =>
  new Date(date.getTime() + TOKYO_OFFSET_MS).toISOString().slice(0, 10);

const mondayOf = (iso) => {
  const d = new Date(`${iso}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() - ((d.getUTCDay() + 6) % 7));
  return d.toISOString().slice(0, 10);
};

/** Pure link gate; returns the school domain or throws permission-denied. */
export function assertLinkAllowed({ callerEmail, callerVerified, tokenEmail, hd, school, uid, firstAdmins = [] }) {
  const deny = (m) => { throw new HttpsError('permission-denied', m); };
  const domain = domainOf(callerEmail);
  if (callerVerified !== true || !domain) deny('Verified email required.');
  if (String(tokenEmail ?? '').toLowerCase() !== String(callerEmail).toLowerCase()) {
    deny('Google account does not match the signed-in account.');
  }
  if (String(hd ?? '').toLowerCase() !== domain) deny('Not a Google Workspace account of this domain.');
  // A school with no admin yet may be claimed only by an email the operator
  // listed (SCHOOL_FIRST_ADMIN_EMAILS): students of the domain hold
  // Workspace accounts too and would otherwise win by linking first.
  const admins = school?.admins ?? [];
  if (admins.length ? !admins.includes(uid) : !firstAdmins.includes(String(callerEmail).toLowerCase())) {
    deny('Not a school admin.');
  }
  return domain;
}

/**
 * Sends one push per recipient language. [message] is a {title, body} object
 * or `(lang) => {title, body}`; `route` tells the app which screen to open.
 */
export async function sendAll(sendMulticast, recipients, message, route = '/timetable') {
  const build = typeof message === 'function' ? message : () => message;
  for (const { lang, tokens } of groupByLang(recipients)) {
    const notification = build(lang);
    for (let i = 0; i < tokens.length; i += MULTICAST_MAX) {
      await sendMulticast({
        tokens: tokens.slice(i, i + MULTICAST_MAX),
        notification,
        data: { route },
        android: { notification: { channelId: CHANNEL_ID } },
      });
    }
  }
}

/**
 * Pushes [message] to one class's students, or to the whole grade when
 * [course] is null. Returns the token count.
 */
export async function notifyClass(domain, grade, course, message, { db, sendMulticast }, route) {
  let query = db.collection('users')
    .where('schoolDomain', '==', domain)
    .where('grade', '==', String(grade));
  if (course != null) query = query.where('course', '==', course);
  const snap = await query.get();
  const recipients = snap.docs.map((d) => recipientOf(d.data())).filter((r) => r.token);
  if (!recipients.length) return 0;
  await sendAll(sendMulticast, recipients, message, route);
  return recipients.length;
}

/** Pushes one class's change summary to its students. Returns the token count. */
export const notifySchoolChanges = (domain, grade, course, changes, periods, deps) =>
  notifyClass(domain, grade, course, (lang) => buildClassMessage(grade, course, changes, periods, lang), deps);

async function pushToFirstAdmin(school, message, { db, sendMulticast }) {
  const adminUid = school.admins?.[0];
  if (!adminUid) return;
  const recipient = recipientOf((await db.collection('users').doc(adminUid).get()).data());
  if (recipient.token) await sendAll(sendMulticast, [recipient], message, '/home');
}

async function recordError(schoolRef, school, err, deps) {
  const message = String(err?.message ?? err).slice(0, 300);
  await schoolRef.set({ sync: { status: 'error', error: message, lastRunAt: deps.now() } }, { merge: true });
  if (school.sync?.status !== 'error') {
    // A failed admin push must not mask the sync error itself.
    await pushToFirstAdmin(school, (lang) => ({ title: pt(lang, 'push_sync_failed'), body: message }), deps)
      .catch(() => {});
  }
  return { status: 'error', error: message, weeks: 0, classes: 0, changes: 0, periods: 0 };
}

export async function syncSchool(domain, { force = false, notify = false }, deps) {
  const { db, google, now } = deps;
  const schoolRef = db.collection('schools').doc(domain);
  const [secretSnap, schoolSnap] = await Promise.all([
    db.collection('school_secrets').doc(domain).get(),
    schoolRef.get(),
  ]);
  const school = schoolSnap.data() ?? {};

  let meta;
  let parsed;
  try {
    const accessToken = await google.refreshAccessToken(secretSnap.data().refreshToken);
    meta = await google.getFileMeta(accessToken, school.file.id);
    if (!force && meta.modifiedTime === school.file.modifiedTime) {
      await schoolRef.set({ sync: { lastRunAt: now() } }, { merge: true });
      return { status: 'skipped', weeks: 0, classes: 0, changes: 0, periods: 0 };
    }
    const buffer = await google.downloadXlsx(accessToken, meta);
    parsed = parseTimetableRows(await xlsxToRows(buffer), { fileName: meta.name });
  } catch (err) {
    return recordError(schoolRef, school, err, deps);
  }

  const todayIso = tokyoToday(now());
  const byClass = new Map();
  for (const day of parsed.days) {
    const key = `${day.grade}|${day.course}`;
    if (!byClass.has(key)) byClass.set(key, []);
    byClass.get(key).push(day);
  }

  const writes = [];
  let changed = []; // { grade, course, changes }
  for (const days of byClass.values()) {
    const refs = days.map((d) => db.collection('school_days').doc(dayDocId(domain, d)));
    const snaps = await db.getAll(...refs);
    const prev = new Map();
    days.forEach((day, i) => {
      const old = snaps[i].exists ? snaps[i].data() : null;
      const hash = slotsHash(day.slots);
      if (old) prev.set(day.date, old.slots);
      if (old?.hash !== hash) {
        writes.push([refs[i], {
          domain, grade: day.grade, course: day.course, date: day.date,
          slots: day.slots, hash, updatedAt: now(),
        }]);
      }
    });
    // Dates with no previous doc are new weeks/classes, not changes.
    const changes = diffDays(prev, days.filter((d) => prev.has(d.date)), todayIso);
    if (changes.length) changed.push({ grade: days[0].grade, course: days[0].course, changes });
  }

  const daysById = new Map(parsed.days.map((d) => [dayDocId(domain, d), d]));
  changed = await reconcileOverrides(domain, daysById, changed, deps);

  for (let i = 0; i < writes.length; i += BATCH_MAX) {
    const batch = db.batch();
    writes.slice(i, i + BATCH_MAX).forEach(([ref, data]) => batch.set(ref, data));
    await batch.commit();
  }

  // The first link run has no meaningful "before", so it records no feed.
  if (!(force && !notify)) {
    for (const { grade, course, changes } of changed) {
      const ref = db.collection('school_changes').doc(`${domain}_${grade}_${course}`);
      const old = (await ref.get()).data()?.items ?? [];
      const fresh = changes.map((c) => ({ ...describeChange(c), at: now() }));
      await ref.set({ items: [...fresh, ...old].slice(0, FEED_MAX) });
    }
  }

  await schoolRef.set({
    periods: parsed.periods,
    grades: parsed.grades,
    courses: parsed.courses,
    file: { name: meta.name, modifiedTime: meta.modifiedTime },
    sync: { status: 'ok', error: null, lastRunAt: now() },
  }, { merge: true });

  if (notify) {
    for (const { grade, course, changes } of changed) {
      await notifySchoolChanges(domain, grade, course, changes, parsed.periods, deps);
    }
  }

  return {
    status: 'ok',
    weeks: new Set(parsed.days.map((d) => mondayOf(d.date))).size,
    classes: byClass.size,
    changes: changed.reduce((n, c) => n + c.changes.length, 0),
    periods: parsed.periods.length,
  };
}

/** Scheduled entry: every school with a linked file, one failure never stops the rest. */
export async function syncAllSchools(deps, run = (domain) => syncSchool(domain, { force: false, notify: true }, deps)) {
  const snap = await deps.db.collection('schools').get();
  for (const doc of snap.docs) {
    if (!doc.data().file?.id) continue;
    try {
      await run(doc.id);
    } catch {
      // syncSchool records its own errors; anything else is skipped so the next school still runs.
    }
  }
}
