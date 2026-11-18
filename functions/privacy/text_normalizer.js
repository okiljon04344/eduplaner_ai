const DASH_CODE_UNITS = new Set([
  0x2010, // ‐ hyphen
  0x2011, // ‑ non-breaking hyphen
  0x2012, // ‒ figure dash
  0x2013, // – en dash
  0x2014, // — em dash
  0x2015, // ― horizontal bar
  0x2212, // − minus sign
  0x30FC, // ー katakana prolonged sound mark
  0xFF0D, // － full-width hyphen-minus
]);

const isHorizontalSpace = (unit) =>
  unit === 0x20 || unit === 0x09 || unit === 0x3000;

const isDigitUnit = (unit) =>
  (unit >= 0x30 && unit <= 0x39) || (unit >= 0xFF10 && unit <= 0xFF19);

function normalizeChar(input, index, unit) {
  // Full-width digits ０-９ -> 0-9
  if (unit >= 0xFF10 && unit <= 0xFF19) return unit - 0xFEE0;
  // Full-width uppercase A-Z -> A-Z
  if (unit >= 0xFF21 && unit <= 0xFF3A) return unit - 0xFEE0;
  // Full-width lowercase a-z -> a-z
  if (unit >= 0xFF41 && unit <= 0xFF5A) return unit - 0xFEE0;
  // Full-width '@' and '.' for email normalization
  if (unit === 0xFF20) return 0x40;
  if (unit === 0xFF0E) return 0x2E;

  // Normalize dashes to '-' only when directly surrounded by digits so
  // katakana words like コンピューター remain intact.
  if (DASH_CODE_UNITS.has(unit)) {
    const hasPrevDigit = index > 0 && isDigitUnit(input.charCodeAt(index - 1));
    const hasNextDigit =
      index + 1 < input.length && isDigitUnit(input.charCodeAt(index + 1));
    if (hasPrevDigit && hasNextDigit) {
      return 0x2D; // '-'
    }
  }
  return unit;
}

/**
 * Normalizes [input] for matching while recording the starting UTF-16 index of
 * each normalized character in `indexMap` (`indexMap[text.length] === input.length`).
 */
export function normalizeWithMap(input) {
  const str = String(input ?? '');
  if (str.length === 0) {
    return {
      text: '',
      indexMap: [0],
      originalRange: () => ({ start: 0, end: 0 }),
    };
  }

  const chars = [];
  const indexMap = [];
  let inHorizontalSpace = false;

  for (let i = 0; i < str.length; i++) {
    const unit = str.charCodeAt(i);
    if (isHorizontalSpace(unit)) {
      if (!inHorizontalSpace) {
        chars.push(' ');
        indexMap.push(i);
        inHorizontalSpace = true;
      }
      continue;
    }
    inHorizontalSpace = false;
    chars.push(String.fromCharCode(normalizeChar(str, i, unit)));
    indexMap.push(i);
  }
  indexMap.push(str.length);

  const text = chars.join('');
  return {
    text,
    indexMap,
    originalRange(start, end) {
      const safeStart = Math.max(0, Math.min(start, text.length));
      const safeEnd = Math.max(safeStart, Math.min(end, text.length));
      return { start: indexMap[safeStart], end: indexMap[safeEnd] };
    },
  };
}

export const normalizeForComparison = (input) => normalizeWithMap(input).text;
