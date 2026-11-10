import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import {
  pushLang,
  pt,
  formatPushDate,
  weekdayName,
  groupByLang,
  recipientOf,
} from '../school/push_i18n.js';
import { sendAll } from '../school/sync.js';
import { collectPushStrings } from '../scripts/sync_push_strings.mjs';

test('pushLang resolves valid language and falls back to ja', () => {
  assert.equal(pushLang('ja'), 'ja');
  assert.equal(pushLang('en'), 'en');
  assert.equal(pushLang('uz'), 'uz');
  assert.equal(pushLang('zh_TW'), 'zh_TW');
  assert.equal(pushLang('unknown'), 'ja');
  assert.equal(pushLang(null), 'ja');
  assert.equal(pushLang(undefined), 'ja');
  assert.equal(pushLang(''), 'ja');
  assert.equal(pushLang(123), 'ja');
});

test('pt fills placeholders from params object', () => {
  const ja = pt('ja', 'push_status_body', { day: '水曜日', n: 3 });
  assert.equal(ja, '水曜日 3限');

  const en = pt('en', 'push_status_body', { day: 'Wednesday', n: 3 });
  assert.equal(en, 'Wednesday, period 3');

  const roomJa = pt('ja', 'push_room_detail', { from: '101', to: '202' });
  assert.equal(roomJa, '：101 → 202');

  const roomEn = pt('en', 'push_room_detail', { from: '101', to: '202' });
  assert.equal(roomEn, ': 101 → 202');

  const syncJa = pt('ja', 'push_sync_body', {
    grade: 2,
    course: '観光',
    when: '10/29（木）',
    subject: '英語',
    what: '休講',
    more: '',
  });
  assert.equal(syncJa, '2年・観光：10/29（木） 英語 → 休講');
});

test('pt leaves missing placeholders untouched and handles extra params', () => {
  const partial = pt('ja', 'push_status_body', { day: '金曜日' });
  assert.equal(partial, '金曜日 {n}限');

  const withExtra = pt('ja', 'push_notice_title', { unused: 'value' });
  assert.equal(withExtra, 'お知らせ');
});

test('pt falls back to ja for unknown or missing lang', () => {
  assert.equal(pt('unknown_lang', 'push_notice_title'), 'お知らせ');
  assert.equal(pt('invalid_locale', 'push_notice_urgent'), '【緊急】お知らせ');
  assert.equal(pt(null, 'push_notice_title'), 'お知らせ');
  assert.equal(pt(undefined, 'push_notice_title'), 'お知らせ');
  assert.equal(pt('', 'push_notice_urgent'), '【緊急】お知らせ');
});

test('pt returns raw key if not found in language or fallback', () => {
  assert.equal(pt('ja', 'non_existent_key'), 'non_existent_key');
  assert.equal(pt('en', 'non_existent_key'), 'non_existent_key');
});

test('formatPushDate ja keeps the format 10/29（木）', () => {
  // 2026-10-29 was a Thursday (木)
  assert.equal(formatPushDate('2026-10-29', 'ja'), '10/29（木）');
  // 2026-11-01 was a Sunday (日)
  assert.equal(formatPushDate('2026-11-01', 'ja'), '11/1（日）');
  // 2026-11-02 was a Monday (月)
  assert.equal(formatPushDate('2026-11-02', 'ja'), '11/2（月）');

  // Unknown/missing lang falls back to ja format
  assert.equal(formatPushDate('2026-10-29', 'unknown'), '10/29（木）');
  assert.equal(formatPushDate('2026-10-29', null), '10/29（木）');
  assert.equal(formatPushDate('2026-10-29', undefined), '10/29（木）');

  // Other languages use Intl format with month, day, and weekday
  const en = formatPushDate('2026-10-29', 'en');
  assert.match(en, /10\/29/);
  assert.match(en, /Thu/);
});

test('weekdayName formats canonical kanji into localized weekday name', () => {
  // ja returns kanji + 曜日
  assert.equal(weekdayName('月', 'ja'), '月曜日');
  assert.equal(weekdayName('火', 'ja'), '火曜日');
  assert.equal(weekdayName('水', 'ja'), '水曜日');
  assert.equal(weekdayName('木', 'ja'), '木曜日');
  assert.equal(weekdayName('金', 'ja'), '金曜日');
  assert.equal(weekdayName('土', 'ja'), '土曜日');
  assert.equal(weekdayName('日', 'ja'), '日曜日');

  // en returns English weekday names
  assert.equal(weekdayName('月', 'en'), 'Monday');
  assert.equal(weekdayName('木', 'en'), 'Thursday');
  assert.equal(weekdayName('日', 'en'), 'Sunday');

  // Unknown kanji or non-kanji returns as is
  assert.equal(weekdayName('祝', 'ja'), '祝');
  assert.equal(weekdayName('X', 'ja'), 'X');
  assert.equal(weekdayName('X', 'en'), 'X');

  // Empty, null or undefined returns empty string
  assert.equal(weekdayName('', 'ja'), '');
  assert.equal(weekdayName(null, 'ja'), '');
  assert.equal(weekdayName(undefined, 'ja'), '');
});

