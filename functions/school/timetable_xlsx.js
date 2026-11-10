import ExcelJS from 'exceljs';

export class TimetableParseError extends Error {
  constructor(message) {
    super(message);
    this.name = 'TimetableParseError';
  }
}

export const dayDocId = (domain, day) =>
  `${domain}_${day.grade}_${day.course}_${day.date.replaceAll('-', '')}`;

// ExcelJS cell value -> string. Dates come back as UTC Date objects (cell.text is locale-dependent).
function valueToString(v) {
  if (v == null) return '';
  if (v instanceof Date) return `${v.getUTCMonth() + 1}月${v.getUTCDate()}日`;
  if (typeof v !== 'object') return String(v);
  if (Array.isArray(v.richText)) return v.richText.map((t) => t.text ?? '').join('');
  if ('result' in v) return valueToString(v.result); // formula / sharedFormula
  if ('text' in v) return valueToString(v.text); // hyperlink
  return ''; // error values etc.
}

/** First worksheet -> string[][] (0-indexed). Merged (non-master) and empty cells are ''. */
export async function xlsxToRows(buffer) {
  const wb = new ExcelJS.Workbook();
  await wb.xlsx.load(buffer);
  const ws = wb.worksheets[0];
  if (!ws) return [];
  const rows = [];
  for (let r = 1; r <= ws.rowCount; r++) {
    const row = [];
    for (let c = 1; c <= ws.columnCount; c++) {
      const cell = ws.getCell(r, c);
      row.push(cell.isMerged && cell.master !== cell ? '' : valueToString(cell.value));
    }
    rows.push(row);
  }
  rows.sheetName = ws.name;
  return rows;
}

const DATE_RE = /^(\d{1,2})月(\d{1,2})日$/;
const GRADE_RE = /^(\d)年生$/;
const PERIOD_RE = /(\d)\s*・\s*(\d)\s*限目?\s*(\d{1,2}):(\d{2})\s*[~-]\s*(\d{1,2}):(\d{2})/;
const TEACHER_RE = /^(.*?)【(.*?)】(.*)$/;
const EVENT_RE = /学園祭準備|学園準備|宿泊研修|全員登校日|企業説明会|郊外学習/;
const pad = (n) => String(n).padStart(2, '0');

const norm = (v) => String(v ?? '').normalize('NFKC').replace(/\s+/g, ' ').trim();

function statusOf(subj, tcell) {
  const either = (re) => re.test(subj) || re.test(tcell);
  if (either(/休講/) || subj === '休み') return 'cancelled';
  if (either(EVENT_RE)) return 'event';
  if (either(/追って連絡/)) return 'tbd';
  if (['X', 'Y', 'Z'].includes(subj)) return 'elective';
  return 'normal';
}

function toSlot(period, subj, tcell) {
  const m = TEACHER_RE.exec(tcell);
  const [teacher, room, rest] = m ? [m[1].trim(), m[2].trim(), m[3].trim()] : ['', '', tcell];
  return { period, subject: subj, teacher, room, note: rest, status: statusOf(subj, tcell) };
}

