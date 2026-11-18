import { randomUUID } from 'node:crypto';
import { HttpsError } from 'firebase-functions/https';
import { logger } from 'firebase-functions';
import { resolveSchoolDomain } from './sync.js';
import { isTeacher } from './overrides.js';
import { ERROR_REASONS } from '../shared/error_reasons.js';

export const POLICY_SCHEMA_VERSION = 1;
export const ALLOWED_IMPORTERS_MODES = Object.freeze([
  'admins_only',
  'homeroom_and_admins',
  'all_teachers',
]);
export const REPLACE_MODES = Object.freeze([
  'disabled',
  'admins_only',
  'allowed',
]);
export const SCHOOL_DAY_VALUES = Object.freeze([
  '月',
  '火',
  '水',
  '木',
  '金',
  '土',
  '日',
]);

export const POLICY_HISTORY_TTL_DAYS = 365;
export const MIN_UNDO_WINDOW_DAYS = 1;
export const MAX_UNDO_WINDOW_DAYS = 30;
export const MAX_CLOSED_DATE_RANGES = 30;
export const MAX_CLOSED_RANGE_LABEL_LENGTH = 80;
export const MAX_STUDENT_ID_PATTERNS = 10;
export const MAX_STUDENT_ID_PATTERN_LENGTH = 100;
export const MAX_EXTRA_REDACTION_LABELS = 20;
export const MAX_EXTRA_REDACTION_LABEL_LENGTH = 40;
export const MAX_EXTRA_HONORIFIC_EXCEPTIONS = 30;
export const MAX_EXTRA_HONORIFIC_EXCEPTION_LENGTH = 30;
const MAX_REGEX_QUANTIFIER_BOUND = 50;
const REGEX_SMOKE_TIMEOUT_MS = 25;

export const DEFAULT_SCHOOL_POLICY = Object.freeze({
  schemaVersion: POLICY_SCHEMA_VERSION,
  revision: 0,
  updatedAt: null,
  timetableImport: Object.freeze({
    allowedImporters: 'homeroom_and_admins',
    replaceMode: 'admins_only',
    notifyStudentsDefault: false,
    undoWindowDays: 7,
    schoolDays: Object.freeze(['月', '火', '水', '木', '金']),
    closedDateRanges: Object.freeze([]),
    excludeNationalHolidays: true,
  }),
  privacy: Object.freeze({
    studentIdPatterns: Object.freeze([]),
    extraRedactionLabels: Object.freeze([]),
    extraHonorificExceptions: Object.freeze([]),
  }),
});

export function defaultSchoolPolicy() {
  return {
    schemaVersion: POLICY_SCHEMA_VERSION,
    revision: 0,
    updatedAt: null,
    timetableImport: {
      allowedImporters: DEFAULT_SCHOOL_POLICY.timetableImport.allowedImporters,
      replaceMode: DEFAULT_SCHOOL_POLICY.timetableImport.replaceMode,
      notifyStudentsDefault:
        DEFAULT_SCHOOL_POLICY.timetableImport.notifyStudentsDefault,
      undoWindowDays: DEFAULT_SCHOOL_POLICY.timetableImport.undoWindowDays,
      schoolDays: [...DEFAULT_SCHOOL_POLICY.timetableImport.schoolDays],
      closedDateRanges: [],
      excludeNationalHolidays:
        DEFAULT_SCHOOL_POLICY.timetableImport.excludeNationalHolidays,
    },
    privacy: {
      studentIdPatterns: [],
      extraRedactionLabels: [],
      extraHonorificExceptions: [],
    },
  };
}

function clonePolicy(policy) {
  return {
    schemaVersion: policy.schemaVersion,
    revision: policy.revision ?? 0,
    updatedAt: policy.updatedAt ?? null,
    timetableImport: {
      ...policy.timetableImport,
      schoolDays: [...policy.timetableImport.schoolDays],
      closedDateRanges: policy.timetableImport.closedDateRanges.map((r) => ({ ...r })),
    },
    privacy: {
      studentIdPatterns: [...policy.privacy.studentIdPatterns],
      extraRedactionLabels: [...policy.privacy.extraRedactionLabels],
      extraHonorificExceptions: [...policy.privacy.extraHonorificExceptions],
    },
  };
}

const isPlainObject = (v) =>
  v !== null && typeof v === 'object' && !Array.isArray(v);

const TOP_LEVEL_KEYS = new Set([
  'schemaVersion',
  'revision',
  'updatedAt',
  'timetableImport',
  'privacy',
]);
const TIMETABLE_IMPORT_KEYS = new Set([
  'allowedImporters',
  'replaceMode',
  'notifyStudentsDefault',
  'undoWindowDays',
  'schoolDays',
  'closedDateRanges',
  'excludeNationalHolidays',
]);
const PRIVACY_KEYS = new Set([
  'studentIdPatterns',
  'extraRedactionLabels',
  'extraHonorificExceptions',
]);
const CLOSED_RANGE_KEYS = new Set(['start', 'end', 'label']);

