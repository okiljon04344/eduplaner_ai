import { randomUUID } from 'node:crypto';
import ExcelJS from 'exceljs';
import { HttpsError } from 'firebase-functions/https';
import { logger } from 'firebase-functions';
import { dayDocId, parseTimetableRows, TimetableParseError } from './timetable_xlsx.js';
import { slotsHash } from './diff.js';
import { isTeacher } from './overrides.js';
import { getJapaneseHolidayInfo } from './jp_holidays.js';
import { pt } from './push_i18n.js';
import {
  canUserImportTimetable,
  canUserUseReplaceMode,
  isValidIsoDate,
  loadSchoolPolicy,
} from './policy.js';
import {
  REDACTABLE_IMAGE_MIMES,
  ocrImageDocument,
} from '../privacy/image_redactor.js';
import { extractPdfText } from '../privacy/pdf_extractor.js';
import { callAiSafely } from '../privacy/safe_ai.js';
import { mapAiError } from '../ai/ai_errors.js';
import { gridToText, reconstructGrid, visionWordsToTokens } from './timetable_grid.js';
import { ERROR_REASONS } from '../shared/error_reasons.js';

export const MAX_IMPORT_FILE_BYTES = 10 * 1024 * 1024;
export const MAX_IMPORT_SHEETS = 10;
export const MAX_IMPORT_ROWS = 5000;
export const MAX_IMPORT_XLSX_ENTRIES = 500;
export const MAX_IMPORT_XLSX_UNCOMPRESSED_BYTES = 50 * 1024 * 1024;
export const MAX_IMPORT_RANGE_DAYS = 366;
export const MAX_AI_IMPORT_CHARS = 6000;
export const MAX_INVALID_ROWS_RETURNED = 100;
export const DRAFT_TTL_MS = 30 * 60 * 1000;
export const IMPORT_HISTORY_TTL_DAYS = 30;
export const BATCH_CHUNK_SIZE = 400;
export const DIFF_PREVIEW_LIMIT = 200;

const HEIC_MIME_TYPES = new Set(['image/heic', 'image/heif']);

/**
 * Fallback periods matching `lib/core/constants/periods.dart` (`kPeriodTimes`).
 * Used only when `schools/{domain}.periods` is absent or empty.
 */
export const DEFAULT_IMPORT_PERIODS = Object.freeze([
  Object.freeze({ key: '1', label: '1限', start: '09:00', end: '10:30' }),
  Object.freeze({ key: '2', label: '2限', start: '10:40', end: '12:10' }),
  Object.freeze({ key: '3', label: '3限', start: '13:00', end: '14:30' }),
  Object.freeze({ key: '4', label: '4限', start: '14:40', end: '16:10' }),
  Object.freeze({ key: '5', label: '5限', start: '16:20', end: '17:50' }),
  Object.freeze({ key: '6', label: '6限', start: '18:00', end: '19:30' }),
]);

const WEEKDAY_KANJI_BY_UTC_DAY = ['日', '月', '火', '水', '木', '金', '土'];

const bad = (message, details) => {
  throw new HttpsError('invalid-argument', message, details);
};

const normText = (v) =>
  String(v ?? '')
    .normalize('NFKC')
    .replace(/\s+/g, ' ')
    .trim();

const toDateObj = (v) => {
  if (!v) return null;
  if (v instanceof Date) return v;
  if (typeof v.toDate === 'function') return v.toDate();
  if (typeof v === 'string') {
    const parsed = new Date(v);
    return Number.isNaN(parsed.getTime()) ? null : parsed;
  }
  return null;
};

function extractJsonObject(raw) {
  if (!raw || typeof raw !== 'string') return null;
  let text = raw.trim();
  text = text.replace(/^```(?:json)?\s*/i, '').replace(/```\s*$/i, '').trim();
  const start = text.indexOf('{');
  const end = text.lastIndexOf('}');
  if (start === -1 || end === -1 || end < start) return null;
  try {
    return JSON.parse(text.slice(start, end + 1));
  } catch {
    return null;
  }
}

/**
 * Returns `schools/{domain}.periods` when present and non-empty, falling
 * back to `DEFAULT_IMPORT_PERIODS` (`periods.dart` 1–6).
 */
export function resolveSchoolPeriods(school) {
  if (Array.isArray(school?.periods) && school.periods.length > 0) {
    return school.periods;
  }
  return DEFAULT_IMPORT_PERIODS.map((p) => ({ ...p }));
}

/**
 * Inspects the ZIP Central Directory of an `.xlsx` buffer before handing it
 * to ExcelJS so a crafted zip-bomb cannot OOM the function instance.
 */
export function validateXlsxZip(buf) {
  if (!Buffer.isBuffer(buf) || buf.length < 22 || buf.readUInt32LE(0) !== 0x04034b50) {
    bad('Invalid XLSX file.');
  }
  const minEocdOffset = Math.max(0, buf.length - 65557);
  let eocdOffset = -1;
  for (let i = buf.length - 22; i >= minEocdOffset; i--) {
    if (buf.readUInt32LE(i) === 0x06054b50) {
      eocdOffset = i;
      break;
    }
  }
  if (eocdOffset === -1) {
    bad('Invalid XLSX archive directory.');
  }
  const totalEntries = buf.readUInt16LE(eocdOffset + 10);
  const cdSize = buf.readUInt32LE(eocdOffset + 12);
  const cdOffset = buf.readUInt32LE(eocdOffset + 16);
  if (totalEntries > MAX_IMPORT_XLSX_ENTRIES || cdOffset + cdSize > buf.length) {
    bad('XLSX file exceeds allowed entry count or bounds.');
  }
  let pos = cdOffset;
  let totalUncompressed = 0;
  for (let e = 0; e < totalEntries && pos + 46 <= buf.length; e++) {
    if (buf.readUInt32LE(pos) !== 0x02014b50) break;
    const uncompressedSize = buf.readUInt32LE(pos + 24);
    if (uncompressedSize === 0xffffffff) {
      bad('ZIP64 XLSX files are not supported.');
    }
    totalUncompressed += uncompressedSize;
    if (totalUncompressed > MAX_IMPORT_XLSX_UNCOMPRESSED_BYTES) {
      bad('XLSX file uncompressed size exceeds limit.');
    }
    const nameLen = buf.readUInt16LE(pos + 28);
    const extraLen = buf.readUInt16LE(pos + 30);
    const commentLen = buf.readUInt16LE(pos + 32);
    pos += 46 + nameLen + extraLen + commentLen;
  }
}

/**
 * Checks whether the current Node.js runtime has Shift_JIS (CP932) TextDecoder support.
 * Logs an error on failure and returns false.
 */
let _shiftJisSupported = null;
export function checkShiftJisSupport() {
  if (_shiftJisSupported !== null) return _shiftJisSupported;
  try {
    new TextDecoder('shift_jis');
    _shiftJisSupported = true;
  } catch (err) {
    _shiftJisSupported = false;
    logger.error('Shift_JIS (CP932) TextDecoder is NOT supported in this Node.js runtime', {
      error: err?.message,
      reason: ERROR_REASONS.sjisUnsupportedRuntime,
    });
  }
  return _shiftJisSupported;
}

/** For unit testing runtime Shift_JIS absence */
export function setShiftJisSupportForTest(val) {
  _shiftJisSupported = val;
}

// Initial probe at module load / function cold start
checkShiftJisSupport();

/**
 * Decodes a CSV buffer, automatically handling UTF-8 (with or without BOM)
 * and Windows-31J / Shift_JIS (CP932, used by Japanese Excel "CSV (コンマ区切り)").
 *
 * Uses Node.js 22 built-in full-ICU `TextDecoder('utf-8', { fatal: true })`
 * and `TextDecoder('shift_jis')` (WHATWG `shift_jis` is CP932), requiring no
 * extra npm dependency.
 */
