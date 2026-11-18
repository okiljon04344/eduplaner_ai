// Japanese national holiday (国民の祝日) calculator based on 国民の祝日に関する法律.
// Source reference: 内閣府 国民の祝日について
//   https://www8.cao.go.jp/chosei/shukujitsu/syukujitsu.csv

/**
 * Manual holiday override map for future statutory amendments or official
 * 官報 updates that deviate from the astronomical equinox formula.
 * - `add`: `{ 'YYYY-MM-DD': '祝日名' }`
 * - `remove`: `Set<'YYYY-MM-DD'>`
 */
export const NATIONAL_HOLIDAY_OVERRIDES = Object.freeze({
  add: Object.freeze({}),
  remove: Object.freeze(new Set()),
});

/**
 * Last year whose 春分の日/秋分の日 have been officially announced in the 官報
 * (published every February for the FOLLOWING year; the 内閣府
 * syukujitsu.csv currently covers through 2027). Equinox dates (and any
 * 振替休日/国民の休日 derived from them) for later years are computed by
 * formula and flagged `provisional: true`. Bump this after each February
 * announcement (and add an override if the official date differs).
 */
export const OFFICIAL_HOLIDAYS_PUBLISHED_THROUGH = 2027;

const pad2 = (n) => String(n).padStart(2, '0');
const isoOf = (year, month, day) => `${year}-${pad2(month)}-${pad2(day)}`;

function nthWeekdayOfMonth(year, month, weekday, nth) {
  const firstDow = new Date(Date.UTC(year, month - 1, 1)).getUTCDay();
  const offset = (weekday - firstDow + 7) % 7;
  return 1 + offset + (nth - 1) * 7;
}

function parseIsoUtc(iso) {
  const [y, m, d] = iso.split('-').map(Number);
  return new Date(Date.UTC(y, m - 1, d));
}

function addDaysIso(iso, deltaDays) {
  const dt = parseIsoUtc(iso);
  dt.setUTCDate(dt.getUTCDate() + deltaDays);
  return dt.toISOString().slice(0, 10);
}

// 春分の日・秋分の日は天文計算式による算出値（1980〜2099年対応）。
// 正式な祝日は毎年2月の官報で発表されるため、万一差異が生じた場合は
// NATIONAL_HOLIDAY_OVERRIDES で上書きする。
function vernalEquinoxDay(year) {
  if (year < 1980 || year > 2099) {
    throw new RangeError(`Equinox formula supports 1980-2099 (got ${year}).`);
  }
  return (
    Math.floor(20.8431 + 0.242194 * (year - 1980)) -
    Math.floor((year - 1980) / 4)
  );
}

function autumnalEquinoxDay(year) {
  if (year < 1980 || year > 2099) {
    throw new RangeError(`Equinox formula supports 1980-2099 (got ${year}).`);
  }
  return (
    Math.floor(23.2488 + 0.242194 * (year - 1980)) -
    Math.floor((year - 1980) / 4)
  );
}

function baseNationalHolidaysForYear(year) {
  const holidays = new Map();
  const set = (m, d, name) => holidays.set(isoOf(year, m, d), name);

  // Fixed national holidays
  set(1, 1, '元日');
  set(2, 11, '建国記念の日');
  if (year >= 2020) {
    set(2, 23, '天皇誕生日');
  } else if (year >= 1989 && year <= 2018) {
    set(12, 23, '天皇誕生日');
  }
  set(3, vernalEquinoxDay(year), '春分の日');
  set(4, 29, year >= 2007 ? '昭和の日' : 'みどりの日');
  set(5, 3, '憲法記念日');
  if (year >= 2007) {
    set(5, 4, 'みどりの日');
  }
  set(5, 5, 'こどもの日');

  // 山の日 (8/11; Olympic date shifts in 2020 and 2021)
  if (year === 2020) {
    set(8, 10, '山の日');
  } else if (year === 2021) {
    set(8, 8, '山の日');
  } else if (year >= 2016) {
    set(8, 11, '山の日');
  }

  set(9, autumnalEquinoxDay(year), '秋分の日');
  set(11, 3, '文化の日');
  set(11, 23, '勤労感謝の日');

  // Happy Monday holidays
  set(1, nthWeekdayOfMonth(year, 1, 1, 2), '成人の日');
  if (year === 2020) {
    set(7, 23, '海の日');
    set(7, 24, 'スポーツの日');
  } else if (year === 2021) {
    set(7, 22, '海の日');
    set(7, 23, 'スポーツの日');
  } else {
    set(7, nthWeekdayOfMonth(year, 7, 1, 3), '海の日');
    set(10, nthWeekdayOfMonth(year, 10, 1, 2), 'スポーツの日');
  }
  set(9, nthWeekdayOfMonth(year, 9, 1, 3), '敬老の日');

  return holidays;
}