const ISO_DATE_RE = /^\d{4}-\d{2}-\d{2}$/;

/**
 * Verifies `YYYY-MM-DD` corresponds to a real calendar date (rejects `2026-02-30`).
 */
export function isValidIsoDate(str) {
  if (typeof str !== 'string' || !ISO_DATE_RE.test(str)) return false;
  const [yStr, mStr, dStr] = str.split('-');
  const y = Number.parseInt(yStr, 10);
  const m = Number.parseInt(mStr, 10);
  const d = Number.parseInt(dStr, 10);
  if (m < 1 || m > 12 || d < 1 || d > 31) return false;
  const dt = new Date(Date.UTC(y, m - 1, d));
  return (
    dt.getUTCFullYear() === y &&
    dt.getUTCMonth() === m - 1 &&
    dt.getUTCDate() === d
  );
}

/**
 * Parses a `{m}` or `{m,n}` quantifier starting at `source[idx] === '{'`.
 * Returns `{ ok, endIndex, min, max }` or `null` if not a valid quantifier.
 */
function parseBraceQuantifier(source, idx) {
  const match = /^\{(\d+)(?:,(\d*))?\}/.exec(source.slice(idx));
  if (!match) return null;
  const min = Number.parseInt(match[1], 10);
  const maxStr = match[2];
  const max = maxStr === undefined ? min : (maxStr === '' ? Infinity : Number.parseInt(maxStr, 10));
  return {
    endIndex: idx + match[0].length,
    min,
    max,
  };
}

/**
 * Validates a regex pattern for ReDoS safety before it can be saved or run:
 * - Non-empty string <= 100 chars
 * - Compiles cleanly with `new RegExp`
 * - Does not match empty string `""`
 * - Rejects lookarounds (`(?=`, `(?!`, `(?<=`, `(?<!`), backreferences (`\1`..`\9`, `\k<`)
 * - Rejects nested quantifiers / star height > 1 and quantified alternations (e.g. `(a+)+`, `(a|a)*`)
 * - Rejects excessive `{m,n}` bounds (> 50)
 * - Runs a fast adversarial input smoke check
 */