export function decodeCsvBuffer(buffer) {
  if (!Buffer.isBuffer(buffer) || buffer.length === 0) {
    bad('Uploaded CSV file is empty.');
  }
  // Reject binary payloads masquerading as CSV.
  if (buffer.includes(0x00)) {
    bad('Uploaded CSV appears to be a binary file.');
  }

  // Explicit UTF-8 BOM
  if (buffer.length >= 3 && buffer[0] === 0xef && buffer[1] === 0xbb && buffer[2] === 0xbf) {
    try {
      const text = new TextDecoder('utf-8', { fatal: true }).decode(buffer);
      if (!text.includes('\uFFFD')) {
        return { text, encoding: 'utf-8-bom' };
      }
    } catch {
      // Fall through to Shift_JIS check below
    }
  }

  // Try strict UTF-8 first
  try {
    const utf8Text = new TextDecoder('utf-8', { fatal: true }).decode(buffer);
    if (!utf8Text.includes('\uFFFD')) {
      return { text: utf8Text, encoding: 'utf-8' };
    }
  } catch {
    // Invalid UTF-8 byte sequence -> fall back to Shift_JIS (CP932)
  }

  if (!checkShiftJisSupport()) {
    logger.error('Shift_JIS decoder unsupported in runtime for CSV import', {
      reason: ERROR_REASONS.sjisUnsupportedRuntime,
    });
    throw new HttpsError('failed-precondition', 'Shift_JIS (CP932) decoding is not supported in this runtime.', {
      reason: ERROR_REASONS.sjisUnsupportedRuntime,
    });
  }

  // Fall back to CP932 (WHATWG 'shift_jis' includes NEC/IBM extensions like ①②, 髙, 﨑)
  try {
    const sjisText = new TextDecoder('shift_jis', { fatal: true }).decode(buffer);
    if (!sjisText.includes('\uFFFD')) {
      return { text: sjisText, encoding: 'shift_jis' };
    }
  } catch {
    // Non-fatal fallback below
  }

  return {
    text: new TextDecoder('shift_jis', { fatal: false }).decode(buffer),
    encoding: 'shift_jis',
  };
}

function cellValueToString(v) {
  if (v == null) return '';
  if (v instanceof Date) {
    return `${v.getUTCFullYear()}-${String(v.getUTCMonth() + 1).padStart(2, '0')}-${String(v.getUTCDate()).padStart(2, '0')}`;
  }
  if (typeof v !== 'object') return String(v);
  if (Array.isArray(v.richText)) return v.richText.map((t) => t.text ?? '').join('');
  if ('result' in v) return cellValueToString(v.result);
  if ('text' in v) return cellValueToString(v.text);
  return '';
}

function cellValueToGridString(v) {
  if (v instanceof Date) return `${v.getUTCMonth() + 1}月${v.getUTCDate()}日`;
  return cellValueToString(v);
}

/**
 * RFC-4180 CSV parser supporting UTF-8 BOM, quoted fields, escaped `""`,
 * and CRLF/LF line endings. Enforces `MAX_IMPORT_ROWS`.
 */
export function parseCsvRows(text) {
  const clean = text.startsWith('\uFEFF') ? text.slice(1) : text;
  const rows = [];
  let row = [];
  let field = '';
  let inQuotes = false;

  for (let i = 0; i < clean.length; i++) {
    const ch = clean[i];
    if (inQuotes) {
      if (ch === '"') {
        if (clean[i + 1] === '"') {
          field += '"';
          i += 1;
        } else {
          inQuotes = false;
        }
      } else {
        field += ch;
      }
      continue;
    }

    if (ch === '"') {
      inQuotes = true;
    } else if (ch === ',') {
      row.push(field);
      field = '';
    } else if (ch === '\r' || ch === '\n') {
      if (ch === '\r' && clean[i + 1] === '\n') i += 1;
      row.push(field);
      rows.push(row);
      if (rows.length > MAX_IMPORT_ROWS) {
        bad(`CSV exceeds maximum row limit (${MAX_IMPORT_ROWS}).`);
      }
      row = [];
      field = '';
    } else {
      field += ch;
    }
  }
  if (field.length > 0 || row.length > 0) {
    row.push(field);
    rows.push(row);
    if (rows.length > MAX_IMPORT_ROWS) {
      bad(`CSV exceeds maximum row limit (${MAX_IMPORT_ROWS}).`);
    }
  }
  return rows.filter((r) => r.some((cell) => normText(cell) !== ''));
}

const WEEKDAY_ALIASES = new Map([
  ['月', '月'], ['月曜', '月'], ['月曜日', '月'], ['mon', '月'], ['monday', '月'], ['1', '月'],
  ['火', '火'], ['火曜', '火'], ['火曜日', '火'], ['tue', '火'], ['tuesday', '火'], ['2', '火'],
  ['水', '水'], ['水曜', '水'], ['水曜日', '水'], ['wed', '水'], ['wednesday', '水'], ['3', '水'],
  ['木', '木'], ['木曜', '木'], ['木曜日', '木'], ['thu', '木'], ['thursday', '木'], ['4', '木'],
  ['金', '金'], ['金曜', '金'], ['金曜日', '金'], ['fri', '金'], ['friday', '金'], ['5', '金'],
  ['土', '土'], ['土曜', '土'], ['土曜日', '土'], ['sat', '土'], ['saturday', '土'], ['6', '土'],
  ['日', '日'], ['日曜', '日'], ['日曜日', '日'], ['sun', '日'], ['sunday', '日'], ['7', '日'], ['0', '日'],
]);

function normalizeWeekday(raw) {
  const key = normText(raw).toLowerCase();
  return WEEKDAY_ALIASES.get(key) ?? null;
}

function normalizeStatus(raw) {
  const s = normText(raw).toLowerCase();
  if (!s || s === 'normal' || s === '通常') return 'normal';
  if (s === 'cancelled' || s === 'canceled' || s === '休講' || s === '休み') return 'cancelled';
  if (s === 'event' || s === '行事') return 'event';
  if (s === 'tbd' || s === '未定' || s === '追って連絡') return 'tbd';
  if (s === 'elective' || s === '選択') return 'elective';
  return 'normal';
}

function tryNormalizeDateString(raw, fallbackFiscalYear) {
  const s = normText(raw);
  if (!s) return null;
  if (isValidIsoDate(s)) return s;

  const ymdSlash = /^(\d{4})[/.-](\d{1,2})[/.-](\d{1,2})$/.exec(s);
  if (ymdSlash) {
    const iso = `${ymdSlash[1]}-${ymdSlash[2].padStart(2, '0')}-${ymdSlash[3].padStart(2, '0')}`;
    if (isValidIsoDate(iso)) return iso;
    return { error: `Invalid date: ${s}` };
  }

  const jpMd = /^(\d{1,2})月(\d{1,2})日$/.exec(s);
  const slashMd = /^(\d{1,2})\/(\d{1,2})$/.exec(s);
  const mPair = jpMd ?? slashMd;
  if (mPair) {
    const m = Number.parseInt(mPair[1], 10);
    const d = Number.parseInt(mPair[2], 10);
    const y = m >= 4 ? fallbackFiscalYear : fallbackFiscalYear + 1;
    const iso = `${y}-${String(m).padStart(2, '0')}-${String(d).padStart(2, '0')}`;
    if (isValidIsoDate(iso)) return iso;
    return { error: `Invalid date: ${s}` };
  }
  return { error: `Invalid date format: ${s}` };
}

function tryResolvePeriodKey(rawPeriod, schoolPeriods) {
  const s = normText(rawPeriod);
  if (!s) return { error: 'Period is required.' };

  for (const p of schoolPeriods) {
    if (s === p.key || s === p.label) return p.key;
  }

  const cleaned = s.replace(/限目?$/g, '').replace(/[・~〜]/g, '-').trim();
  for (const p of schoolPeriods) {
    const pk = normText(p.key);
    const pl = normText(p.label).replace(/限目?$/g, '').replace(/[・~〜]/g, '-').trim();
    if (cleaned === pk || cleaned === pl) return p.key;
  }

  return { error: `Unknown period: ${s}` };
}

const HEADER_ALIASES = new Map([
  ['date', 'date'], ['日付', 'date'], ['年月日', 'date'],
  ['dayofweek', 'dayOfWeek'], ['weekday', 'dayOfWeek'], ['day', 'dayOfWeek'], ['曜日', 'dayOfWeek'],
  ['period', 'period'], ['時限', 'period'], ['限', 'period'], ['コマ', 'period'],
  ['subject', 'subject'], ['科目', 'subject'], ['教科', 'subject'], ['授業', 'subject'], ['授業名', 'subject'],
  ['teacher', 'teacher'], ['教員', 'teacher'], ['担当', 'teacher'], ['担当者', 'teacher'], ['先生', 'teacher'],
  ['room', 'room'], ['教室', 'room'], ['場所', 'room'],
  ['note', 'note'], ['メモ', 'note'], ['備考', 'note'],
  ['status', 'status'], ['状態', 'status'], ['種別', 'status'],
  ['grade', 'grade'], ['学年', 'grade'],
  ['course', 'course'], ['コース', 'course'], ['クラス', 'course'],
]);

