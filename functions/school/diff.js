import { createHash } from 'node:crypto';
import { formatPushDate, pt } from './push_i18n.js';

const FIELDS = ['subject', 'teacher', 'room', 'note', 'status'];

const byPeriod = (a, b) =>
  parseInt(a.period, 10) - parseInt(b.period, 10) ||
  (a.period < b.period ? -1 : a.period > b.period ? 1 : 0);

export const slotsHash = (slots) =>
  createHash('sha1')
    .update(JSON.stringify([...slots].sort(byPeriod)))
    .digest('hex');

const differs = (a, b, fields = FIELDS) =>
  fields.some((f) => (a[f] ?? '') !== (b[f] ?? ''));

// prev: Map<date, Slot[]>; next: Day[] of one class. Dates before todayIso are skipped.
// UZ: prev: Map<date, Slot[]>; next: bitta sinfning Day[] ro'yxati. todayIso dan oldingi sanalar o'tkazib yuboriladi.
export function diffDays(prev, next, todayIso) {
  const nextByDate = new Map(next.map((d) => [d.date, d.slots]));
  const dates = new Set([...prev.keys(), ...nextByDate.keys()]);
  const changes = [];
  for (const date of [...dates].sort()) {
    if (date < todayIso) continue;
    const before = new Map((prev.get(date) ?? []).map((s) => [s.period, s]));
    const after = new Map((nextByDate.get(date) ?? []).map((s) => [s.period, s]));
    for (const period of new Set([...before.keys(), ...after.keys()])) {
      const b = before.get(period) ?? null;
      const a = after.get(period) ?? null;
      if (!a || !b || differs(a, b)) {
        changes.push({ date, period, before: b, after: a });
      }
    }
  }
  return changes.sort((x, y) => x.date.localeCompare(y.date) || byPeriod(x, y));
}

const changeKind = ({ before, after }) => {
  if (after?.status === 'cancelled') return 'cancelled';
  if (before && after && !differs(before, after, FIELDS.filter((f) => f !== 'room'))) return 'room';
  if (!after) return 'removed';
  if (!before) return 'added';
  return 'changed';
};

/** One change in [lang]; the in-app feed stores the Japanese form. */
// UZ: [lang] tilidagi bitta o'zgarish; ilova ichidagi lenta yaponcha shaklini saqlaydi.
const whatOf = (change, lang) => {
  const kind = changeKind(change);
  return kind === 'room'
    ? pt(lang, 'push_room_short', { from: change.before.room, to: change.after.room })
    : pt(lang, `push_kind_${kind}`);
};

export function describeChange(change) {
  const { date, period, before, after } = change;
  return {
    date,
    period,
    subject: after?.subject || before?.subject,
    what: whatOf(change, 'ja'),
  };
}

export function buildClassMessage(grade, course, changes, periods, lang = 'ja') {
  const sorted = [...changes].sort(
    (x, y) => x.date.localeCompare(y.date) || byPeriod(x, y),
  );
  const first = sorted[0];
  const label = periods.find((p) => p.key === first.period)?.label ?? first.period;
  const more = sorted.length > 1 ? pt(lang, 'push_more', { n: sorted.length - 1 }) : '';
  return {
    title: pt(lang, 'push_tt_title_sync'),
    body: pt(lang, 'push_sync_body', {
      grade,
      course,
      when: `${formatPushDate(first.date, lang)}${label}`,
      subject: first.after?.subject || first.before?.subject,
      what: whatOf(first, lang),
      more,
    }),
  };
}