export function validateSafeRegexPattern(source) {
  if (typeof source !== 'string' || source.length === 0) {
    return { ok: false, reason: 'Regex pattern must be a non-empty string.' };
  }
  if (source.length > MAX_STUDENT_ID_PATTERN_LENGTH) {
    return {
      ok: false,
      reason: `Regex pattern exceeds ${MAX_STUDENT_ID_PATTERN_LENGTH} characters.`,
    };
  }

  let inCharClass = false;
  const groupStack = [];
  let lastWasQuantifiable = false;
  let lastEndedQuantifier = false;

  for (let i = 0; i < source.length; i++) {
    const ch = source[i];

    if (ch === '\\') {
      if (i + 1 >= source.length) {
        return { ok: false, reason: 'Trailing backslash in regex pattern.' };
      }
      const next = source[i + 1];
      if (!inCharClass && ((next >= '1' && next <= '9') || next === 'k')) {
        return { ok: false, reason: 'Backreferences are not allowed in regex pattern.' };
      }
      i += 1;
      lastWasQuantifiable = !inCharClass;
      lastEndedQuantifier = false;
      continue;
    }

    if (inCharClass) {
      if (ch === ']') {
        inCharClass = false;
        lastWasQuantifiable = true;
        lastEndedQuantifier = false;
      }
      continue;
    }

    if (ch === '[') {
      inCharClass = true;
      lastWasQuantifiable = false;
      lastEndedQuantifier = false;
      continue;
    }

    if (ch === '(') {
      if (source[i + 1] === '?') {
        const two = source.slice(i, i + 3);
        const three = source.slice(i, i + 4);
        if (two === '(?=' || two === '(?!' || three === '(?<=' || three === '(?<!') {
          return { ok: false, reason: 'Lookarounds are not allowed in regex pattern.' };
        }
        if (two === '(?:') {
          i += 2;
        } else if (two === '(?<') {
          const closeAngle = source.indexOf('>', i + 3);
          if (closeAngle === -1) {
            return { ok: false, reason: 'Unclosed named capture group in regex pattern.' };
          }
          i = closeAngle;
        } else {
          return { ok: false, reason: 'Unsupported group syntax in regex pattern.' };
        }
      }
      groupStack.push({ hasQuantifier: false, hasAlternation: false });
      lastWasQuantifiable = false;
      lastEndedQuantifier = false;
      continue;
    }

    if (ch === ')') {
      if (groupStack.length === 0) {
        return { ok: false, reason: 'Unbalanced parentheses in regex pattern.' };
      }
      const closed = groupStack.pop();
      // Look ahead for a quantifier immediately following `)`.
      const afterIdx = i + 1;
      const nextCh = source[afterIdx];
      let hasOuterQuantifier = nextCh === '*' || nextCh === '+' || nextCh === '?';
      let brace = null;
      if (!hasOuterQuantifier && nextCh === '{') {
        brace = parseBraceQuantifier(source, afterIdx);
        hasOuterQuantifier = brace !== null;
      }

      if (hasOuterQuantifier && (closed.hasQuantifier || closed.hasAlternation)) {
        return {
          ok: false,
          reason: 'Nested quantifiers or quantified alternations are not allowed.',
        };
      }

      if (groupStack.length > 0) {
        const parent = groupStack[groupStack.length - 1];
        if (closed.hasQuantifier || hasOuterQuantifier) {
          parent.hasQuantifier = true;
        }
      }
      lastWasQuantifiable = true;
      lastEndedQuantifier = false;
      continue;
    }

    if (ch === '|') {
      if (groupStack.length > 0) {
        groupStack[groupStack.length - 1].hasAlternation = true;
      }
      lastWasQuantifiable = false;
      lastEndedQuantifier = false;
      continue;
    }

    if (ch === '*' || ch === '+' || ch === '?') {
      if (lastEndedQuantifier) {
        if (ch === '?') {
          // Lazy modifier (e.g. `+?`, `*?`, `{1,4}?`) ends the quantifier.
          lastEndedQuantifier = false;
          lastWasQuantifiable = false;
          continue;
        }
        return { ok: false, reason: 'Chained quantifiers are not allowed.' };
      }
      if (!lastWasQuantifiable) {
        return { ok: false, reason: 'Quantifier has nothing to repeat.' };
      }
      if (groupStack.length > 0) {
        groupStack[groupStack.length - 1].hasQuantifier = true;
      }
      lastWasQuantifiable = false;
      lastEndedQuantifier = true;
      continue;
    }

    if (ch === '{') {
      const brace = parseBraceQuantifier(source, i);
      if (brace) {
        if (lastEndedQuantifier || !lastWasQuantifiable) {
          return { ok: false, reason: 'Invalid quantifier placement.' };
        }
        if (
          brace.min > MAX_REGEX_QUANTIFIER_BOUND ||
          (Number.isFinite(brace.max) && brace.max > MAX_REGEX_QUANTIFIER_BOUND) ||
          brace.max < brace.min
        ) {
          return {
            ok: false,
            reason: `Quantifier bounds must be <= ${MAX_REGEX_QUANTIFIER_BOUND} and min <= max.`,
          };
        }
        if (groupStack.length > 0) {
          groupStack[groupStack.length - 1].hasQuantifier = true;
        }
        i = brace.endIndex - 1;
        lastWasQuantifiable = false;
        lastEndedQuantifier = true;
        continue;
      }
    }

    if (ch === '^' || ch === '$') {
      lastWasQuantifiable = false;
      lastEndedQuantifier = false;
      continue;
    }

    lastWasQuantifiable = true;
    lastEndedQuantifier = false;
  }

  if (inCharClass || groupStack.length > 0) {
    return { ok: false, reason: 'Unclosed character class or group in regex pattern.' };
  }

  let re;
  try {
    re = new RegExp(source);
  } catch {
    return { ok: false, reason: 'Invalid regular expression syntax.' };
  }

  if (re.test('')) {
    return { ok: false, reason: 'Regex pattern must not match empty strings.' };
  }

  const samples = [
    `${'a'.repeat(32)}!`,
    `${'0'.repeat(32)}!`,
    `${'A'.repeat(32)}!`,
  ];
  for (const sample of samples) {
    const started = performance.now();
    re.test(sample);
    if (performance.now() - started > REGEX_SMOKE_TIMEOUT_MS) {
      return { ok: false, reason: 'Regex pattern failed adversarial timing check.' };
    }
  }

  return { ok: true, pattern: source };
}

function bad(message) {
  throw new HttpsError('invalid-argument', message);
}

/**
 * Strict validator for admin `setSchoolPolicy` writes. Rejects unknown keys,
 * invalid enums/ranges/dates, and unsafe regexes. Missing sections/fields
 * fall back to `DEFAULT_SCHOOL_POLICY`.
 */