test('groupByLang dedupes tokens and skips empty tokens', () => {
  const recipients = [
    { token: 'tok_ja_1', lang: 'ja' },
    { token: 'tok_ja_1', lang: 'ja' }, // duplicate token
    { token: 'tok_ja_2', lang: 'ja' },
    { token: '', lang: 'ja' }, // empty token
    { token: null, lang: 'ja' }, // null token
    { token: undefined, lang: 'ja' }, // undefined token
    { token: 'tok_en_1', lang: 'en' },
    { token: 'tok_en_1', lang: 'en' }, // duplicate token
    { token: 'tok_fallback_1', lang: 'unknown_lang' }, // falls back to ja
    { token: 'tok_fallback_2', lang: null }, // falls back to ja
  ];

  const groups = groupByLang(recipients);
  assert.equal(groups.length, 2);

  const jaGroup = groups.find((g) => g.lang === 'ja');
  const enGroup = groups.find((g) => g.lang === 'en');

  assert.ok(jaGroup);
  assert.deepEqual(jaGroup.tokens, ['tok_ja_1', 'tok_ja_2', 'tok_fallback_1', 'tok_fallback_2']);

  assert.ok(enGroup);
  assert.deepEqual(enGroup.tokens, ['tok_en_1']);
});

test('recipientOf extracts fcmToken and language from user doc data', () => {
  assert.deepEqual(
    recipientOf({ fcmToken: 'token_abc', language: 'en', otherField: 123 }),
    { token: 'token_abc', lang: 'en' },
  );
  assert.deepEqual(
    recipientOf({ language: 'ja' }),
    { token: undefined, lang: 'ja' },
  );
  assert.deepEqual(
    recipientOf(null),
    { token: undefined, lang: undefined },
  );
  assert.deepEqual(
    recipientOf(undefined),
    { token: undefined, lang: undefined },
  );
});

test('sendAll sends one multicast per language with data.route', async () => {
  const multicasts = [];
  const sendMulticast = async (payload) => {
    multicasts.push(payload);
  };

  const recipients = [
    { token: 'tok_ja_1', lang: 'ja' },
    { token: 'tok_ja_2', lang: 'ja' },
    { token: 'tok_en_1', lang: 'en' },
  ];

  const messageBuilder = (lang) => ({
    title: pt(lang, 'push_notice_urgent'),
    body: '重要なお知らせ',
  });

  await sendAll(sendMulticast, recipients, messageBuilder, '/home');

  assert.equal(multicasts.length, 2);

  const jaCall = multicasts.find((m) => m.notification.title === '【緊急】お知らせ');
  const enCall = multicasts.find((m) => m.notification.title === '[Urgent] Notice');

  assert.ok(jaCall);
  assert.deepEqual(jaCall.tokens, ['tok_ja_1', 'tok_ja_2']);
  assert.equal(jaCall.notification.body, '重要なお知らせ');
  assert.deepEqual(jaCall.data, { route: '/home' });
  assert.equal(jaCall.android?.notification?.channelId, 'eduplanner_reminders');

  assert.ok(enCall);
  assert.deepEqual(enCall.tokens, ['tok_en_1']);
  assert.equal(enCall.notification.body, '重要なお知らせ');
  assert.deepEqual(enCall.data, { route: '/home' });
  assert.equal(enCall.android?.notification?.channelId, 'eduplanner_reminders');
});

test('sendAll supports static message object and defaults route to /timetable', async () => {
  const multicasts = [];
  const sendMulticast = async (payload) => {
    multicasts.push(payload);
  };

  const recipients = [{ token: 'tok_1', lang: 'ja' }];
  const staticMsg = { title: '全体連絡', body: '本文' };

  await sendAll(sendMulticast, recipients, staticMsg);

  assert.equal(multicasts.length, 1);
  assert.deepEqual(multicasts[0].notification, staticMsg);
  assert.deepEqual(multicasts[0].data, { route: '/timetable' });
});

test('sendAll chunks multicasts exceeding MULTICAST_MAX (500 tokens)', async () => {
  const multicasts = [];
  const sendMulticast = async (payload) => {
    multicasts.push(payload);
  };

  // 505 tokens in ja
  const recipients = Array.from({ length: 505 }, (_, i) => ({
    token: `token_${i}`,
    lang: 'ja',
  }));

  await sendAll(sendMulticast, recipients, { title: 'T', body: 'B' }, '/home');

  assert.equal(multicasts.length, 2);
  assert.equal(multicasts[0].tokens.length, 500);
  assert.equal(multicasts[1].tokens.length, 5);
});

test('freshness test: collectPushStrings() deep-equals school/push_strings.json', () => {
  const collected = collectPushStrings();
  const current = JSON.parse(
    readFileSync(new URL('../school/push_strings.json', import.meta.url), 'utf8'),
  );
  assert.deepEqual(collected, current);
});