function enumerateDatesInRange(startIso, endIso) {
  if (!isValidIsoDate(startIso) || !isValidIsoDate(endIso) || startIso > endIso) {
    bad('dateRange must have valid start <= end YYYY-MM-DD dates.', {
      reason: ERROR_REASONS.invalidDateRange,
    });
  }
  const start = new Date(`${startIso}T00:00:00Z`);
  const end = new Date(`${endIso}T00:00:00Z`);
  const diffDays = Math.round((end.getTime() - start.getTime()) / 86_400_000) + 1;
  if (diffDays > MAX_IMPORT_RANGE_DAYS) {
    bad(`dateRange cannot exceed ${MAX_IMPORT_RANGE_DAYS} days.`, {
      reason: ERROR_REASONS.rangeTooLarge,
    });
  }
  const out = [];
  for (let i = 0; i < diffDays; i++) {
    const dt = new Date(start.getTime() + i * 86_400_000);
    out.push(dt.toISOString().slice(0, 10));
  }
  return out;
}

/**
 * Validates and expands normalized slot objects into `{ slotsByDate, invalidRows }`.
 */
function parseTabularObjects(objects, { grade, course, schoolPeriods, dateRange, fiscalYear }) {
  if (objects.length > MAX_IMPORT_ROWS) {
    bad(`Import exceeds maximum row limit (${MAX_IMPORT_ROWS}).`);
  }

  const parsedRecords = [];
  const invalidRows = [];
  const pushInvalid = (rowNum, reason) => {
    if (invalidRows.length < MAX_INVALID_ROWS_RETURNED) {
      invalidRows.push({ row: rowNum, reason });
    }
  };

  for (let idx = 0; idx < objects.length; idx++) {
    const raw = objects[idx];
    const rowNum = Number.isInteger(raw?.__row) ? raw.__row : idx + 1;
    if (!raw || typeof raw !== 'object') {
      pushInvalid(rowNum, 'Row must be an object.');
      continue;
    }
    const rowGradeRaw = raw.grade !== undefined && raw.grade !== '' ? normText(raw.grade).replace(/年生$/, '') : '';
    const rowCourseRaw = raw.course !== undefined && raw.course !== '' ? normText(raw.course) : '';
    if (rowGradeRaw) {
      const gNum = Number.parseInt(rowGradeRaw, 10);
      if (gNum !== grade) continue;
    }
    if (rowCourseRaw && rowCourseRaw !== course) continue;

    const subject = normText(raw.subject).slice(0, 100);
    if (!subject) {
      if (normText(raw.period) || normText(raw.date) || normText(raw.dayOfWeek)) {
        pushInvalid(rowNum, 'Subject is empty.');
      }
      continue;
    }

    const period = tryResolvePeriodKey(raw.period, schoolPeriods);
    if (typeof period !== 'string') {
      pushInvalid(rowNum, period.error);
      continue;
    }

    let dateStr = null;
    if (raw.date !== undefined && normText(raw.date) !== '') {
      const normalized = tryNormalizeDateString(raw.date, fiscalYear);
      if (typeof normalized === 'string') {
        dateStr = normalized;
      } else {
        pushInvalid(rowNum, normalized.error);
        continue;
      }
    }

    const hasWeekdayInput = raw.dayOfWeek !== undefined && normText(raw.dayOfWeek) !== '';
    const weekday = hasWeekdayInput ? normalizeWeekday(raw.dayOfWeek) : null;
    if (hasWeekdayInput && !weekday) {
      pushInvalid(rowNum, `Invalid dayOfWeek: ${normText(raw.dayOfWeek).slice(0, 20)}`);
      continue;
    }

    if (!dateStr && !weekday) {
      pushInvalid(rowNum, 'Row must specify either date or dayOfWeek.');
      continue;
    }

    const teacher = normText(raw.teacher).slice(0, 100);
    const room = normText(raw.room).slice(0, 100);
    const note = normText(raw.note).slice(0, 200);
    const status = normalizeStatus(raw.status);

    parsedRecords.push({
      date: dateStr,
      dayOfWeek: weekday,
      slot: { period, subject, teacher, room, note, status },
    });
  }

  const needsRange = parsedRecords.some((r) => !r.date);
  let rangeDates = null;
  if (dateRange) {
    rangeDates = enumerateDatesInRange(dateRange.start, dateRange.end);
  } else if (needsRange) {
    bad('dateRange is required when importing a weekly template (dayOfWeek).');
  }

  const slotsByDate = new Map();
  const addSlot = (iso, slot) => {
    if (!slotsByDate.has(iso)) slotsByDate.set(iso, new Map());
    slotsByDate.get(iso).set(slot.period, slot);
  };

  for (const rec of parsedRecords) {
    if (rec.date) {
      if (dateRange && (rec.date < dateRange.start || rec.date > dateRange.end)) {
        continue;
      }
      addSlot(rec.date, rec.slot);
    } else if (rec.dayOfWeek && rangeDates) {
      for (const iso of rangeDates) {
        const dow = WEEKDAY_KANJI_BY_UTC_DAY[new Date(`${iso}T00:00:00Z`).getUTCDay()];
        if (dow === rec.dayOfWeek) {
          addSlot(iso, rec.slot);
        }
      }
    }
  }

  return {
    slotsByDate: new Map(
      [...slotsByDate.entries()].map(([iso, map]) => [iso, [...map.values()]]),
    ),
    invalidRows,
  };
}

/**
 * Tries to parse a flat tabular sheet with a header row containing
 * `(date|dayOfWeek), period, subject`. Returns `null` if headers don't match.
 */
function tryParseFlatHeaderTable(rows, opts) {
  if (!Array.isArray(rows) || rows.length < 2) return null;
  if (rows.length > MAX_IMPORT_ROWS) {
    bad(`File exceeds maximum row limit (${MAX_IMPORT_ROWS}).`);
  }

  const headerRow = rows[0].map((h) => HEADER_ALIASES.get(normText(h).toLowerCase().replace(/\s+/g, '')) ?? null);
  const hasDate = headerRow.includes('date') || headerRow.includes('dayOfWeek');
  const hasPeriod = headerRow.includes('period');
  const hasSubject = headerRow.includes('subject');
  if (!hasDate || !hasPeriod || !hasSubject) {
    return null;
  }

  const objects = [];
  for (let i = 1; i < rows.length; i++) {
    const r = rows[i];
    if (!r || r.every((c) => normText(c) === '')) continue;
    const obj = { __row: i + 1 };
    for (let c = 0; c < headerRow.length; c++) {
      const key = headerRow[c];
      if (key) obj[key] = r[c] ?? '';
    }
    objects.push(obj);
  }
  return parseTabularObjects(objects, opts);
}

const CELL_ROOM_RE = /^(.*?)【(.*?)】(.*)$/;
const SKIP_GRID_CELLS = new Set(['', '-', '―', 'ー', '空き', '空きコマ', '休憩', '昼休み']);

function parseGridCellValue(raw) {
  const s = normText(raw);
  if (SKIP_GRID_CELLS.has(s)) return null;
  const bracket = CELL_ROOM_RE.exec(s);
  if (bracket) {
    const left = bracket[1].trim();
    const room = bracket[2].trim();
    const rest = bracket[3].trim();
    const parts = left.split(/\s+/).filter(Boolean);
    const subject = parts[0] ?? left;
    const teacher = parts.slice(1).join(' ');
    return {
      subject: subject.slice(0, 100),
      teacher: teacher.slice(0, 100),
      room: room.slice(0, 100),
      note: rest.slice(0, 200),
      status: s.includes('休講') ? 'cancelled' : 'normal',
    };
  }
  const tokens = s.split(/\s+/);
  let subject = tokens[0] ?? s;
  let teacher = '';
  if (tokens.length >= 2 && /先生|教員/.test(tokens[1])) {
    teacher = tokens[1];
  } else if (tokens.length >= 2) {
    subject = tokens.join(' ');
  }
  return {
    subject: subject.slice(0, 100),
    teacher: teacher.slice(0, 100),
    room: '',
    note: '',
    status: s.includes('休講') ? 'cancelled' : 'normal',
  };
}

/**
 * Tries to parse a 2D weekly/date grid where columns are weekdays (`月..日`) or
 * dates (`4/14`, `2026-06-01`) and rows are periods (`1限..6限`). Returns `null`
 * if no clear header + period grid structure is found.
 */