export function validateSchoolPolicyInput(raw) {
  if (!isPlainObject(raw)) {
    bad('Policy payload must be an object.');
  }
  for (const key of Object.keys(raw)) {
    if (!TOP_LEVEL_KEYS.has(key)) {
      bad(`Unknown policy field: ${key}`);
    }
  }
  if (raw.schemaVersion !== undefined && raw.schemaVersion !== POLICY_SCHEMA_VERSION) {
    bad(`schemaVersion must be ${POLICY_SCHEMA_VERSION}.`);
  }
  if (raw.revision !== undefined && raw.revision !== null) {
    if (!Number.isInteger(raw.revision) || raw.revision < 0) {
      bad('revision must be a non-negative integer.');
    }
  }
  if (raw.updatedAt !== undefined && raw.updatedAt !== null) {
    if (typeof raw.updatedAt !== 'string' || raw.updatedAt.length > 50) {
      bad('updatedAt must be an ISO string or null.');
    }
  }

  const out = defaultSchoolPolicy();

  if (raw.timetableImport !== undefined) {
    if (!isPlainObject(raw.timetableImport)) {
      bad('timetableImport must be an object.');
    }
    for (const key of Object.keys(raw.timetableImport)) {
      if (!TIMETABLE_IMPORT_KEYS.has(key)) {
        bad(`Unknown timetableImport field: ${key}`);
      }
    }
    const ti = raw.timetableImport;

    if (ti.allowedImporters !== undefined) {
      if (!ALLOWED_IMPORTERS_MODES.includes(ti.allowedImporters)) {
        bad('Invalid timetableImport.allowedImporters value.');
      }
      out.timetableImport.allowedImporters = ti.allowedImporters;
    }

    if (ti.replaceMode !== undefined) {
      if (!REPLACE_MODES.includes(ti.replaceMode)) {
        bad('Invalid timetableImport.replaceMode value.');
      }
      out.timetableImport.replaceMode = ti.replaceMode;
    }

    if (ti.notifyStudentsDefault !== undefined) {
      if (typeof ti.notifyStudentsDefault !== 'boolean') {
        bad('timetableImport.notifyStudentsDefault must be a boolean.');
      }
      out.timetableImport.notifyStudentsDefault = ti.notifyStudentsDefault;
    }

    if (ti.undoWindowDays !== undefined) {
      if (
        !Number.isInteger(ti.undoWindowDays) ||
        ti.undoWindowDays < MIN_UNDO_WINDOW_DAYS ||
        ti.undoWindowDays > MAX_UNDO_WINDOW_DAYS
      ) {
        bad(
          `timetableImport.undoWindowDays must be an integer between ${MIN_UNDO_WINDOW_DAYS} and ${MAX_UNDO_WINDOW_DAYS}.`,
        );
      }
      out.timetableImport.undoWindowDays = ti.undoWindowDays;
    }

    if (ti.schoolDays !== undefined) {
      if (!Array.isArray(ti.schoolDays) || ti.schoolDays.length === 0) {
        bad('timetableImport.schoolDays must be a non-empty array.');
      }
      const seen = new Set();
      for (const day of ti.schoolDays) {
        if (typeof day !== 'string' || !SCHOOL_DAY_VALUES.includes(day)) {
          bad('timetableImport.schoolDays contains an invalid weekday.');
        }
        if (seen.has(day)) {
          bad('timetableImport.schoolDays must not contain duplicates.');
        }
        seen.add(day);
      }
      out.timetableImport.schoolDays = [...seen];
    }

    if (ti.closedDateRanges !== undefined) {
      if (!Array.isArray(ti.closedDateRanges)) {
        bad('timetableImport.closedDateRanges must be an array.');
      }
      if (ti.closedDateRanges.length > MAX_CLOSED_DATE_RANGES) {
        bad(`timetableImport.closedDateRanges may not exceed ${MAX_CLOSED_DATE_RANGES} items.`);
      }
      const ranges = [];
      for (const item of ti.closedDateRanges) {
        if (!isPlainObject(item)) {
          bad('Each closedDateRanges item must be an object.');
        }
        for (const k of Object.keys(item)) {
          if (!CLOSED_RANGE_KEYS.has(k)) {
            bad(`Unknown closedDateRanges item field: ${k}`);
          }
        }
        if (!isValidIsoDate(item.start) || !isValidIsoDate(item.end)) {
          bad('closedDateRanges start and end must be valid YYYY-MM-DD dates.');
        }
        if (item.start > item.end) {
          bad('closedDateRanges start must be <= end.');
        }
        const label = item.label === undefined ? '' : item.label;
        if (typeof label !== 'string' || label.trim().length > MAX_CLOSED_RANGE_LABEL_LENGTH) {
          bad(`closedDateRanges label must be at most ${MAX_CLOSED_RANGE_LABEL_LENGTH} characters.`);
        }
        ranges.push({
          start: item.start,
          end: item.end,
          label: label.trim(),
        });
      }
      out.timetableImport.closedDateRanges = ranges;
    }

    if (ti.excludeNationalHolidays !== undefined) {
      if (typeof ti.excludeNationalHolidays !== 'boolean') {
        bad('timetableImport.excludeNationalHolidays must be a boolean.');
      }
      out.timetableImport.excludeNationalHolidays = ti.excludeNationalHolidays;
    }
  }

  if (raw.privacy !== undefined) {
    if (!isPlainObject(raw.privacy)) {
      bad('privacy must be an object.');
    }
    for (const key of Object.keys(raw.privacy)) {
      if (!PRIVACY_KEYS.has(key)) {
        bad(`Unknown privacy field: ${key}`);
      }
    }
    const pr = raw.privacy;

    if (pr.studentIdPatterns !== undefined) {
      if (!Array.isArray(pr.studentIdPatterns)) {
        bad('privacy.studentIdPatterns must be an array.');
      }
      if (pr.studentIdPatterns.length > MAX_STUDENT_ID_PATTERNS) {
        bad(`privacy.studentIdPatterns may not exceed ${MAX_STUDENT_ID_PATTERNS} patterns.`);
      }
      const seen = new Set();
      for (const pat of pr.studentIdPatterns) {
        const check = validateSafeRegexPattern(pat);
        if (!check.ok) {
          bad(check.reason);
        }
        seen.add(pat);
      }
      out.privacy.studentIdPatterns = [...seen];
    }

    if (pr.extraRedactionLabels !== undefined) {
      if (!Array.isArray(pr.extraRedactionLabels)) {
        bad('privacy.extraRedactionLabels must be an array.');
      }
      if (pr.extraRedactionLabels.length > MAX_EXTRA_REDACTION_LABELS) {
        bad(`privacy.extraRedactionLabels may not exceed ${MAX_EXTRA_REDACTION_LABELS} items.`);
      }
      const seen = new Set();
      for (const label of pr.extraRedactionLabels) {
        if (typeof label !== 'string') {
          bad('privacy.extraRedactionLabels items must be strings.');
        }
        const trimmed = label.trim();
        if (trimmed.length === 0 || trimmed.length > MAX_EXTRA_REDACTION_LABEL_LENGTH) {
          bad(
            `privacy.extraRedactionLabels items must be 1-${MAX_EXTRA_REDACTION_LABEL_LENGTH} characters.`,
          );
        }
        seen.add(trimmed);
      }
      out.privacy.extraRedactionLabels = [...seen];
    }

    if (pr.extraHonorificExceptions !== undefined) {
      if (!Array.isArray(pr.extraHonorificExceptions)) {
        bad('privacy.extraHonorificExceptions must be an array.');
      }
      if (pr.extraHonorificExceptions.length > MAX_EXTRA_HONORIFIC_EXCEPTIONS) {
        bad(
          `privacy.extraHonorificExceptions may not exceed ${MAX_EXTRA_HONORIFIC_EXCEPTIONS} items.`,
        );
      }
      const seen = new Set();
      for (const ex of pr.extraHonorificExceptions) {
        if (typeof ex !== 'string') {
          bad('privacy.extraHonorificExceptions items must be strings.');
        }
        const trimmed = ex.trim();
        if (trimmed.length === 0 || trimmed.length > MAX_EXTRA_HONORIFIC_EXCEPTION_LENGTH) {
          bad(
            `privacy.extraHonorificExceptions items must be 1-${MAX_EXTRA_HONORIFIC_EXCEPTION_LENGTH} characters.`,
          );
        }
        seen.add(trimmed);
      }
      out.privacy.extraHonorificExceptions = [...seen];
    }
  }

  return out;
}

