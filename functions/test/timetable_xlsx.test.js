import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import ExcelJS from 'exceljs';
import {
  xlsxToRows,
  parseTimetableRows,
  dayDocId,
  TimetableParseError,
} from '../school/timetable_xlsx.js';

const loadRows = () => JSON.parse(
  readFileSync(new URL('./fixtures/school_rows.json', import.meta.url), 'utf8'),
);
const trimRow = (r) => {
  const out = [...r];
  while (out.length && out[out.length - 1] === '') out.pop();
  return out;
};
const find = (parsed, grade, course, date) =>
  parsed.days.find((d) => d.grade === grade && d.course === course && d.date === date);

test('parses periods from headers', () => {
  const { periods } = parseTimetableRows(loadRows());
  assert.deepEqual(periods, [
    { key: '1-2', label: '1・2限', start: '09:00', end: '10:30' },
    { key: '3-4', label: '3・4限', start: '10:40', end: '12:10' },
    { key: '5-6', label: '5・6限', start: '13:10', end: '14:40' },
    { key: '7-8', label: '7・8限', start: '14:50', end: '16:20' },
  ]);
});

test('assigns grade and course per half', () => {
  const parsed = parseTimetableRows(loadRows());
  assert.deepEqual(parsed.grades, [1, 2]);
  assert.deepEqual(parsed.courses, ['農業', '観光']);
  const day = find(parsed, 1, '農業', '2026-10-26');
  assert.deepEqual(day.slots[0], {
    period: '1-2', subject: 'IT概論2', teacher: '田中', room: '104', note: '', status: 'normal',
  });
  assert.equal(day.slots.length, 4);
  assert.ok(find(parsed, 2, '観光', '2026-10-26'));
});

test('rolls January into next year', () => {
  const dates = parseTimetableRows(loadRows()).days.map((d) => d.date);
  assert.ok(dates.some((d) => d.startsWith('2026-10-')));
  const jan = dates.filter((d) => d.slice(5, 7) === '01');
  assert.ok(jan.length > 0);
  assert.ok(jan.every((d) => d.startsWith('2027-01-')));
});

test('classifies statuses', () => {
  const parsed = parseTimetableRows(loadRows());
  const first = (date, course) => find(parsed, 1, course, date).slots[0];
  assert.deepEqual(
    [first('2026-10-28', '農業').status, first('2026-10-28', '農業').note],
    ['cancelled', '英語休講'],
  );
  assert.equal(first('2026-10-29', '農業').status, 'event');
  assert.equal(first('2026-10-28', '観光').status, 'tbd');
  assert.equal(first('2026-10-30', '農業').status, 'elective');
  const ev = first('2026-10-30', '観光');
  assert.equal(ev.status, 'event');
  assert.equal(ev.teacher, '田中');
  assert.equal(ev.room, '101');
  assert.equal(ev.note, '企業説明会');
});

test('emits empty days', () => {
  const day = find(parseTimetableRows(loadRows()), 2, '観光', '2026-10-28');
  assert.ok(day);
  assert.deepEqual(day.slots, []);
});

test('throws on missing periods', () => {
  const rows = loadRows();
  // drop the 7・8 header in the first week's both halves
  const i = rows.findIndex((r) => /７・８限目/.test(r[1] ?? ''));
  rows[i][1] = '';
  rows[i][9] = '';
  assert.throws(() => parseTimetableRows(rows), TimetableParseError);
});

test('throws without fiscal year, and on invalid dates', () => {
  const noYear = loadRows();
  noYear[0] = [];
  assert.throws(() => parseTimetableRows(noYear), TimetableParseError);
  const badDate = loadRows();
  badDate[2][3] = '2月30日';
  assert.throws(() => parseTimetableRows(badDate), TimetableParseError);
});

test('extracts fiscal year from sheetName, options or rawRows.sheetName', () => {
  const rows = loadRows();
  rows[0] = []; // no year cell
  const p1 = parseTimetableRows(rows, { sheetName: '2026年度 後期' });
  assert.equal(p1.days[0].date.startsWith('2026-'), true);
  const p2 = parseTimetableRows(rows, { fileName: '2026年度 後期時間割.xlsx' });
  assert.equal(p2.days[0].date.startsWith('2026-'), true);
  rows.sheetName = '2026年度 後期';
  const p3 = parseTimetableRows(rows);
  assert.equal(p3.days[0].date.startsWith('2026-'), true);
});

test('parses periods with loose whitespace around dots and numbers', () => {
  const rows = loadRows();
  rows[3][1] = '1 ・ 2 限目 09:00 ~ 10:30';
  rows[8][1] = '3 ・4 限目 10:40~12:10';
  rows[13][1] = '5 ・ 6限目 13:10~14:40';
  rows[18][1] = '7 ・8 限目 14:50~16:20';
  const { periods } = parseTimetableRows(rows);
  assert.equal(periods.length, 4);
  assert.equal(periods.map((p) => p.key).join(','), '1-2,3-4,5-6,7-8');
});

test('dayDocId', () => {
  assert.equal(dayDocId('sch', { grade: 1, course: '農業', date: '2026-10-26' }), 'sch_1_農業_20261026');
});

test('xlsxToRows round-trips exceljs workbook', async () => {
  const rows = loadRows();
  const wb = new ExcelJS.Workbook();
  const ws = wb.addWorksheet('t');
  rows.forEach((r) => ws.addRow(r));
  ws.mergeCells('B1:C1'); // merged non-master cell must come back as ''
  const buf = Buffer.from(await wb.xlsx.writeBuffer());
  const got = await xlsxToRows(buf);
  const expected = rows.map(trimRow);
  expected[0] = ['', '2026年度 後期'];
  assert.deepEqual(got.map(trimRow), expected);
});

test('xlsxToRows handles date, rich text, formula and hyperlink cells', async () => {
  const wb = new ExcelJS.Workbook();
  const ws = wb.addWorksheet('t');
  ws.getCell('A1').value = new Date(Date.UTC(2026, 9, 26));
  ws.getCell('A1').numFmt = 'm"月"d"日"';
  ws.getCell('B1').value = { richText: [{ text: '田中' }, { text: '【104】', font: { bold: true } }] };
  ws.getCell('C1').value = { formula: 'A1', result: new Date(Date.UTC(2027, 0, 5)) };
  ws.getCell('D1').value = { text: '鈴木', hyperlink: 'https://example.com' };
  ws.getCell('E1').value = { formula: '1+1', result: 2 };
  const got = await xlsxToRows(Buffer.from(await wb.xlsx.writeBuffer()));
  assert.deepEqual(got[0].slice(0, 5), ['10月26日', '田中【104】', '1月5日', '鈴木', '2']);
});
