import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  NATIONAL_HOLIDAY_OVERRIDES,
  getJapaneseHolidayInfo,
  getJapaneseHolidayName,
  getJapaneseHolidaysForYear,
  isJapaneseHoliday,
} from '../school/jp_holidays.js';

// Official Cabinet Office source for 2026–2027 verified dates:
//   https://www8.cao.go.jp/chosei/shukujitsu/syukujitsu.csv
// (2028 is computed under 国民の祝日に関する法律; official 2028 官報 announcement
//  occurs in Feb 2027 and any change can be applied via NATIONAL_HOLIDAY_OVERRIDES.)

const OFFICIAL_2026 = [
  ['2026-01-01', '元日'],
  ['2026-01-12', '成人の日'],
  ['2026-02-11', '建国記念の日'],
  ['2026-02-23', '天皇誕生日'],
  ['2026-03-20', '春分の日'],
  ['2026-04-29', '昭和の日'],
  ['2026-05-03', '憲法記念日'],
  ['2026-05-04', 'みどりの日'],
  ['2026-05-05', 'こどもの日'],
  ['2026-05-06', '休日'], // 振替休日 (5/3 Sun -> 5/6 Wed)
  ['2026-07-20', '海の日'],
  ['2026-08-11', '山の日'],
  ['2026-09-21', '敬老の日'],
  ['2026-09-22', '休日'], // 国民の休日 (between 9/21 敬老の日 and 9/23 秋分の日)
  ['2026-09-23', '秋分の日'],
  ['2026-10-12', 'スポーツの日'],
  ['2026-11-03', '文化の日'],
  ['2026-11-23', '勤労感謝の日'],
];

const OFFICIAL_2027 = [
  ['2027-01-01', '元日'],
  ['2027-01-11', '成人の日'],
  ['2027-02-11', '建国記念の日'],
  ['2027-02-23', '天皇誕生日'],
  ['2027-03-21', '春分の日'],
  ['2027-03-22', '休日'], // 振替休日 (3/21 Sun -> 3/22 Mon)
  ['2027-04-29', '昭和の日'],
  ['2027-05-03', '憲法記念日'],
  ['2027-05-04', 'みどりの日'],
  ['2027-05-05', 'こどもの日'],
  ['2027-07-19', '海の日'],
  ['2027-08-11', '山の日'],
  ['2027-09-20', '敬老の日'],
  ['2027-09-23', '秋分の日'],
  ['2027-10-11', 'スポーツの日'],
  ['2027-11-03', '文化の日'],
  ['2027-11-23', '勤労感謝の日'],
];

const EXPECTED_2028 = [
  ['2028-01-01', '元日'],
  ['2028-01-10', '成人の日'],
  ['2028-02-11', '建国記念の日'],
  ['2028-02-23', '天皇誕生日'],
  ['2028-03-20', '春分の日'],
  ['2028-04-29', '昭和の日'],
  ['2028-05-03', '憲法記念日'],
  ['2028-05-04', 'みどりの日'],
  ['2028-05-05', 'こどもの日'],
  ['2028-07-17', '海の日'],
  ['2028-08-11', '山の日'],
  ['2028-09-18', '敬老の日'],
  ['2028-09-22', '秋分の日'],
  ['2028-10-09', 'スポーツの日'],
  ['2028-11-03', '文化の日'],
  ['2028-11-23', '勤労感謝の日'],
];

test('2026 Japanese national holidays match Cabinet Office official syukujitsu.csv (incl. 振替休日 and 国民の休日)', () => {
  const actual = [...getJapaneseHolidaysForYear(2026).entries()];
  assert.deepEqual(actual, OFFICIAL_2026);
  assert.equal(getJapaneseHolidayName('2026-05-06'), '休日');
  assert.equal(getJapaneseHolidayName('2026-09-22'), '休日');
  assert.equal(isJapaneseHoliday('2026-05-07'), false);
});

test('2027 Japanese national holidays match Cabinet Office official syukujitsu.csv (incl. 3/22 振替休日)', () => {
  const actual = [...getJapaneseHolidaysForYear(2027).entries()];
  assert.deepEqual(actual, OFFICIAL_2027);
  assert.equal(getJapaneseHolidayName('2027-03-22'), '休日');
});

test('2028 Japanese national holidays match 国民の祝日法 and mark equinoxes as provisional', () => {
  const actual = [...getJapaneseHolidaysForYear(2028).entries()];
  assert.deepEqual(actual, EXPECTED_2028);

  // 2028 春分の日 / 秋分の日 have not yet been announced in Feb 2027 官報 -> provisional: true
  assert.deepEqual(getJapaneseHolidayInfo('2028-03-20'), {
    name: '春分の日',
    provisional: true,
  });
  assert.deepEqual(getJapaneseHolidayInfo('2028-09-22'), {
    name: '秋分の日',
    provisional: true,
  });

  // Fixed 2028 holidays and officially published 2026–2027 holidays -> provisional: false
  assert.deepEqual(getJapaneseHolidayInfo('2028-01-01'), {
    name: '元日',
    provisional: false,
  });
  assert.deepEqual(getJapaneseHolidayInfo('2026-09-22'), {
    name: '休日',
    provisional: false,
  });
  assert.deepEqual(getJapaneseHolidayInfo('2027-03-21'), {
    name: '春分の日',
    provisional: false,
  });
});

test('NATIONAL_HOLIDAY_OVERRIDES supports adding and removing holiday dates cleanly', () => {
  assert.ok(NATIONAL_HOLIDAY_OVERRIDES.add && NATIONAL_HOLIDAY_OVERRIDES.remove);

  const custom = {
    add: { '2026-06-15': '特別祝日' },
    remove: new Set(['2026-08-11']),
  };
  assert.equal(getJapaneseHolidayName('2026-06-15', custom), '特別祝日');
  assert.equal(isJapaneseHoliday('2026-08-11', custom), false);
  // Original 2026 holidays remain untouched
  assert.equal(isJapaneseHoliday('2026-08-11'), true);
});