/**
 * Resilient runtime reader for `schools/{domain}.policy`. Never throws; falls
 * back to default values for any missing or corrupted fields and warns with
 * field names only (never values).
 */
export function normalizeSchoolPolicy(raw, { domain } = {}) {
  const out = defaultSchoolPolicy();
  if (raw === undefined || raw === null) {
    return out;
  }

  const corruptedFields = [];
  const warnField = (name) => {
    if (!corruptedFields.includes(name)) corruptedFields.push(name);
  };

  if (!isPlainObject(raw)) {
    warnField('policy');
    logger.warn('Corrupted school policy field; using default', {
      domain: domain ?? null,
      fields: corruptedFields,
    });
    return out;
  }

  for (const key of Object.keys(raw)) {
    if (!TOP_LEVEL_KEYS.has(key)) {
      warnField(`unknown.${key}`);
    }
  }
  if (raw.schemaVersion !== undefined && raw.schemaVersion !== POLICY_SCHEMA_VERSION) {
    warnField('schemaVersion');
  }
  if (raw.revision !== undefined && raw.revision !== null) {
    if (Number.isInteger(raw.revision) && raw.revision >= 0) {
      out.revision = raw.revision;
    } else {
      warnField('revision');
    }
  }
  if (raw.updatedAt !== undefined && raw.updatedAt !== null) {
    if (typeof raw.updatedAt === 'string' && raw.updatedAt.length <= 50) {
      out.updatedAt = raw.updatedAt;
    } else if (typeof raw.updatedAt?.toDate === 'function') {
      out.updatedAt = raw.updatedAt.toDate().toISOString();
    } else if (raw.updatedAt instanceof Date) {
      out.updatedAt = raw.updatedAt.toISOString();
    } else {
      warnField('updatedAt');
    }
  }

  if (raw.timetableImport !== undefined) {
    if (!isPlainObject(raw.timetableImport)) {
      warnField('timetableImport');
    } else {
      const ti = raw.timetableImport;
      for (const key of Object.keys(ti)) {
        if (!TIMETABLE_IMPORT_KEYS.has(key)) {
          warnField(`timetableImport.unknown.${key}`);
        }
      }
      if (ti.allowedImporters !== undefined) {
        if (ALLOWED_IMPORTERS_MODES.includes(ti.allowedImporters)) {
          out.timetableImport.allowedImporters = ti.allowedImporters;
        } else {
          warnField('timetableImport.allowedImporters');
        }
      }
      if (ti.replaceMode !== undefined) {
        if (REPLACE_MODES.includes(ti.replaceMode)) {
          out.timetableImport.replaceMode = ti.replaceMode;
        } else {
          warnField('timetableImport.replaceMode');
        }
      }
      if (ti.notifyStudentsDefault !== undefined) {
        if (typeof ti.notifyStudentsDefault === 'boolean') {
          out.timetableImport.notifyStudentsDefault = ti.notifyStudentsDefault;
        } else {
          warnField('timetableImport.notifyStudentsDefault');
        }
      }
      if (ti.undoWindowDays !== undefined) {
        if (
          Number.isInteger(ti.undoWindowDays) &&
          ti.undoWindowDays >= MIN_UNDO_WINDOW_DAYS &&
          ti.undoWindowDays <= MAX_UNDO_WINDOW_DAYS
        ) {
          out.timetableImport.undoWindowDays = ti.undoWindowDays;
        } else {
          warnField('timetableImport.undoWindowDays');
        }
      }
      if (ti.schoolDays !== undefined) {
        if (Array.isArray(ti.schoolDays) && ti.schoolDays.length > 0) {
          const validDays = [];
          const seen = new Set();
          let hadBadDay = false;
          for (const d of ti.schoolDays) {
            if (typeof d === 'string' && SCHOOL_DAY_VALUES.includes(d) && !seen.has(d)) {
              seen.add(d);
              validDays.push(d);
            } else {
              hadBadDay = true;
            }
          }
          if (validDays.length > 0) {
            out.timetableImport.schoolDays = validDays;
          }
          if (hadBadDay || validDays.length === 0) {
            warnField('timetableImport.schoolDays');
          }
        } else {
          warnField('timetableImport.schoolDays');
        }
      }
      if (ti.closedDateRanges !== undefined) {
        if (Array.isArray(ti.closedDateRanges)) {
          const validRanges = [];
          let hadBadRange = ti.closedDateRanges.length > MAX_CLOSED_DATE_RANGES;
          for (const item of ti.closedDateRanges.slice(0, MAX_CLOSED_DATE_RANGES)) {
            if (
              isPlainObject(item) &&
              Object.keys(item).every((k) => CLOSED_RANGE_KEYS.has(k)) &&
              isValidIsoDate(item.start) &&
              isValidIsoDate(item.end) &&
              item.start <= item.end &&
              (item.label === undefined ||
                (typeof item.label === 'string' &&
                  item.label.trim().length <= MAX_CLOSED_RANGE_LABEL_LENGTH))
            ) {
              validRanges.push({
                start: item.start,
                end: item.end,
                label: typeof item.label === 'string' ? item.label.trim() : '',
              });
            } else {
              hadBadRange = true;
            }
          }
          out.timetableImport.closedDateRanges = validRanges;
          if (hadBadRange) {
            warnField('timetableImport.closedDateRanges');
          }
        } else {
          warnField('timetableImport.closedDateRanges');
        }
      }
      if (ti.excludeNationalHolidays !== undefined) {
        if (typeof ti.excludeNationalHolidays === 'boolean') {
          out.timetableImport.excludeNationalHolidays = ti.excludeNationalHolidays;
        } else {
          warnField('timetableImport.excludeNationalHolidays');
        }
      }
    }
  }

  if (raw.privacy !== undefined) {
    if (!isPlainObject(raw.privacy)) {
      warnField('privacy');
    } else {
      const pr = raw.privacy;
      for (const key of Object.keys(pr)) {
        if (!PRIVACY_KEYS.has(key)) {
          warnField(`privacy.unknown.${key}`);
        }
      }
      if (pr.studentIdPatterns !== undefined) {
        if (Array.isArray(pr.studentIdPatterns)) {
          const validPatterns = [];
          const seen = new Set();
          let hadBadPattern = pr.studentIdPatterns.length > MAX_STUDENT_ID_PATTERNS;
          for (const pat of pr.studentIdPatterns.slice(0, MAX_STUDENT_ID_PATTERNS)) {
            const check = validateSafeRegexPattern(pat);
            if (check.ok) {
              if (!seen.has(pat)) {
                seen.add(pat);
                validPatterns.push(pat);
              }
            } else {
              hadBadPattern = true;
            }
          }
          out.privacy.studentIdPatterns = validPatterns;
          if (hadBadPattern) {
            warnField('privacy.studentIdPatterns');
          }
        } else {
          warnField('privacy.studentIdPatterns');
        }
      }
      if (pr.extraRedactionLabels !== undefined) {
        if (Array.isArray(pr.extraRedactionLabels)) {
          const validLabels = [];
          const seen = new Set();
          let hadBadLabel = pr.extraRedactionLabels.length > MAX_EXTRA_REDACTION_LABELS;
          for (const lbl of pr.extraRedactionLabels.slice(0, MAX_EXTRA_REDACTION_LABELS)) {
            if (
              typeof lbl === 'string' &&
              lbl.trim().length > 0 &&
              lbl.trim().length <= MAX_EXTRA_REDACTION_LABEL_LENGTH
            ) {
              const trimmed = lbl.trim();
              if (!seen.has(trimmed)) {
                seen.add(trimmed);
                validLabels.push(trimmed);
              }
            } else {
              hadBadLabel = true;
            }
          }
          out.privacy.extraRedactionLabels = validLabels;
          if (hadBadLabel) {
            warnField('privacy.extraRedactionLabels');
          }
        } else {
          warnField('privacy.extraRedactionLabels');
        }
      }
      if (pr.extraHonorificExceptions !== undefined) {
        if (Array.isArray(pr.extraHonorificExceptions)) {
          const validEx = [];
          const seen = new Set();
          let hadBadEx =
            pr.extraHonorificExceptions.length > MAX_EXTRA_HONORIFIC_EXCEPTIONS;
          for (const ex of pr.extraHonorificExceptions.slice(
            0,
            MAX_EXTRA_HONORIFIC_EXCEPTIONS,
          )) {
            if (
              typeof ex === 'string' &&
              ex.trim().length > 0 &&
              ex.trim().length <= MAX_EXTRA_HONORIFIC_EXCEPTION_LENGTH
            ) {
              const trimmed = ex.trim();
              if (!seen.has(trimmed)) {
                seen.add(trimmed);
                validEx.push(trimmed);
              }
            } else {
              hadBadEx = true;
            }
          }
          out.privacy.extraHonorificExceptions = validEx;
          if (hadBadEx) {
            warnField('privacy.extraHonorificExceptions');
          }
        } else {
          warnField('privacy.extraHonorificExceptions');
        }
      }
    }
  }

  if (corruptedFields.length > 0) {
    logger.warn('Corrupted school policy field; using default', {
      domain: domain ?? null,
      fields: corruptedFields,
    });
  }

  return out;
}