function tryParseWeeklyMatrixGrid(rows, opts) {
  if (!Array.isArray(rows) || rows.length < 2) return null;
  const scanLimit = Math.min(rows.length - 1, 5);
  let headerRowIdx = -1;
  let colMap = null; // colIndex -> { date?, dayOfWeek? }

  for (let r = 0; r < scanLimit; r++) {
    const candidate = new Map();
    for (let c = 0; c < rows[r].length; c++) {
      const cell = normText(rows[r][c]);
      if (!cell) continue;
      // Avoid classifying numeric period-like headers as weekdays ("1"..'5')
      const weekday = /^[0-9]+$/.test(cell) ? null : normalizeWeekday(cell);
      if (weekday) {
        candidate.set(c, { dayOfWeek: weekday });
        continue;
      }
      const dateVal = tryNormalizeDateString(cell, opts.fiscalYear);
      if (typeof dateVal === 'string') {
        candidate.set(c, { date: dateVal });
      }
    }
    if (candidate.size >= 2) {
      headerRowIdx = r;
      colMap = candidate;
      break;
    }
  }
  if (headerRowIdx === -1 || !colMap) return null;

  const firstHeaderCol = Math.min(...colMap.keys());
  const labelColCandidates = [];
  for (let c = 0; c < firstHeaderCol; c++) labelColCandidates.push(c);
  if (labelColCandidates.length === 0) labelColCandidates.push(0);

  const objects = [];
  let matchedPeriodRows = 0;

  for (let r = headerRowIdx + 1; r < rows.length; r++) {
    const row = rows[r];
    if (!row) continue;
    let periodKey = null;
    for (const lc of labelColCandidates) {
      const candidate = normText(row[lc]);
      if (!candidate) continue;
      const resolved = tryResolvePeriodKey(candidate, opts.schoolPeriods);
      if (typeof resolved === 'string') {
        periodKey = resolved;
        break;
      }
    }
    if (!periodKey) continue;
    matchedPeriodRows += 1;

    for (const [colIdx, colMeta] of colMap.entries()) {
      if (colIdx >= row.length) continue;
      const cell = parseGridCellValue(row[colIdx]);
      if (!cell || !cell.subject) continue;
      objects.push({
        __row: r + 1,
        ...colMeta,
        period: periodKey,
        ...cell,
      });
    }
  }

  if (matchedPeriodRows < 1 || objects.length === 0) return null;
  return parseTabularObjects(objects, opts);
}

/**
 * Sends ONLY text (never raw image/PDF bytes) through `callGeminiSafely` to
 * extract timetable entries from unfamiliar layouts, then validates every row.
 */
async function parseTimetableWithAi({
  text,
  grade,
  course,
  schoolPeriods,
  dateRange,
  fiscalYear,
  auth,
  db,
  generateContent,
  createMessage,
}) {
  const clipped = String(text ?? '').trim().slice(0, MAX_AI_IMPORT_CHARS);
  if (!clipped) {
    bad('No readable timetable text was found in the uploaded file.');
  }

  const periodDesc = schoolPeriods
    .map((p) => `${p.key} (${p.label}: ${p.start}-${p.end})`)
    .join(', ');

  const systemInstruction = [
    'You extract structured school timetable entries from untrusted document text.',
    `Target class: Grade ${grade}, Course ${course}.`,
    `Allowed period keys: ${periodDesc}.`,
    'Return ONLY valid JSON matching:',
    '{"slots":[{"date":"YYYY-MM-DD (optional if weekly)","dayOfWeek":"月|火|水|木|金|土|日 (required if no date)","period":"period key","subject":"...","teacher":"...","room":"...","note":"...","status":"normal|cancelled|event|tbd|elective"}]}',
    'Preserve any privacy tokens like [TEACHER_1] or [PERSON_1] verbatim.',
    'Do not invent lessons that are not in the input.',
  ].join('\n');

  const prompt = [
    dateRange ? `Selected date range: ${dateRange.start} to ${dateRange.end}` : 'Use dates from the file.',
    `Document content:\n${clipped}`,
  ].join('\n\n');

  const gatewayOpts = {
    auth,
    db,
    mapError: mapAiError,
    functionName: 'previewTimetableImport',
    japaneseFallback: '時間割の解析に失敗しました。もう一度お試しください。',
  };
  if (typeof generateContent === 'function') {
    gatewayOpts.generateContent = generateContent;
  }
  if (typeof createMessage === 'function') {
    gatewayOpts.createMessage = createMessage;
  }

  const aiResp = await callAiSafely(
    {
      task: 'previewTimetableImport',
      systemInstruction,
      contents: prompt,
      responseFormat: 'json',
    },
    gatewayOpts,
  );

  const parsedJson = extractJsonObject(aiResp.text ?? '');
  const rawSlots = Array.isArray(parsedJson?.slots)
    ? parsedJson.slots
    : (Array.isArray(parsedJson?.days)
        ? parsedJson.days.flatMap((d) =>
            (Array.isArray(d?.slots) ? d.slots : []).map((s) => ({
              ...s,
              date: s?.date ?? d?.date,
            })),
          )
        : null);

  if (!rawSlots) {
    bad('AI could not extract structured timetable rows from this file.');
  }

  const validated = parseTabularObjects(
    rawSlots.map((s, idx) => ({ ...(s && typeof s === 'object' ? s : {}), __row: idx + 1 })),
    { grade, course, schoolPeriods, dateRange, fiscalYear },
  );

  return {
    slotsByDate: validated.slotsByDate,
    invalidRows: validated.invalidRows,
    detectedPeriods: null,
    parseMethod: 'ai',
    usedAi: true,
    maskedPreviewText: typeof aiResp.maskedContents === 'string'
      ? aiResp.maskedContents.slice(0, MAX_AI_IMPORT_CHARS)
      : null,
  };
}

function detectFormat(mimeType, fileName) {
  const mime = String(mimeType ?? '').toLowerCase();
  const name = String(fileName ?? '').toLowerCase();
  if (HEIC_MIME_TYPES.has(mime) || name.endsWith('.heic') || name.endsWith('.heif')) {
    throw new HttpsError(
      'invalid-argument',
      'HEIC/HEIF形式の画像は非対応です。JPGまたはPNGに変換してからアップロードしてください。',
      { reason: ERROR_REASONS.unsupportedHeic },
    );
  }
  if (
    mime === 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' ||
    name.endsWith('.xlsx')
  ) {
    return 'xlsx';
  }
  if (
    mime === 'text/csv' ||
    mime === 'application/csv' ||
    (mime === 'text/plain' && name.endsWith('.csv')) ||
    name.endsWith('.csv')
  ) {
    return 'csv';
  }
  if (mime === 'application/pdf' || name.endsWith('.pdf')) {
    return 'pdf';
  }
  if (
    REDACTABLE_IMAGE_MIMES.has(mime) ||
    /\.(jpe?g|png|webp)$/i.test(name)
  ) {
    return 'image';
  }
  bad('Unsupported timetable file type. Please upload XLSX, CSV, PDF, or JPG/PNG/WebP.');
}

function mimeForImageFormat(mimeType, fileName) {
  const m = String(mimeType ?? '').toLowerCase();
  if (REDACTABLE_IMAGE_MIMES.has(m)) return m;
  const n = String(fileName ?? '').toLowerCase();
  if (n.endsWith('.png')) return 'image/png';
  if (n.endsWith('.webp')) return 'image/webp';
  return 'image/jpeg';
}

function resolveFromGridRows(gridRows, opts, { methodName }) {
  const flat = tryParseFlatHeaderTable(gridRows, opts);
  if (flat) {
    return {
      slotsByDate: flat.slotsByDate,
      invalidRows: flat.invalidRows,
      detectedPeriods: null,
      parseMethod: methodName,
      usedAi: false,
      maskedPreviewText: null,
    };
  }
  const weekly = tryParseWeeklyMatrixGrid(gridRows, opts);
  if (weekly) {
    return {
      slotsByDate: weekly.slotsByDate,
      invalidRows: weekly.invalidRows,
      detectedPeriods: null,
      parseMethod: methodName,
      usedAi: false,
      maskedPreviewText: null,
    };
  }
  return null;
}

/**
 * Parses an uploaded `.xlsx`, `.csv`, `.pdf`, or image buffer into
 * `{ slotsByDate, invalidRows, detectedPeriods, parseMethod, usedAi, maskedPreviewText }`.
 */
