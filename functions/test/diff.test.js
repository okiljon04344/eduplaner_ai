import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  slotsHash,
  diffDays,
  describeChange,
  buildClassMessage,
} from '../school/diff.js';

const periods = [
  { key: '1-2', label: '1・2限', start: '08:50', end: '10:30' },
  { key: '3-4', label: '3・4限', start: '10:40', end: '12:20' },
];
const slot = (period, o = {}) => ({
  period, subject: '数学', teacher: '田中', room: '101', note: '', status: 'normal', ...o,
});
const day = (date, slots) => ({ grade: 1, course: '農業', date, slots });
const TODAY = '2026-10-27';

test('slotsHash ignores slot order and detects changes', () => {
  const a = slot('1-2'), b = slot('3-4');
  assert.equal(slotsHash([a, b]), slotsHash([b, a]));
  assert.notEqual(slotsHash([a, b]), slotsHash([a, { ...b, room: '203' }]));
  assert.match(slotsHash([]), /^[0-9a-f]{40}$/);
});

test('diffDays ignores dates before today', () => {
  const prev = new Map([['2026-10-26', [slot('1-2')]]]);
  const next = [day('2026-10-26', [slot('1-2', { room: '999' })])];
  assert.deepEqual(diffDays(prev, next, TODAY), []);
});

test('diffDays detects room change', () => {
  const prev = new Map([['2026-10-29', [slot('1-2')]]]);
  const next = [day('2026-10-29', [slot('1-2', { room: '203' })])];
  const changes = diffDays(prev, next, TODAY);
  assert.equal(changes.length, 1);
  assert.equal(changes[0].before.room, '101');
  assert.equal(changes[0].after.room, '203');
});

test('diffDays detects removed and added slots', () => {
  const prev = new Map([
    ['2026-10-29', [slot('1-2')]],
    ['2026-10-30', [slot('1-2')]],
  ]);
  const next = [day('2026-10-29', [slot('1-2'), slot('3-4')])];
  const changes = diffDays(prev, next, TODAY);
  assert.equal(changes.length, 2);
  const added = changes.find((c) => c.date === '2026-10-29');
  assert.equal(added.before, null);
  assert.equal(added.after.period, '3-4');
  const removed = changes.find((c) => c.date === '2026-10-30');
  assert.equal(removed.after, null);
  assert.equal(removed.before.period, '1-2');
});

test('diffDays returns [] for identical days', () => {
  const prev = new Map([['2026-10-29', [slot('1-2'), slot('3-4')]]]);
  const next = [day('2026-10-29', [slot('3-4'), slot('1-2')])];
  assert.deepEqual(diffDays(prev, next, TODAY), []);
});

test('buildClassMessage formats cancellation', () => {
  const eng = slot('3-4', { subject: '英語' });
  const changes = [
    { date: '2026-10-29', period: '3-4', before: eng, after: { ...eng, status: 'cancelled' } },
    { date: '2026-10-30', period: '1-2', before: null, after: slot('1-2') },
  ];
  const msg = buildClassMessage(1, '農業', changes, periods);
  assert.equal(msg.title, '時間割の変更');
  assert.equal(msg.body, '1年・農業：10/29（木）3・4限 英語 → 休講 ほか1件');
});

test('buildClassMessage formats room change', () => {
  const s = slot('3-4', { subject: '英語' });
  const changes = [
    { date: '2026-10-29', period: '3-4', before: s, after: { ...s, room: '203' } },
  ];
  assert.equal(
    buildClassMessage(1, '農業', changes, periods).body,
    '1年・農業：10/29（木）3・4限 英語 → 教室 101→203',
  );
});

test('buildClassMessage picks earliest change; describeChange covers other cases', () => {
  const s = slot('1-2');
  const later = { date: '2026-11-02', period: '1-2', before: s, after: null };
  const earlier = { date: '2026-10-29', period: '3-4', before: null, after: slot('3-4', { subject: '理科' }) };
  const body = buildClassMessage(2, '畜産', [later, earlier], periods).body;
  assert.equal(body, '2年・畜産：10/29（木）3・4限 理科 → 追加 ほか1件');
  assert.equal(describeChange(later, periods).what, '授業なし');
  assert.equal(
    describeChange({ date: '2026-10-29', period: '1-2', before: s, after: { ...s, teacher: '鈴木' } }, periods).what,
    '変更',
  );
});