/**
 * Loads `schools/{domain}.policy`, normalizing with defaults on missing or
 * corrupted fields. Uses `cache` (a Map keyed by domain) if provided.
 */
export async function loadSchoolPolicy(domain, { db, cache } = {}) {
  const cleanDomain = typeof domain === 'string' ? domain.trim().toLowerCase() : '';
  if (!cleanDomain) return defaultSchoolPolicy();
  if (cache && cache.has(cleanDomain)) {
    return clonePolicy(cache.get(cleanDomain));
  }
  if (!db) {
    throw new Error('Firestore instance is required to load school policy.');
  }
  const snap = await db.collection('schools').doc(cleanDomain).get();
  const rawPolicy = snap.exists ? (snap.data()?.policy ?? null) : null;
  const normalized = normalizeSchoolPolicy(rawPolicy, { domain: cleanDomain });
  if (cache) {
    cache.set(cleanDomain, clonePolicy(normalized));
  }
  return normalized;
}

/**
 * Resolves the caller's verified school domain (if any) and returns its
 * normalized policy (or `DEFAULT_SCHOOL_POLICY` for unlinked users).
 */
export async function loadSchoolPolicyForAuth(
  auth,
  { db, domainCache, policyCache } = {},
) {
  if (!auth?.uid || !db) return defaultSchoolPolicy();
  let domain;
  if (domainCache && domainCache.has(auth.uid)) {
    domain = domainCache.get(auth.uid);
  } else {
    domain = await resolveSchoolDomain(auth, { db });
    if (domainCache) {
      domainCache.set(auth.uid, domain);
    }
  }
  if (!domain) return defaultSchoolPolicy();
  return loadSchoolPolicy(domain, { db, cache: policyCache });
}