export async function parseTimetableImportFile({
  buffer,
  mimeType,
  fileName,
  grade,
  course,
  schoolPeriods,
  dateRange = null,
  fiscalYear = new Date().getUTCFullYear(),
  auth = null,
  db = null,
  visionClient,
  generateContent,
  createMessage,
}) {
  if (!Buffer.isBuffer(buffer) || buffer.length === 0) {
    bad('Uploaded file is empty.');
  }
  if (buffer.length > MAX_IMPORT_FILE_BYTES) {
    bad('Uploaded file exceeds 10MB limit.', { reason: ERROR_REASONS.fileTooLarge });
  }

  const format = detectFormat(mimeType, fileName);
  const tabularOpts = { grade, course, schoolPeriods, dateRange, fiscalYear };

  if (format === 'xlsx') {
    validateXlsxZip(buffer);
    const wb = new ExcelJS.Workbook();
    await wb.xlsx.load(buffer);
    if (wb.worksheets.length === 0) {
      bad('XLSX workbook has no worksheets.');
    }
    if (wb.worksheets.length > MAX_IMPORT_SHEETS) {
      bad(`XLSX workbook exceeds maximum sheet limit (${MAX_IMPORT_SHEETS}).`);
    }

    const firstSheet = wb.worksheets[0];
    if (firstSheet.rowCount > MAX_IMPORT_ROWS) {
      bad(`XLSX worksheet exceeds maximum row limit (${MAX_IMPORT_ROWS}).`);
    }

    // 1) Try EduPlanner's existing school-wide matrix format on the first sheet.
    const gridRows = [];
    for (let r = 1; r <= firstSheet.rowCount; r++) {
      const row = [];
      for (let c = 1; c <= firstSheet.columnCount; c++) {
        const cell = firstSheet.getCell(r, c);
        row.push(cell.isMerged && cell.master !== cell ? '' : cellValueToGridString(cell.value));
      }
      gridRows.push(row);
    }
    gridRows.sheetName = firstSheet.name;

    try {
      const parsedGrid = parseTimetableRows(gridRows, { fileName });
      const matchingDays = parsedGrid.days.filter(
        (d) => Number(d.grade) === Number(grade) && String(d.course) === String(course),
      );
      if (matchingDays.length === 0) {
        bad('Target grade/course was not found in the uploaded timetable.');
      }
      const map = new Map();
      for (const day of matchingDays) {
        if (dateRange && (day.date < dateRange.start || day.date > dateRange.end)) {
          continue;
        }
        map.set(day.date, day.slots);
      }
      return {
        slotsByDate: map,
        invalidRows: [],
        detectedPeriods: parsedGrid.periods,
        parseMethod: 'school_matrix',
        usedAi: false,
        maskedPreviewText: null,
      };
    } catch (err) {
      if (err instanceof HttpsError) throw err;
      if (!(err instanceof TimetableParseError)) throw err;
    }

    // 2) Deterministic header_mapper / weekly grid across worksheets
    let totalRows = 0;
    const mergedSlotsByDate = new Map();
    const allInvalidRows = [];
    let matchedStructuredSheet = false;
    const sheetTexts = [];

    for (const ws of wb.worksheets) {
      totalRows += ws.rowCount;
      if (totalRows > MAX_IMPORT_ROWS) {
        bad(`XLSX exceeds maximum row limit (${MAX_IMPORT_ROWS}).`);
      }
      if (ws.rowCount < 1) continue;
      const flatRows = [];
      for (let r = 1; r <= ws.rowCount; r++) {
        const row = [];
        for (let c = 1; c <= ws.columnCount; c++) {
          const cell = ws.getCell(r, c);
          row.push(cell.isMerged && cell.master !== cell ? '' : cellValueToString(cell.value));
        }
        flatRows.push(row);
      }
      sheetTexts.push(gridToText(flatRows));
      const resolved = resolveFromGridRows(flatRows, tabularOpts, { methodName: 'header_mapper' });
      if (resolved) {
        matchedStructuredSheet = true;
        for (const [iso, slots] of resolved.slotsByDate.entries()) {
          if (!mergedSlotsByDate.has(iso)) mergedSlotsByDate.set(iso, new Map());
          const m = mergedSlotsByDate.get(iso);
          for (const s of slots) m.set(s.period, s);
        }
        allInvalidRows.push(...resolved.invalidRows);
      }
    }

    if (matchedStructuredSheet) {
      return {
        slotsByDate: new Map(
          [...mergedSlotsByDate.entries()].map(([iso, m]) => [iso, [...m.values()]]),
        ),
        invalidRows: allInvalidRows.slice(0, MAX_INVALID_ROWS_RETURNED),
        detectedPeriods: null,
        parseMethod: 'header_mapper',
        usedAi: false,
        maskedPreviewText: null,
      };
    }

    // 3) AI fallback for unknown XLSX layout (text only)
    return parseTimetableWithAi({
      text: sheetTexts.join('\n\n'),
      grade,
      course,
      schoolPeriods,
      dateRange,
      fiscalYear,
      auth,
      db,
      generateContent,
      createMessage,
    });
  }

  if (format === 'csv') {
    const { text } = decodeCsvBuffer(buffer);
    const csvRows = parseCsvRows(text);
    const resolved = resolveFromGridRows(csvRows, tabularOpts, { methodName: 'header_mapper' });
    if (resolved) return resolved;

    return parseTimetableWithAi({
      text: gridToText(csvRows),
      grade,
      course,
      schoolPeriods,
      dateRange,
      fiscalYear,
      auth,
      db,
      generateContent,
      createMessage,
    });
  }

  if (format === 'image') {
    const imgMime = mimeForImageFormat(mimeType, fileName);
    const ocrOpts = {};
    if (visionClient) ocrOpts.visionClient = visionClient;
    const ocrResult = await ocrImageDocument(buffer, imgMime, ocrOpts);
    const tokens = visionWordsToTokens(ocrResult.fullTextAnnotation);
    if (tokens.length === 0) {
      bad('No readable text was detected in the timetable image.');
    }
    const gridRows = reconstructGrid(tokens);
    try {
      const schoolParsed = parseTimetableRows(gridRows, { fileName });
      const matchingDays = schoolParsed.days.filter(
        (d) => Number(d.grade) === Number(grade) && String(d.course) === String(course),
      );
      if (matchingDays.length > 0) {
        const map = new Map();
        for (const day of matchingDays) {
          if (dateRange && (day.date < dateRange.start || day.date > dateRange.end)) continue;
          map.set(day.date, day.slots);
        }
        return {
          slotsByDate: map,
          invalidRows: [],
          detectedPeriods: schoolParsed.periods,
          parseMethod: 'school_matrix',
          usedAi: false,
          maskedPreviewText: null,
        };
      }
    } catch (err) {
      if (err instanceof HttpsError) throw err;
      if (!(err instanceof TimetableParseError)) throw err;
    }

    const ocrResolved = resolveFromGridRows(gridRows, tabularOpts, { methodName: 'ocr_grid' });
    if (ocrResolved) return ocrResolved;

    // Unknown image grid layout -> send ONLY masked OCR text to Gemini (never the image)
    return parseTimetableWithAi({
      text: gridToText(gridRows),
      grade,
      course,
      schoolPeriods,
      dateRange,
      fiscalYear,
      auth,
      db,
      generateContent,
      createMessage,
    });
  }

  // PDF format: reuse Stage 3 extractPdfText (handles CMap + scanned_pdf rejection)
  const pdfResult = await extractPdfText(buffer, {
    maxChars: MAX_AI_IMPORT_CHARS,
    includeItems: true,
  });
  const allPdfTokens = (pdfResult.pageItems ?? []).flat();
  const pdfGrid = reconstructGrid(allPdfTokens);

  if (pdfGrid.length >= 2) {
    const pdfResolved = resolveFromGridRows(pdfGrid, tabularOpts, { methodName: 'ocr_grid' });
    if (pdfResolved) return pdfResolved;
  }

  return parseTimetableWithAi({
    text: pdfGrid.length > 0 ? gridToText(pdfGrid) : pdfResult.text,
    grade,
    course,
    schoolPeriods,
    dateRange,
    fiscalYear,
    auth,
    db,
    generateContent,
    createMessage,
  });
}

/**
 * Classifies whether a `YYYY-MM-DD` date is excluded by manual selection,
 * `policy.timetableImport.schoolDays`, Japanese national holidays, or
 * `policy.timetableImport.closedDateRanges`.
 */
