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

/**
 * Resolves the school domain for an authenticated caller, matching the
 * exact semantics of `inDomain(d)` / `isTester(d)` in `firestore.rules`:
 * 1. If `auth.token.email_verified !== true`, returns `null`.
 * 2. Checks `school_testers/{lowercaseEmail}` first (pilot test account let in
 *    by a school admin via `setSchoolTester`).
 * 3. Otherwise checks if `schools/{emailDomain}` exists; if so, returns
 *    `emailDomain`, else `null` (an unlinked personal account like `@gmail.com`
 *    is not an error).
 */
export async function resolveSchoolDomain(auth, { db } = {}) {
  const token = auth?.token;
  if (!token || token.email_verified !== true) return null;
  const email = String(token.email ?? '').trim().toLowerCase();
  if (!email) return null;

  if (db) {
    const testerSnap = await db.collection('school_testers').doc(email).get();
    const testerDomain = testerSnap.exists ? testerSnap.data()?.domain : null;
    if (typeof testerDomain === 'string' && testerDomain.trim().length > 0) {
      return testerDomain.trim().toLowerCase();
    }
  }

  const emailDomain = domainOf(email);
  if (!emailDomain) return null;

  if (db) {
    const schoolSnap = await db.collection('schools').doc(emailDomain).get();
    if (!schoolSnap.exists) return null;
  }
  return emailDomain;
}

// Japan has no DST, so a fixed +9h offset is exact. (An Intl 'sv-SE' format
// silently falls back to en-US on small-ICU Node builds, e.g. the emulator.)
// UZ: Yaponiyada DST yo'q, shuning uchun qat'iy +9h siljish aniq hisoblanadi. (Intl 'sv-SE' formati
// kichik ICU'li Node build'larida, masalan emulyatorda, jimgina en-US ga qaytadi.)
const TOKYO_OFFSET_MS = 9 * 60 * 60 * 1000;
export const tokyoToday = (date) =>
  new Date(date.getTime() + TOKYO_OFFSET_MS).toISOString().slice(0, 10);

const mondayOf = (iso) => {
  const d = new Date(`${iso}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() - ((d.getUTCDay() + 6) % 7));
  return d.toISOString().slice(0, 10);
};

/** Pure link gate; returns the school domain or throws permission-denied. */
// UZ: Sof havola darvozasi (gate); maktab domenini qaytaradi yoki permission-denied xatosini tashlaydi.
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
  // UZ: Hali admini bo'lmagan maktabga faqat operator ro'yxatga kiritgan elektron pochta
  // (SCHOOL_FIRST_ADMIN_EMAILS) da'vogarlik qilishi mumkin: domen talabalari ham Workspace
  // hisoblariga ega va aks holda birinchi bo'lib bog'lash orqali yutib chiqishlari mumkin.
  const admins = school?.admins ?? [];
  if (admins.length ? !admins.includes(uid) : !firstAdmins.includes(String(callerEmail).toLowerCase())) {
    deny('Not a school admin.');
  }
  return domain;
}

/**
 * Sends one push per recipient language. [message] is a {title, body} object
 * or `(lang) => {title, body}`; `route` tells the app which screen to open.
 * UZ: Qabul qiluvchi tili bo'yicha bitta push yuboradi. [message] bu {title, body} obyekti
 * yoki `(lang) => {title, body}`; `route` ilovaga qaysi ekranni ochishni aytadi.
 */
/// Account deletion: drop [uid] from every school's admins, and where the
/// school's Drive link is this user's, remove their refresh token and the
/// file link so the server stops reading their Drive.
///
/// UZ: Hisobni o'chirish: har bir maktabning adminlaridan [uid] ni olib tashlang, va maktabning
/// Drive havolasi ushbu foydalanuvchiniki bo'lgan joyda, server ularning Drive'ini o'qishni to'xtatishi
/// uchun ularning yangilash tokeni va fayl havolasini olib tashlang.
// ponytail: scans all schools; query by admins array-contains if there are ever many.
// UZ: ponytail: barcha maktablarni ko'rib chiqadi (scan); agar ko'p bo'lsa, admins array-contains orqali so'rov yuboring.
export async function releaseSchoolAdmin(db, uid, deleteField) {
  const schools = (await db.collection('schools').get()).docs
    .filter((d) => (d.data().admins ?? []).includes(uid));
  for (const doc of schools) {
    const secretRef = db.collection('school_secrets').doc(doc.id);
    const mine = (await secretRef.get()).data()?.linkedBy === uid;
    if (mine) await secretRef.delete();
    await doc.ref.set({
      admins: doc.data().admins.filter((a) => a !== uid),
      ...(mine ? {file: deleteField} : {}),
    }, {merge: true});
  }
  return schools.length;
}

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
 * UZ: [message] ni bitta sinf talabalariga yoki [course] null bo'lganda butun kursga push qiladi.
 * Tokenlar sonini qaytaradi.
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
// UZ: Bitta sinfning o'zgarishlar xulosasini uning talabalariga push qiladi. Tokenlar sonini qaytaradi.
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
    // UZ: Muvaffaqiyatsiz admin push'i sinxronlash xatosining o'zini yashirmasligi kerak.
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
    // UZ: Oldingi hujjati bo'lmagan sanalar o'zgarishlar emas, yangi haftalar/sinflardir.
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
  // UZ: Birinchi bog'lash ishga tushirilishida mazmunli "before" bo'lmaydi, shuning uchun u hech qanday feed yozmaydi.
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
// UZ: Rejalashtirilgan kirish: bog'langan fayli bor har bir maktab, bitta nosozlik hech qachon qolganlarini to'xtatmaydi.
export async function syncAllSchools(deps, run = (domain) => syncSchool(domain, { force: false, notify: true }, deps)) {
  const snap = await deps.db.collection('schools').get();
  for (const doc of snap.docs) {
    if (!doc.data().file?.id) continue;
    try {
      await run(doc.id);
    } catch {
      // syncSchool records its own errors; anything else is skipped so the next school still runs.
      // UZ: syncSchool o'z xatolarini yozadi; keyingi maktab baribir ishlashi uchun boshqa har qanday narsa o'tkazib yuboriladi.
    }
  }
}