/**
 * Computes all Japanese national holidays (including 振替休日 and 国民の休日)
 * for [year], applying `NATIONAL_HOLIDAY_OVERRIDES` (plus optional custom
 * [overrides] for tests). Returns `{ holidays: Map<iso, name>, provisional: Set<iso> }`.
 */
function computeHolidays(year, overrides = NATIONAL_HOLIDAY_OVERRIDES) {
  const removeSet =
    overrides?.remove instanceof Set
      ? overrides.remove
      : new Set(Array.isArray(overrides?.remove) ? overrides.remove : []);
  const addMap = overrides?.add && typeof overrides.add === 'object' ? overrides.add : {};

  const base = baseNationalHolidaysForYear(year);
  for (const iso of removeSet) {
    base.delete(iso);
  }

  const provisional = new Set();
  if (year > OFFICIAL_HOLIDAYS_PUBLISHED_THROUGH) {
    for (const [iso, name] of base.entries()) {
      if (name === '春分の日' || name === '秋分の日') provisional.add(iso);
    }
  }

  const all = new Map(base);

  // 国民の休日 (祝日法第3条第3項): non-holiday weekday sandwiched directly
  // between two base national holidays (e.g. 2026-09-22 between 9/21 and 9/23).
  for (const iso of base.keys()) {
    const plus2 = addDaysIso(iso, 2);
    if (!base.has(plus2)) continue;
    const between = addDaysIso(iso, 1);
    if (all.has(between)) continue;
    if (parseIsoUtc(between).getUTCDay() !== 0) {
      all.set(between, '休日');
      if (provisional.has(iso) || provisional.has(plus2)) provisional.add(between);
    }
  }

  // 振替休日 (祝日法第3条第2項): if a national holiday falls on Sunday, the
  // next non-holiday day becomes a substitute holiday.
  for (const iso of [...base.keys()].sort()) {
    if (parseIsoUtc(iso).getUTCDay() !== 0) continue;
    let next = addDaysIso(iso, 1);
    while (all.has(next)) {
      next = addDaysIso(next, 1);
    }
    all.set(next, '休日');
    if (provisional.has(iso)) provisional.add(next);
  }

  // Apply explicit overrides last so statutory additions/removals always win.
  const prefix = `${year}-`;
  for (const [iso, name] of Object.entries(addMap)) {
    if (iso.startsWith(prefix) && typeof name === 'string' && name.trim()) {
      all.set(iso, name.trim());
      provisional.delete(iso);
    }
  }
  for (const iso of removeSet) {
    all.delete(iso);
    provisional.delete(iso);
  }

  return {
    holidays: new Map([...all.entries()].sort(([a], [b]) => a.localeCompare(b))),
    provisional,
  };
}

/**
 * Computes all Japanese national holidays (including 振替休日 and 国民の休日)
 * for [year]. Returns `Map<'YYYY-MM-DD', string>`.
 */
export function getJapaneseHolidaysForYear(year, overrides = NATIONAL_HOLIDAY_OVERRIDES) {
  return computeHolidays(year, overrides).holidays;
}

/**
 * Returns `{ name, provisional }` if `isoDate` is a national holiday, else
 * `null`. `provisional: true` marks formula-derived equinox dates not yet
 * announced in the 官報 (see OFFICIAL_HOLIDAYS_PUBLISHED_THROUGH).
 */
export function getJapaneseHolidayInfo(isoDate, overrides = NATIONAL_HOLIDAY_OVERRIDES) {
  if (typeof isoDate !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(isoDate)) {
    return null;
  }
  const year = Number.parseInt(isoDate.slice(0, 4), 10);
  const { holidays, provisional } = computeHolidays(year, overrides);
  const name = holidays.get(isoDate);
  if (!name) return null;
  return { name, provisional: provisional.has(isoDate) };
}

/**
 * Returns the holiday name if `isoDate` (`YYYY-MM-DD`) is a Japanese national
 * holiday (incl. 振替休日 / 国民の休日), or `null`.
 */
export function getJapaneseHolidayName(isoDate, overrides = NATIONAL_HOLIDAY_OVERRIDES) {
  if (typeof isoDate !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(isoDate)) {
    return null;
  }
  const year = Number.parseInt(isoDate.slice(0, 4), 10);
  const map = getJapaneseHolidaysForYear(year, overrides);
  return map.get(isoDate) ?? null;
}

export function isJapaneseHoliday(isoDate, overrides = NATIONAL_HOLIDAY_OVERRIDES) {
  return getJapaneseHolidayName(isoDate, overrides) !== null;
}