/**
 * Validates and persists a school policy update under `schools/{domain}.policy`,
 * recording an immutable diff entry in `school_policy_history/{historyId}` with
 * a 365-day `expiresAt` TTL.
 */
export async function saveSchoolPolicy(
  domain,
  rawPolicy,
  actor,
  { db, now = () => new Date(), expectedRevision, expectedUpdatedAt } = {},
) {
  const cleanDomain = typeof domain === 'string' ? domain.trim().toLowerCase() : '';
  if (!cleanDomain) {
    throw new HttpsError('permission-denied', 'Not a school admin.');
  }
  if (!db) {
    throw new Error('Firestore instance is required to save school policy.');
  }

  let effectiveExpectedRevision;
  if (expectedRevision !== undefined && expectedRevision !== null) {
    if (!Number.isInteger(expectedRevision) || expectedRevision < 0) {
      bad('expectedRevision must be a non-negative integer.');
    }
    effectiveExpectedRevision = expectedRevision;
  } else if (
    isPlainObject(rawPolicy) &&
    rawPolicy.revision !== undefined &&
    rawPolicy.revision !== null
  ) {
    if (!Number.isInteger(rawPolicy.revision) || rawPolicy.revision < 0) {
      bad('revision must be a non-negative integer.');
    }
    effectiveExpectedRevision = rawPolicy.revision;
  }

  let effectiveExpectedUpdatedAt;
  if (expectedUpdatedAt !== undefined && expectedUpdatedAt !== null) {
    if (typeof expectedUpdatedAt !== 'string' || expectedUpdatedAt.length > 50) {
      bad('expectedUpdatedAt must be an ISO string.');
    }
    effectiveExpectedUpdatedAt = expectedUpdatedAt;
  }

  const nextPolicy = validateSchoolPolicyInput(rawPolicy);
  const schoolRef = db.collection('schools').doc(cleanDomain);
  const historyId = `${cleanDomain}_${randomUUID()}`;
  const historyRef = db.collection('school_policy_history').doc(historyId);
  const createdAt = now();
  const expiresAt = new Date(createdAt.getTime() + POLICY_HISTORY_TTL_DAYS * 86_400_000);

  await db.runTransaction(async (tx) => {
    const schoolSnap = await tx.get(schoolRef);
    const schoolData = schoolSnap.exists ? (schoolSnap.data() ?? null) : null;
    if (!schoolData || !(schoolData.admins ?? []).includes(actor?.uid)) {
      throw new HttpsError('permission-denied', 'Not a school admin.');
    }

    const previousPolicy = normalizeSchoolPolicy(schoolData.policy ?? null, {
      domain: cleanDomain,
    });
    const currentRevision = previousPolicy.revision ?? 0;
    const currentUpdatedAt = previousPolicy.updatedAt ?? null;

    if (
      effectiveExpectedRevision !== undefined &&
      effectiveExpectedRevision !== currentRevision
    ) {
      throw new HttpsError(
        'aborted',
        'School policy was updated by another administrator.',
        {
          reason: ERROR_REASONS.policyChanged,
          currentRevision,
          currentUpdatedAt,
        },
      );
    }
    if (
      effectiveExpectedUpdatedAt !== undefined &&
      effectiveExpectedUpdatedAt !== currentUpdatedAt
    ) {
      throw new HttpsError(
        'aborted',
        'School policy was updated by another administrator.',
        {
          reason: ERROR_REASONS.policyChanged,
          currentRevision,
          currentUpdatedAt,
        },
      );
    }

    nextPolicy.revision = currentRevision + 1;
    nextPolicy.updatedAt = createdAt.toISOString();

    tx.set(schoolRef, { policy: nextPolicy }, { merge: true });
    tx.set(historyRef, {
      domain: cleanDomain,
      changedByUid: String(actor?.uid ?? ''),
      changedByEmail: String(actor?.email ?? '').trim().toLowerCase(),
      previousPolicy,
      nextPolicy,
      createdAt,
      expiresAt,
    });
  });

  return { policy: nextPolicy, historyId };
}