export function exclusionReasonForDate(isoDate, policy, manualExcludedSet) {
  if (manualExcludedSet?.has(isoDate)) {
    return { date: isoDate, reason: 'manual', label: '', provisional: false };
  }

  const dow = WEEKDAY_KANJI_BY_UTC_DAY[new Date(`${isoDate}T00:00:00Z`).getUTCDay()];
  const schoolDays = policy?.timetableImport?.schoolDays ?? ['月', '火', '水', '木', '金'];
  if (!schoolDays.includes(dow)) {
    return { date: isoDate, reason: 'non_school_day', label: dow, provisional: false };
  }

  if (policy?.timetableImport?.excludeNationalHolidays !== false) {
    const holidayInfo = getJapaneseHolidayInfo(isoDate);
    if (holidayInfo) {
      return {
        date: isoDate,
        reason: 'national_holiday',
        label: holidayInfo.name,
        provisional: holidayInfo.provisional,
      };
    }
  }

  const ranges = policy?.timetableImport?.closedDateRanges ?? [];
  for (const r of ranges) {
    if (r.start <= isoDate && isoDate <= r.end) {
      return { date: isoDate, reason: 'closed_range', label: r.label || '', provisional: false };
    }
  }

  return null;
}

function slotEquals(a, b) {
  return (
    (a.subject ?? '') === (b.subject ?? '') &&
    (a.teacher ?? '') === (b.teacher ?? '') &&
    (a.room ?? '') === (b.room ?? '') &&
    (a.note ?? '') === (b.note ?? '') &&
    (a.status ?? 'normal') === (b.status ?? 'normal')
  );
}

function sortSlotsByPeriod(slots, schoolPeriods) {
  const order = new Map(schoolPeriods.map((p, idx) => [p.key, idx]));
  return [...slots].sort((a, b) => {
    const ia = order.get(a.period) ?? Number.MAX_SAFE_INTEGER;
    const ib = order.get(b.period) ?? Number.MAX_SAFE_INTEGER;
    if (ia !== ib) return ia - ib;
    return String(a.period).localeCompare(String(b.period));
  });
}

function normalizeDateRangeInput(dateRange) {
  if (dateRange === undefined || dateRange === null) return null;
  if (typeof dateRange !== 'object' || Array.isArray(dateRange)) {
    bad('dateRange must be an object with start and end.');
  }
  enumerateDatesInRange(dateRange.start, dateRange.end);
  return { start: dateRange.start, end: dateRange.end };
}

function normalizeExcludedDatesInput(excludedDates) {
  if (excludedDates === undefined || excludedDates === null) return [];
  if (!Array.isArray(excludedDates)) bad('excludedDates must be an array.');
  if (excludedDates.length > MAX_IMPORT_RANGE_DAYS) {
    bad(`excludedDates cannot exceed ${MAX_IMPORT_RANGE_DAYS} items.`);
  }
  const out = [];
  const seen = new Set();
  for (const d of excludedDates) {
    if (!isValidIsoDate(d)) bad(`Invalid excluded date: ${d}`);
    if (!seen.has(d)) {
      seen.add(d);
      out.push(d);
    }
  }
  return out;
}

/**
 * Parses an uploaded timetable file, applies school policy exclusions
 * (national holidays, closedDateRanges, schoolDays, manual excludedDates),
 * computes per-day diff & `baseHash`, and persists a short-lived draft
 * (30 min TTL) in `timetable_import_drafts/{draftId}`.
 */
export async function previewTimetableImport(
  domain,
  school,
  auth,
  data,
  { db, now = () => new Date(), visionClient, generateContent, createMessage } = {},
) {
  const uid = auth?.uid;
  const email = String(auth?.token?.email ?? '').trim().toLowerCase();
  if (!uid || !isTeacher(school, uid, email)) {
    throw new HttpsError('permission-denied', 'Not a teacher of this school.');
  }

  const grade = Number(data?.grade);
  const course = typeof data?.course === 'string' ? data.course.trim() : '';
  const mode = data?.mode ?? 'merge';
  if (!(school?.grades ?? []).includes(grade)) bad('Unknown grade.');
  if (!(school?.courses ?? []).includes(course)) bad('Unknown course.');
  if (mode !== 'merge' && mode !== 'replace') bad('mode must be merge or replace.');

  const fileBase64 = data?.fileBase64;
  if (typeof fileBase64 !== 'string' || fileBase64.length === 0) {
    bad('fileBase64 is required.');
  }
  if (fileBase64.length > MAX_IMPORT_FILE_BYTES * 1.4) {
    bad('File exceeds 10MB limit.', { reason: ERROR_REASONS.fileTooLarge });
  }

  const dateRange = normalizeDateRangeInput(data?.dateRange);
  const manualExcluded = normalizeExcludedDatesInput(data?.excludedDates);
  const manualExcludedSet = new Set(manualExcluded);

  const policy = await loadSchoolPolicy(domain, { db });
  if (!canUserImportTimetable(school, policy, uid, email, grade, course)) {
    throw new HttpsError('permission-denied', 'Not permitted to import timetable for this class.');
  }
  if (mode === 'replace' && !canUserUseReplaceMode(school, policy, uid)) {
    throw new HttpsError('permission-denied', 'Replace mode is not permitted by school policy.', {
      reason: ERROR_REASONS.policyDisallowsReplace,
    });
  }

  const schoolPeriods = resolveSchoolPeriods(school);
  const fiscalYear = dateRange
    ? (() => {
        const [y, m] = dateRange.start.split('-').map(Number);
        return m >= 4 ? y : y - 1;
      })()
    : (() => {
        const dt = now();
        const m = dt.getUTCMonth() + 1;
        return m >= 4 ? dt.getUTCFullYear() : dt.getUTCFullYear() - 1;
      })();

  let buffer = Buffer.from(fileBase64, 'base64');
  let parsed;
  try {
    parsed = await parseTimetableImportFile({
      buffer,
      mimeType: data?.mimeType,
      fileName: data?.fileName,
      grade,
      course,
      schoolPeriods,
      dateRange,
      fiscalYear,
      auth,
      db,
      visionClient,
      generateContent,
      createMessage,
    });
  } finally {
    buffer = null;
  }

  const candidateDatesSet = new Set(parsed.slotsByDate.keys());
  if (mode === 'replace' && dateRange) {
    for (const d of enumerateDatesInRange(dateRange.start, dateRange.end)) {
      candidateDatesSet.add(d);
    }
  }
  const candidateDates = [...candidateDatesSet].sort();

  const excludedDates = [];
  const activeDates = [];
  for (const iso of candidateDates) {
    const excl = exclusionReasonForDate(iso, policy, manualExcludedSet);
    if (excl) {
      if (parsed.slotsByDate.has(iso) || excl.reason !== 'non_school_day') {
        excludedDates.push(excl);
      }
    } else {
      activeDates.push(iso);
    }
  }

  if (
    activeDates.length === 0 &&
    parsed.slotsByDate.size === 0 &&
    parsed.invalidRows.length === 0
  ) {
    bad('No matching lessons found in the uploaded file.');
  }

  const dayRefs = activeDates.map((date) =>
    db.collection('school_days').doc(dayDocId(domain, { grade, course, date })),
  );
  const existingSnaps = [];
  for (let i = 0; i < dayRefs.length; i += BATCH_CHUNK_SIZE) {
    const chunk = dayRefs.slice(i, i + BATCH_CHUNK_SIZE);
    if (chunk.length > 0) {
      existingSnaps.push(...(await db.getAll(...chunk)));
    }
  }

  const draftDays = [];
  const diffPreview = [];
  const summary = { added: 0, updated: 0, removed: 0, unchanged: 0 };

  activeDates.forEach((date, idx) => {
    const snap = existingSnaps[idx];
    const oldData = snap?.exists ? (snap.data() ?? {}) : null;
    const existingSlots = Array.isArray(oldData?.slots) ? oldData.slots : [];
    const baseHash = oldData ? (oldData.hash ?? slotsHash(existingSlots)) : null;

    const importedSlots = parsed.slotsByDate.get(date) ?? [];
    let targetSlots;
    if (mode === 'merge') {
      const mergedMap = new Map(existingSlots.map((s) => [s.period, s]));
      for (const imp of importedSlots) {
        mergedMap.set(imp.period, imp);
      }
      targetSlots = sortSlotsByPeriod([...mergedMap.values()], schoolPeriods);
    } else {
      targetSlots = sortSlotsByPeriod(importedSlots, schoolPeriods);
    }

    const targetHash = slotsHash(targetSlots);
    const shouldWrite =
      oldData !== null ? targetHash !== baseHash : targetSlots.length > 0;

    const oldByPeriod = new Map(existingSlots.map((s) => [s.period, s]));
    const newByPeriod = new Map(targetSlots.map((s) => [s.period, s]));
    for (const pKey of new Set([...oldByPeriod.keys(), ...newByPeriod.keys()])) {
      const before = oldByPeriod.get(pKey) ?? null;
      const after = newByPeriod.get(pKey) ?? null;
      let kind;
      if (!before && after) {
        kind = 'added';
        summary.added += 1;
      } else if (before && !after) {
        kind = 'removed';
        summary.removed += 1;
      } else if (before && after && !slotEquals(before, after)) {
        kind = 'updated';
        summary.updated += 1;
      } else {
        kind = 'unchanged';
        summary.unchanged += 1;
      }
      if (kind !== 'unchanged' && diffPreview.length < DIFF_PREVIEW_LIMIT) {
        diffPreview.push({
          date,
          period: pKey,
          kind,
          before: before ? { subject: before.subject, teacher: before.teacher, room: before.room, status: before.status } : null,
          after: after ? { subject: after.subject, teacher: after.teacher, room: after.room, status: after.status } : null,
        });
      }
    }

    if (shouldWrite) {
      draftDays.push({
        dayId: dayDocId(domain, { grade, course, date }),
        date,
        slots: targetSlots,
        hash: targetHash,
        baseHash,
      });
    }
  });

  const createdAt = now();
  const expiresAt = new Date(createdAt.getTime() + DRAFT_TTL_MS);
  const draftId = `${domain}_${randomUUID()}`;
  const periodsToPersist =
    Array.isArray(school?.periods) && school.periods.length > 0
      ? null
      : (parsed.detectedPeriods?.length ? parsed.detectedPeriods : schoolPeriods);

  await db.collection('timetable_import_drafts').doc(draftId).set({
    domain,
    grade,
    course,
    mode,
    parseMethod: parsed.parseMethod,
    usedAi: parsed.usedAi,
    createdBy: uid,
    createdByEmail: email,
    createdAt,
    expiresAt,
    confirmed: false,
    summary,
    excludedDates,
    invalidRows: parsed.invalidRows,
    days: draftDays,
    periodsToPersist,
  });

  logger.info('Timetable import preview generated', {
    domain,
    grade,
    course,
    mode,
    parseMethod: parsed.parseMethod,
    usedAi: parsed.usedAi,
    changedDaysCount: draftDays.length,
    excludedCount: excludedDates.length,
    invalidRowsCount: parsed.invalidRows.length,
    added: summary.added,
    updated: summary.updated,
    removed: summary.removed,
  });

  return {
    draftId,
    expiresAt: expiresAt.toISOString(),
    mode,
    grade,
    course,
    parseMethod: parsed.parseMethod,
    usedAi: parsed.usedAi,
    maskedPreviewText: parsed.maskedPreviewText,
    invalidRows: parsed.invalidRows,
    summary,
    changedDaysCount: draftDays.length,
    diffPreview,
    excludedDates,
    notifyStudentsDefault: policy.timetableImport.notifyStudentsDefault,
  };
}

