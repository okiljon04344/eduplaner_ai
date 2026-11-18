import { MaskingSession, TOKEN_REGEX_SOURCE } from './masking_session.js';
import { normalizeForComparison, normalizeWithMap } from './text_normalizer.js';
import { maskPiiPatterns } from './pii_pattern_masker.js';

export const MIN_PART_LENGTH = 2;

const LATIN_ONLY_RE = /^[A-Za-z]+(?:\s+[A-Za-z]+)*$/;
const SINGLE_TOKEN_RE = new RegExp(`^${TOKEN_REGEX_SOURCE}$`);
const HONORIFIC_RE =
  /([\u4E00-\u9FFF\u3040-\u309F\u30A0-\u30FFー]{1,4})(さん|くん|君|ちゃん|先生|様)/g;
const LEADING_PARTICLES = new Set([
  'は', 'が', 'を', 'に', 'へ', 'と', 'で', 'や', 'の', 'も', 'か',
]);
const KANJI_OR_KATAKANA_START_RE = /^[\u4E00-\u9FFF\u30A0-\u30FF]/;

export const DEFAULT_HONORIFIC_EXCEPTIONS = Object.freeze([
  'お母',
  'お父',
  'お兄',
  'お姉',
  'おじい',
  'おばあ',
  'おじ',
  'おば',
  '皆',
  'みな',
  'お客',
  '店員',
  '駅員',
  '係員',
  '運転手',
  'お医者',
  '医者',
  '神',
  '仏',
  '奥',
  '旦那',
  'ご主人',
  'お嬢',
  '坊',
  'お巡り',
  'パン屋',
  '花屋',
  '八百屋',
  '本屋',
  '魚屋',
  '肉屋',
  '担任',
  '校長',
  '教頭',
  '顧問',
  '先生',
]);

const escapeRegExp = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

const rolePrefixOf = (role) => (role === 'teacher' ? 'TEACHER' : 'STUDENT');

/**
 * Splits a Japanese or Latin full name into searchable parts (surname/given name)
 * when spaces are present.
 */
export function deriveNameParts(fullName, existingParts = []) {
  const parts = new Set(Array.isArray(existingParts) ? existingParts : []);
  const norm = normalizeForComparison(fullName).trim();
  if (norm.includes(' ')) {
    for (const seg of norm.split(' ')) {
      const trimmed = seg.trim();
      if (trimmed.length >= MIN_PART_LENGTH) parts.add(trimmed);
    }
  }
  return [...parts];
}

export function compileRoster(people) {
  if (!Array.isArray(people) || people.length === 0) {
    return { patternSrc: null, targets: new Map() };
  }

  const fullOwners = new Map();
  const allOwners = new Map();
  const termDisplay = new Map();

  const addOwner = (map, key, person) => {
    let bucket = map.get(key);
    if (!bucket) {
      bucket = new Map();
      map.set(key, bucket);
    }
    bucket.set(person.id, person);
  };

  const registerTerm = (raw, person, isFullName) => {
    const norm = normalizeForComparison(raw).trim();
    if (norm.length < MIN_PART_LENGTH) return;
    const key = norm.toLowerCase();
    if (!termDisplay.has(key)) termDisplay.set(key, norm);
    addOwner(allOwners, key, person);
    if (isFullName) addOwner(fullOwners, key, person);
  };

  for (const rawPerson of people) {
    if (!rawPerson || typeof rawPerson.fullName !== 'string') continue;
    const full = rawPerson.fullName.trim();
    if (!full) continue;
    const person = {
      id: String(rawPerson.id ?? full),
      fullName: full,
      role: rawPerson.role === 'teacher' ? 'teacher' : 'student',
      parts: deriveNameParts(full, rawPerson.parts),
    };
    registerTerm(full, person, true);
    const noSpaces = full.replace(/[\s　]+/g, '');
    if (noSpaces !== full) {
      registerTerm(noSpaces, person, true);
    }
    for (const part of person.parts) {
      if (typeof part === 'string') registerTerm(part, person, false);
    }
  }

  if (termDisplay.size === 0) {
    return { patternSrc: null, targets: new Map() };
  }

  const targets = new Map();
  for (const key of termDisplay.keys()) {
    const fullMap = fullOwners.get(key);
    const allMap = allOwners.get(key);
    if (fullMap && fullMap.size === 1) {
      targets.set(key, { uniquePerson: [...fullMap.values()][0] });
    } else if ((!fullMap || fullMap.size === 0) && allMap && allMap.size === 1) {
      targets.set(key, { uniquePerson: [...allMap.values()][0] });
    } else {
      targets.set(key, { uniquePerson: null });
    }
  }

  const sortedTerms = [...termDisplay.values()].sort((a, b) => {
    const lenDiff = b.length - a.length;
    return lenDiff !== 0 ? lenDiff : a.localeCompare(b);
  });

  const patternParts = sortedTerms.map((term) => {
    const escaped = escapeRegExp(term);
    if (LATIN_ONLY_RE.test(term)) {
      return `(?<![A-Za-z])${escaped}(?![A-Za-z])`;
    }
    return escaped;
  });

  return { patternSrc: patternParts.join('|'), targets };
}