/**
 * Pure permission check for timetable file import governed by
 * `policy.timetableImport.allowedImporters`.
 */
export function canUserImportTimetable(
  school,
  policy,
  uid,
  email,
  targetGrade,
  targetCourse,
) {
  if (!isTeacher(school, uid, email)) return false;
  if ((school?.admins ?? []).includes(uid)) return true;

  const mode = policy?.timetableImport?.allowedImporters ?? 'homeroom_and_admins';
  if (mode === 'admins_only') return false;
  if (mode === 'all_teachers') return true;

  // 'homeroom_and_admins'
  const profile = school?.teacherProfiles?.[String(email ?? '').trim().toLowerCase()];
  const homeroom = profile?.homeroom;
  if (!homeroom) return false;
  return (
    Number(homeroom.grade) === Number(targetGrade) &&
    String(homeroom.course ?? '') === String(targetCourse ?? '')
  );
}

/**
 * Pure permission check for destructive `mode: 'replace'` imports governed by
 * `policy.timetableImport.replaceMode`.
 */
export function canUserUseReplaceMode(school, policy, uid) {
  const mode = policy?.timetableImport?.replaceMode ?? 'admins_only';
  if (mode === 'disabled') return false;
  if (mode === 'admins_only') {
    return (school?.admins ?? []).includes(uid);
  }
  return mode === 'allowed';
}