/**
 * Confirms a preview draft under CURRENT school policy permissions, verifies
 * optimistic concurrency (`baseHash === currentHash`), writes undo history into
 * `timetable_import_history/{importId}` (30d TTL), commits `school_days`
 * (chunked for >400 docs), and optionally sends 1 combined push notification.
 */
export async function confirmTimetableImport(
  domain,
  school,
  auth,
  data,
  { db, now = () => new Date(), notifyClass } = {},
) {
  const uid = auth?.uid;
  const email = String(auth?.token?.email ?? '').trim().toLowerCase();
  if (!uid || !isTeacher(school, uid, email)) {
    throw new HttpsError('permission-denied', 'Not a teacher of this school.');
  }

  const draftId = typeof data?.draftId === 'string' ? data.draftId.trim() : '';
  if (!draftId) bad('draftId is required.');
  const extraExcludedSet = new Set(normalizeExcludedDatesInput(data?.excludedDates));

  const draftRef = db.collection('timetable_import_drafts').doc(draftId);
  const [draftSnap, policy] = await Promise.all([
    draftRef.get(),
    loadSchoolPolicy(domain, { db }),
  ]);

  if (!draftSnap.exists) {
    throw new HttpsError('not-found', 'Import preview draft not found.', {
      reason: ERROR_REASONS.draftExpiredOrNotFound,
    });
  }
  const draft = draftSnap.data();
  if (draft.domain !== domain) {
    throw new HttpsError('permission-denied', 'Draft belongs to another school.');
  }

  const isAdmin = (school?.admins ?? []).includes(uid);
  if (draft.createdBy !== uid && !isAdmin) {
    throw new HttpsError('permission-denied', 'Only the draft creator or an admin can confirm.');
  }
  if (draft.confirmed === true) {
    throw new HttpsError('failed-precondition', 'Import draft was already confirmed.');
  }

  const currentNow = now();
  const expiresAt = toDateObj(draft.expiresAt);
  if (!expiresAt || expiresAt.getTime() <= currentNow.getTime()) {
    throw new HttpsError('deadline-exceeded', 'Import preview has expired. Please upload again.', {
      reason: ERROR_REASONS.draftExpiredOrNotFound,
    });
  }

  // Re-check CURRENT school policy at confirm time (not draft-creation time).
  if (!canUserImportTimetable(school, policy, uid, email, draft.grade, draft.course)) {
    throw new HttpsError(
      'permission-denied',
      'Current school policy does not allow you to import this class timetable.',
      { reason: ERROR_REASONS.policyChanged },
    );
  }
  if (draft.mode === 'replace' && !canUserUseReplaceMode(school, policy, uid)) {
    throw new HttpsError(
      'permission-denied',
      'Replace mode is disabled by current school policy.',
      { reason: ERROR_REASONS.policyDisallowsReplace },
    );
  }

  const notifyStudents =
    typeof data?.notifyStudents === 'boolean'
      ? data.notifyStudents
      : Boolean(policy.timetableImport.notifyStudentsDefault);

  const activeDays = (draft.days ?? []).filter((d) => !extraExcludedSet.has(d.date));

  if (activeDays.length === 0) {
    await draftRef.set({ confirmed: true, confirmedAt: currentNow, importId: null }, { merge: true });
    return { ok: true, appliedDays: 0, importId: null, pushed: 0 };
  }

  const importId = `${domain}_${randomUUID()}`;
  const historyRef = db.collection('timetable_import_history').doc(importId);
  const historyExpiresAt = new Date(
    currentNow.getTime() + IMPORT_HISTORY_TTL_DAYS * 86_400_000,
  );
  const dayRefs = activeDays.map((d) => db.collection('school_days').doc(d.dayId));

  const buildHistoryPayload = (previousDays) => ({
    domain,
    grade: draft.grade,
    course: draft.course,
    mode: draft.mode,
    draftId,
    createdBy: uid,
    createdByEmail: email,
    createdAt: currentNow,
    expiresAt: historyExpiresAt,
    undoWindowDays: policy.timetableImport.undoWindowDays,
    reverted: false,
    dayIds: activeDays.map((d) => d.dayId),
    previousDays,
  });

  if (activeDays.length <= BATCH_CHUNK_SIZE) {
    await db.runTransaction(async (tx) => {
      const freshDraftSnap = await tx.get(draftRef);
      if (!freshDraftSnap.exists || freshDraftSnap.data()?.confirmed === true) {
        throw new HttpsError('failed-precondition', 'Import draft was already confirmed.');
      }

      const daySnaps = await Promise.all(dayRefs.map((ref) => tx.get(ref)));
      const previousDays = [];
      for (let i = 0; i < activeDays.length; i++) {
        const d = activeDays[i];
        const snap = daySnaps[i];
        const oldData = snap.exists ? (snap.data() ?? {}) : null;
        const oldSlots = Array.isArray(oldData?.slots) ? oldData.slots : [];
        const currentHash = oldData ? (oldData.hash ?? slotsHash(oldSlots)) : null;

        if (currentHash !== d.baseHash) {
          throw new HttpsError(
            'aborted',
            'Timetable changed since preview was generated.',
            { reason: ERROR_REASONS.timetableChanged, dayId: d.dayId, date: d.date },
          );
        }

        previousDays.push({
          dayId: d.dayId,
          date: d.date,
          existed: snap.exists,
          slots: oldSlots,
          hash: currentHash,
          afterHash: d.hash,
        });
      }

      tx.set(historyRef, buildHistoryPayload(previousDays));
      for (let i = 0; i < activeDays.length; i++) {
        const d = activeDays[i];
        tx.set(dayRefs[i], {
          domain,
          grade: draft.grade,
          course: draft.course,
          date: d.date,
          slots: d.slots,
          hash: d.hash,
          updatedAt: currentNow,
        });
      }
      tx.set(draftRef, { confirmed: true, confirmedAt: currentNow, importId }, { merge: true });
    });
  } else {
    const daySnaps = [];
    for (let i = 0; i < dayRefs.length; i += BATCH_CHUNK_SIZE) {
      daySnaps.push(...(await db.getAll(...dayRefs.slice(i, i + BATCH_CHUNK_SIZE))));
    }
    const previousDays = [];
    for (let i = 0; i < activeDays.length; i++) {
      const d = activeDays[i];
      const snap = daySnaps[i];
      const oldData = snap.exists ? (snap.data() ?? {}) : null;
      const oldSlots = Array.isArray(oldData?.slots) ? oldData.slots : [];
      const currentHash = oldData ? (oldData.hash ?? slotsHash(oldSlots)) : null;
      if (currentHash !== d.baseHash) {
        throw new HttpsError(
          'aborted',
          'Timetable changed since preview was generated.',
          { reason: ERROR_REASONS.timetableChanged, dayId: d.dayId, date: d.date },
        );
      }
      previousDays.push({
        dayId: d.dayId,
        date: d.date,
        existed: snap.exists,
        slots: oldSlots,
        hash: currentHash,
        afterHash: d.hash,
      });
    }

    await historyRef.set(buildHistoryPayload(previousDays));
    for (let i = 0; i < activeDays.length; i += BATCH_CHUNK_SIZE) {
      const batch = db.batch();
      const slice = activeDays.slice(i, i + BATCH_CHUNK_SIZE);
      slice.forEach((d, offset) => {
        batch.set(dayRefs[i + offset], {
          domain,
          grade: draft.grade,
          course: draft.course,
          date: d.date,
          slots: d.slots,
          hash: d.hash,
          updatedAt: currentNow,
        });
      });
      await batch.commit();
    }
    await draftRef.set({ confirmed: true, confirmedAt: currentNow, importId }, { merge: true });
  }

  if (Array.isArray(draft.periodsToPersist) && draft.periodsToPersist.length > 0 && !(school?.periods?.length > 0)) {
    await db.collection('schools').doc(domain).set(
      { periods: draft.periodsToPersist },
      { merge: true },
    );
  }

  let pushed = 0;
  if (notifyStudents && typeof notifyClass === 'function') {
    pushed = await notifyClass(
      draft.grade,
      draft.course,
      (lang) => ({
        title: pt(lang, 'push_tt_title_sync'),
        body: pt(lang, 'push_tt_import_summary', { n: activeDays.length }),
      }),
      '/timetable',
    );
  }

  logger.info('Timetable import confirmed', {
    domain,
    grade: draft.grade,
    course: draft.course,
    appliedDays: activeDays.length,
    pushed,
  });

  return { ok: true, appliedDays: activeDays.length, importId, pushed };
}