export function parseTimetableRows(rawRows, options = {}) {
  const rows = rawRows.map((r) => r.map(norm));

  let year = rows.flat().map((s) => /(\d{4})年度/.exec(s)).find(Boolean)?.[1];
  if (!year && rawRows.sheetName) year = /(\d{4})年度/.exec(rawRows.sheetName)?.[1];
  if (!year && options.sheetName) year = /(\d{4})年度/.exec(options.sheetName)?.[1];
  if (!year && options.fileName) year = /(\d{4})年度/.exec(options.fileName)?.[1];
  if (!year) throw new TimetableParseError('年度 (fiscal year) cell not found');
  const fiscalYear = Number(year);

  const isDateRow = (r) => r.filter((s) => DATE_RE.test(s)).length >= 3;
  const isGradeRow = (r) => r.some((s) => GRADE_RE.test(s));

  const periods = new Map(); // key -> Period
  const days = new Map(); // `${grade}|${course}|${date}` -> Day
  const courses = [];
  let halves = 0;

  const toIsoDate = (m, d) => {
    const y = m >= 4 ? fiscalYear : fiscalYear + 1;
    const dt = new Date(y, m - 1, d);
    if (Number.isNaN(dt.getTime()) || dt.getMonth() !== m - 1 || dt.getDate() !== d) {
      throw new TimetableParseError(`invalid date: ${m}月${d}日`);
    }
    return `${y}-${pad(m)}-${pad(d)}`;
  };

  const gradeFor = (ri, start) => {
    for (let k = 0; k <= 2 && ri - k >= 0; k++) {
      const row = rows[ri - k];
      for (let c = Math.min(start, row.length - 1); c >= 0; c--) {
        const g = GRADE_RE.exec(row[c]);
        if (g) return Number(g[1]);
      }
    }
    throw new TimetableParseError(`grade header not found for date row ${ri}`);
  };

  rows.forEach((row, ri) => {
    if (!isDateRow(row)) return;
    // maximal runs of consecutive date columns
    const runs = [];
    row.forEach((s, c) => {
      if (!DATE_RE.test(s)) return;
      const last = runs[runs.length - 1];
      if (last && last.cols[last.cols.length - 1] === c - 1) last.cols.push(c);
      else runs.push({ cols: [c] });
    });

    for (const { cols } of runs) {
      halves++;
      const start = cols[0];
      const grade = gradeFor(ri, start);
      const dates = cols.map((c) => {
        const [, m, d] = DATE_RE.exec(row[c]);
        return toIsoDate(Number(m), Number(d));
      });
      const halfPeriods = new Set();
      let current = null;
      const seen = [];

      for (let r = ri + 1; r < rows.length && !isDateRow(rows[r]) && !isGradeRow(rows[r]); r++) {
        const cur = rows[r];
        const ph = PERIOD_RE.exec(cur[start - 2] ?? '');
        if (ph) {
          const [, a, b, h1, m1, h2, m2] = ph;
          const p = {
            key: `${a}-${b}`, label: `${a}・${b}限`,
            start: `${pad(h1)}:${m1}`, end: `${pad(h2)}:${m2}`,
          };
          const prev = periods.get(p.key);
          if (prev && (prev.start !== p.start || prev.end !== p.end)) {
            throw new TimetableParseError(`conflicting times for period ${p.key}`);
          }
          if (!prev) periods.set(p.key, p);
          halfPeriods.add(p.key);
          current = p.key;
        }

        const course = cur[start - 1] ?? '';
        if (!course || course === '休憩' || /年生/.test(course) || !current) continue;
        if (!courses.includes(course)) courses.push(course);
        if (!seen.includes(course)) seen.push(course);
        const next = rows[r + 1];
        const hasTeachers = next && !(next[start - 1] ?? '');
        cols.forEach((c, i) => {
          const subj = cur[c] ?? '';
          const tcell = hasTeachers ? next[c] ?? '' : '';
          const dayKey = `${grade}|${course}|${dates[i]}`;
          if (!days.has(dayKey)) days.set(dayKey, { grade, course, date: dates[i], slots: [] });
          if (subj || tcell) days.get(dayKey).slots.push(toSlot(current, subj, tcell));
        });
      }

      if (halfPeriods.size !== 4) {
        throw new TimetableParseError(`expected 4 periods, found ${halfPeriods.size} (row ${ri}, grade ${grade})`);
      }
    }
  });

  if (!halves) throw new TimetableParseError('no week blocks found');

  const dayList = [...days.values()];
  return {
    periods: [...periods.values()],
    grades: [...new Set(dayList.map((d) => d.grade))].sort((a, b) => a - b),
    courses,
    days: dayList,
  };
}
