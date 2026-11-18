import { resolveSchoolDomain, tokyoToday } from '../school/sync.js';
import { normalizeSchoolPolicy } from '../school/policy.js';
import { dayDocId } from '../school/timetable_xlsx.js';
import { deriveNameParts } from './anonymizer_service.js';

const SPLIT_TEACHER_RE = /[・,、，／/]/;
const HONORIFIC_SUFFIX_RE = /(?:先生|さん|くん|君|ちゃん|様)$/;

function cleanTeacherTokens(raw) {
  const str = String(raw ?? '').trim();
  if (!str) return [];
  const results = [];
  for (const chunk of str.split(SPLIT_TEACHER_RE)) {
    // Strip trailing room annotations like `鈴木【205】` or `鈴木(205)`
    const withoutRoom = chunk
      .replace(/【[^】]*】/g, '')
      .replace(/\([^)]*\)/g, '')
      .replace(/（[^）]*）/g, '')
      .trim();
    const stem = withoutRoom.replace(HONORIFIC_SUFFIX_RE, '').trim();
    if (stem.length >= 2) {
      results.push(stem);
    }
  }
  return results;
}

const parseGradeNum = (raw) => {
  const m = String(raw ?? '').match(/[0-9０-９]+/);
  if (!m) return null;
  const ascii = [...m[0]]
    .map((ch) => {
      const code = ch.charCodeAt(0);
      return code >= 0xff10 && code <= 0xff19
        ? String.fromCharCode(code - 0xfee0)
        : ch;
    })
    .join('');
  const n = Number.parseInt(ascii, 10);
  return Number.isFinite(n) ? n : null;
};

const mondayWeekDays = (todayIso) => {
  const d = new Date(`${todayIso}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() - ((d.getUTCDay() + 6) % 7));
  const dates = [];
  for (let i = 0; i < 5; i++) {
    const cur = new Date(d.getTime());
    cur.setUTCDate(d.getUTCDate() + i);
    dates.push(cur.toISOString().slice(0, 10));
  }
  return dates;
};

/**
 * Loads the caller-scoped list of known people (`PersonName` objects) from
 * Firestore for server-side privacy masking.
 *
 * Security invariants:
 * - Admin SDK bypasses `firestore.rules`, so this function strictly scopes all
 *   reads to the caller's own `uid` and their verified school `domain` (resolved
 *   via `resolveSchoolDomain`). It NEVER reads documents from other schools.
 * - Unlinked users (`domain === null`) are NOT an error: their roster consists
 *   of their own name (`users/{uid}.name`) plus teacher names in their own
 *   `timetables` entries.
 * - Any Firestore read failure or timeout rejects so `callGeminiSafely` can
 *   enforce fail-closed behavior.
 */
export async function loadPeopleForCaller(
  auth,
  { db, now = () => new Date(), cache, domainCache, policyCache } = {},
) {
  const uid = auth?.uid;
  if (!uid) {
    throw new Error('Caller uid is required to load privacy roster.');
  }
  if (!db) {
    throw new Error('Firestore instance is required to load privacy roster.');
  }

  if (cache && cache.has(uid)) {
    return cache.get(uid);
  }

  const peopleByKey = new Map();
  let seq = 0;

  const addPerson = (fullName, role, idHint) => {
    const trimmed = String(fullName ?? '').trim();
    if (!trimmed) return;
    const key = `${role}:${trimmed.toLowerCase()}`;
    if (peopleByKey.has(key)) return;
    seq += 1;
    peopleByKey.set(key, {
      id: idHint || `${role}_${seq}`,
      fullName: trimmed,
      role,
      parts: deriveNameParts(trimmed),
    });
  };

  // 1. Read caller's own profile (`users/{uid}`), personal timetable entries,
  //    and resolve their verified school domain in parallel.
  const [userSnap, timetableSnap, domain] = await Promise.all([
    db.collection('users').doc(uid).get(),
    db.collection('timetables').where('userId', '==', uid).limit(100).get(),
    domainCache && domainCache.has(uid)
      ? Promise.resolve(domainCache.get(uid))
      : resolveSchoolDomain(auth, { db }),
  ]);
  if (domainCache && !domainCache.has(uid)) {
    domainCache.set(uid, domain);
  }

  const userData = userSnap.exists ? (userSnap.data() ?? {}) : {};
  if (typeof userData.name === 'string' && userData.name.trim()) {
    addPerson(userData.name, 'student', `user_${uid}`);
  }

  if (timetableSnap && Array.isArray(timetableSnap.docs)) {
    for (const doc of timetableSnap.docs) {
      const data = doc.data() ?? {};
      for (const tName of cleanTeacherTokens(data.teacher)) {
        addPerson(tName, 'teacher', `tt_${doc.id}_${tName}`);
      }
    }
  }

  // 2. If the caller belongs to a verified school domain, load teacher names
  //    from `schools/{domain}.teacherProfiles` and the caller's current week
  //    `school_days` + `school_overrides` for that same domain ONLY.
  if (domain) {
    const schoolSnap = await db.collection('schools').doc(domain).get();
    if (schoolSnap.exists) {
      const schoolData = schoolSnap.data() ?? {};
      if (policyCache && !policyCache.has(domain)) {
        policyCache.set(
          domain,
          normalizeSchoolPolicy(schoolData.policy ?? null, { domain }),
        );
      }
      const profiles = schoolData.teacherProfiles;
      if (profiles && typeof profiles === 'object') {
        for (const [email, profile] of Object.entries(profiles)) {
          const name = profile?.name;
          for (const tName of cleanTeacherTokens(name)) {
            addPerson(tName, 'teacher', `school_${domain}_${email}`);
          }
        }
      }

      const grade = parseGradeNum(userData.grade);
      const course = typeof userData.course === 'string' ? userData.course.trim() : '';
      if (grade !== null && course && (schoolData.courses ?? []).includes(course)) {
        const weekDates = mondayWeekDays(tokyoToday(now()));
        const dayRefs = weekDates.map((date) =>
          db.collection('school_days').doc(dayDocId(domain, { grade, course, date })),
        );
        const overrideRefs = weekDates.map((date) =>
          db.collection('school_overrides').doc(dayDocId(domain, { grade, course, date })),
        );
        const allRefs = [...dayRefs, ...overrideRefs];
        if (allRefs.length > 0 && typeof db.getAll === 'function') {
          const snaps = await db.getAll(...allRefs);
          for (const snap of snaps) {
            if (!snap.exists) continue;
            const d = snap.data() ?? {};
            if (Array.isArray(d.slots)) {
              for (const slot of d.slots) {
                for (const tName of cleanTeacherTokens(slot?.teacher)) {
                  addPerson(tName, 'teacher');
                }
              }
            }
            if (d.items && typeof d.items === 'object') {
              for (const ov of Object.values(d.items)) {
                for (const tName of cleanTeacherTokens(ov?.teacher)) {
                  addPerson(tName, 'teacher');
                }
              }
            }
          }
        }
      }
    }
  }

  const result = [...peopleByKey.values()];
  if (cache) {
    cache.set(uid, result);
  }
  return result;
}