/**
 * Reverts a previously confirmed timetable import within the school's undo
 * window, checking CURRENT permissions and optimistic concurrency
 * (`currentHash === afterHash` for every affected day).
 */
export async function revertTimetableImport(
  domain,
  school,
  auth,
  data,
  { db, now = () => new Date() } = {},
) {
  const uid = auth?.uid;
  const email = String(auth?.token?.email ?? '').trim().toLowerCase();
  if (!uid || !isTeacher(school, uid, email)) {
    throw new HttpsError('permission-denied', 'Not a teacher of this school.');
  }

  const importId = typeof data?.importId === 'string' ? data.importId.trim() : '';
  if (!importId) bad('importId is required.');

  const historyRef = db.collection('timetable_import_history').doc(importId);
  const [historySnap, policy] = await Promise.all([
    historyRef.get(),
    loadSchoolPolicy(domain, { db }),
  ]);

  if (!historySnap.exists) {
    throw new HttpsError('not-found', 'Import history record not found.', {
      reason: ERROR_REASONS.draftExpiredOrNotFound,
    });
  }
  const history = historySnap.data();
  if (history.domain !== domain) {
    throw new HttpsError('permission-denied', 'Import history belongs to another school.');
  }

  const isAdmin = (school?.admins ?? []).includes(uid);
  if (!isAdmin) {
    if (history.createdBy !== uid) {
      throw new HttpsError('permission-denied', 'Only the importing teacher or an admin can revert.');
    }
    if (!canUserImportTimetable(school, policy, uid, email, history.grade, history.course)) {
      throw new HttpsError(
        'permission-denied',
        'Current school policy does not allow you to revert this class timetable.',
        { reason: ERROR_REASONS.policyChanged },
      );
    }
  }

  if (history.reverted === true) {
    throw new HttpsError('failed-precondition', 'This import has already been reverted.', {
      reason: ERROR_REASONS.alreadyReverted,
    });
  }

  const currentNow = now();
  const createdAt = toDateObj(history.createdAt);
  const undoWindowDays = policy.timetableImport.undoWindowDays ?? 7;
  if (!createdAt || currentNow.getTime() - createdAt.getTime() > undoWindowDays * 86_400_000) {
    throw new HttpsError('failed-precondition', 'Undo window has expired for this import.', {
      reason: ERROR_REASONS.undoWindowExpired,
    });
  }

  const prevDays = Array.isArray(history.previousDays) ? history.previousDays : [];
  const dayRefs = prevDays.map((d) => db.collection('school_days').doc(d.dayId));

  if (prevDays.length <= BATCH_CHUNK_SIZE) {
    await db.runTransaction(async (tx) => {
      const freshHistorySnap = await tx.get(historyRef);
      if (!freshHistorySnap.exists || freshHistorySnap.data()?.reverted === true) {
        throw new HttpsError('failed-precondition', 'This import has already been reverted.', {
          reason: ERROR_REASONS.alreadyReverted,
        });
      }

      const daySnaps = await Promise.all(dayRefs.map((ref) => tx.get(ref)));
      for (let i = 0; i < prevDays.length; i++) {
        const prev = prevDays[i];
        const snap = daySnaps[i];
        const curData = snap.exists ? (snap.data() ?? {}) : null;
        const curSlots = Array.isArray(curData?.slots) ? curData.slots : [];
        const currentHash = curData ? (curData.hash ?? slotsHash(curSlots)) : null;

        if (currentHash !== prev.afterHash) {
          throw new HttpsError(
            'aborted',
            'Timetable was modified after this import and cannot be automatically reverted.',
            { reason: ERROR_REASONS.timetableChanged, dayId: prev.dayId, date: prev.date },
          );
        }
      }

      for (let i = 0; i < prevDays.length; i++) {
        const prev = prevDays[i];
        if (!prev.existed) {
          tx.delete(dayRefs[i]);
        } else {
          tx.set(dayRefs[i], {
            domain,
            grade: history.grade,
            course: history.course,
            date: prev.date,
            slots: prev.slots ?? [],
            hash: prev.hash,
            updatedAt: currentNow,
          });
        }
      }

      tx.set(
        historyRef,
        { reverted: true, revertedBy: uid, revertedAt: currentNow },
        { merge: true },
      );
    });
  } else {
    const daySnaps = [];
    for (let i = 0; i < dayRefs.length; i += BATCH_CHUNK_SIZE) {
      daySnaps.push(...(await db.getAll(...dayRefs.slice(i, i + BATCH_CHUNK_SIZE))));
    }
    for (let i = 0; i < prevDays.length; i++) {
      const prev = prevDays[i];
      const snap = daySnaps[i];
      const curData = snap.exists ? (snap.data() ?? {}) : null;
      const curSlots = Array.isArray(curData?.slots) ? curData.slots : [];
      const currentHash = curData ? (curData.hash ?? slotsHash(curSlots)) : null;
      if (currentHash !== prev.afterHash) {
        throw new HttpsError(
          'aborted',
          'Timetable was modified after this import and cannot be automatically reverted.',
          { reason: ERROR_REASONS.timetableChanged, dayId: prev.dayId, date: prev.date },
        );
      }
    }
    for (let i = 0; i < prevDays.length; i += BATCH_CHUNK_SIZE) {
      const batch = db.batch();
      const slice = prevDays.slice(i, i + BATCH_CHUNK_SIZE);
      slice.forEach((prev, offset) => {
        const ref = dayRefs[i + offset];
        if (!prev.existed) {
          batch.delete(ref);
        } else {
          batch.set(ref, {
            domain,
            grade: history.grade,
            course: history.course,
            date: prev.date,
            slots: prev.slots ?? [],
            hash: prev.hash,
            updatedAt: currentNow,
          });
        }
      });
      await batch.commit();
    }
    await historyRef.set(
      { reverted: true, revertedBy: uid, revertedAt: currentNow },
      { merge: true },
    );
  }

  logger.info('Timetable import reverted', {
    domain,
    grade: history.grade,
    course: history.course,
    revertedDays: prevDays.length,
  });

  return { ok: true, revertedDays: prevDays.length };
}