export function anonymizeKnownPeople(input, people, session, compiledRoster) {
  const str = String(input ?? '');
  if (!str) return str;
  const roster = compiledRoster ?? compileRoster(people);
  if (!roster.patternSrc) return str;

  const normalized = normalizeWithMap(str);
  const regex = new RegExp(roster.patternSrc, 'gi');
  const matches = [...normalized.text.matchAll(regex)];
  if (matches.length === 0) return str;

  let out = '';
  let cursor = 0;

  for (const match of matches) {
    const matchedNorm = match[0];
    if (!matchedNorm) continue;
    const start = match.index ?? 0;
    const end = start + matchedNorm.length;
    const range = normalized.originalRange(start, end);
    if (range.start < cursor) continue;

    const originalSlice = str.slice(range.start, range.end);
    if (SINGLE_TOKEN_RE.test(originalSlice)) continue;

    const target = roster.targets.get(matchedNorm.toLowerCase());
    if (!target) continue;

    let token;
    if (target.uniquePerson) {
      const p = target.uniquePerson;
      token = session.tokenFor(p.fullName, {
        prefix: rolePrefixOf(p.role),
        canonicalKey: `person:${p.id}`,
      });
    } else {
      token = session.tokenFor(originalSlice, {
        prefix: 'PERSON',
        canonicalKey: `ambiguous:${matchedNorm.toLowerCase()}`,
      });
    }

    out += str.slice(cursor, range.start) + token;
    cursor = range.end;
  }

  if (cursor === 0) return str;
  return out + str.slice(cursor);
}

export function anonymizeHonorifics(
  input,
  session,
  honorificExceptions = DEFAULT_HONORIFIC_EXCEPTIONS,
) {
  const str = String(input ?? '');
  if (!str) return str;
  const exceptionSet =
    honorificExceptions instanceof Set
      ? honorificExceptions
      : new Set([...DEFAULT_HONORIFIC_EXCEPTIONS, ...(honorificExceptions ?? [])]);

  const matches = [...str.matchAll(HONORIFIC_RE)];
  if (matches.length === 0) return str;

  let out = '';
  let cursor = 0;

  for (const match of matches) {
    const rawStem = match[1];
    const suffix = match[2];
    const matchStart = match.index ?? 0;
    if (!rawStem || !suffix || matchStart < cursor) continue;

    let stemStartOffset = 0;
    let stem = rawStem;
    while (stem.length >= 2 && LEADING_PARTICLES.has(stem[0])) {
      const rest = stem.slice(1);
      if (KANJI_OR_KATAKANA_START_RE.test(rest) || rest.length >= 2) {
        stemStartOffset += 1;
        stem = rest;
      } else {
        break;
      }
    }

    const fullPhrase = `${stem}${suffix}`;
    if (exceptionSet.has(stem) || exceptionSet.has(fullPhrase)) {
      continue;
    }

    const nameStart = matchStart + stemStartOffset;
    const nameEnd = nameStart + stem.length;
    const token = session.tokenFor(stem, { prefix: 'PERSON' });

    out += str.slice(cursor, nameStart) + token + suffix;
    cursor = nameEnd + suffix.length;
  }

  if (cursor === 0) return str;
  return out + str.slice(cursor);
}

/**
 * Full text anonymization pipeline:
 * 1. Neutralizes preexisting `[TOKEN_1]` strings (`［TOKEN_1］`)
 * 2. Replaces structured PII patterns (`EMAIL`, `PHONE`, `POSTAL`, `STUDENT_ID`)
 *    first so email local-parts matching a known name (e.g. `taro@gmail.com`)
 *    are masked as a whole `[EMAIL_1]` rather than `[STUDENT_1]@gmail.com`.
 * 3. Replaces known student/teacher names
 * 4. Replaces honorific-suffixed Japanese names (`〜さん`, `〜先生`, etc.)
 */
export function maskText(
  input,
  people,
  session,
  {
    compiledRoster,
    extraPatterns = [],
    honorificExceptions,
    enableHonorificFallback = true,
  } = {},
) {
  const str = String(input ?? '');
  if (!str) return str;

  const neutralized = MaskingSession.neutralizeTokens(str);
  let current = maskPiiPatterns(neutralized, session, { extraPatterns });
  current = anonymizeKnownPeople(current, people, session, compiledRoster);
  if (enableHonorificFallback) {
    current = anonymizeHonorifics(current, session, honorificExceptions);
  }
  return current;
}
