import { normalizeWithMap } from './text_normalizer.js';

const EMAIL_RE = /[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/g;
const PHONE_RE = /(?<![\d-])(?:0\d{1,4}-\d{1,4}-\d{3,4}|0\d{9,10})(?![\d-])/g;
const POSTAL_RE = /(?<![\d-])〒?\s?\d{3}-\d{4}(?![\d-])/g;
const PROTECTED_TOKEN_RE = /(?:\[[A-Z]+(?:_[A-Z]+)*_\d+\]|［[A-Z]+(?:_[A-Z]+)*_\d+］)/g;

/**
 * Hard upper bound on the input length any school-configured regex
 * (`policy.privacy.studentIdPatterns`) is ever executed against. Longer texts
 * (e.g. a chat prompt with history) are scanned in overlapping windows so the
 * worst-case cost of a single `RegExp` execution stays bounded even without RE2.
 */
export const MAX_SCHOOL_REGEX_INPUT_CHARS = 6000;
/** Overlap between windows so IDs straddling a window boundary are still found. */
export const SCHOOL_REGEX_WINDOW_OVERLAP = 200;

/**
 * Returns `[start, end)` windows (each <= MAX_SCHOOL_REGEX_INPUT_CHARS long)
 * covering a text of [length] characters.
 */
export function schoolRegexWindows(length) {
  if (length <= MAX_SCHOOL_REGEX_INPUT_CHARS) return [[0, length]];
  const step = MAX_SCHOOL_REGEX_INPUT_CHARS - SCHOOL_REGEX_WINDOW_OVERLAP;
  const windows = [];
  for (let start = 0; start < length; start += step) {
    const end = Math.min(length, start + MAX_SCHOOL_REGEX_INPUT_CHARS);
    windows.push([start, end]);
    if (end === length) break;
  }
  return windows;
}

/**
 * `matchAll` for school-configured regexes, never executing [regex] on more
 * than MAX_SCHOOL_REGEX_INPUT_CHARS characters at once. Yields
 * `{ index, text }` with absolute offsets; duplicates from overlapping
 * windows are dropped.
 */
export function* boundedSchoolMatches(regex, text) {
  const seen = new Set();
  for (const [start, end] of schoolRegexWindows(text.length)) {
    const slice = text.slice(start, end);
    regex.lastIndex = 0;
    for (const m of slice.matchAll(regex)) {
      if (!m[0]) continue;
      const index = start + (m.index ?? 0);
      const key = `${index}:${m[0].length}`;
      if (seen.has(key)) continue;
      seen.add(key);
      yield { index, text: m[0] };
    }
  }
}

function isValidJapanesePhone(normalizedSlice) {
  const digitsOnly = normalizedSlice.replace(/-/g, '');
  return digitsOnly.length === 10 || digitsOnly.length === 11;
}

function toGlobalRegex(pattern) {
  if (pattern instanceof RegExp) {
    const flags = pattern.flags.includes('g') ? pattern.flags : `${pattern.flags}g`;
    return new RegExp(pattern.source, flags);
  }
  if (typeof pattern === 'string' && pattern.length > 0) {
    return new RegExp(pattern, 'g');
  }
  return null;
}

/**
 * Masks structured PII patterns (EMAIL, PHONE, POSTAL, STUDENT_ID) in [input]
 * using [session]. Runs after name masking and leaves existing tokens intact.
 */
export function maskPiiPatterns(input, session, { extraPatterns = [] } = {}) {
  const str = String(input ?? '');
  if (!str) return str;

  const normalized = normalizeWithMap(str);
  const normText = normalized.text;

  const protectedSpans = [];
  for (const m of normText.matchAll(PROTECTED_TOKEN_RE)) {
    const start = m.index ?? 0;
    protectedSpans.push({ start, end: start + m[0].length });
  }

  const accepted = [];

  const overlapsExisting = (start, end) => {
    for (const p of protectedSpans) {
      if (start < p.end && end > p.start) return true;
    }
    for (const a of accepted) {
      if (start < a.end && end > a.start) return true;
    }
    return false;
  };

  const collect = (regex, prefix, validator) => {
    for (const m of normText.matchAll(regex)) {
      const slice = m[0];
      if (!slice) continue;
      if (validator && !validator(slice)) continue;
      const start = m.index ?? 0;
      const end = start + slice.length;
      if (overlapsExisting(start, end)) continue;
      accepted.push({ start, end, prefix });
    }
  };

  collect(EMAIL_RE, 'EMAIL');
  collect(PHONE_RE, 'PHONE', isValidJapanesePhone);
  collect(POSTAL_RE, 'POSTAL');
  for (const rawPattern of extraPatterns) {
    const regex = toGlobalRegex(rawPattern);
    if (!regex) continue;
    for (const m of boundedSchoolMatches(regex, normText)) {
      const end = m.index + m.text.length;
      if (overlapsExisting(m.index, end)) continue;
      accepted.push({ start: m.index, end, prefix: 'STUDENT_ID' });
    }
  }

  if (accepted.length === 0) return str;
  accepted.sort((a, b) => a.start - b.start);

  let out = '';
  let cursor = 0;
  for (const item of accepted) {
    const range = normalized.originalRange(item.start, item.end);
    if (range.start < cursor) continue;
    const originalSlice = str.slice(range.start, range.end);
    const token = session.tokenFor(originalSlice, { prefix: item.prefix });
    out += str.slice(cursor, range.start) + token;
    cursor = range.end;
  }
  return out + str.slice(cursor);
}
