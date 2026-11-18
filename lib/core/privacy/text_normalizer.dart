/// Result of normalizing text for matching while preserving a mapping back to
/// character offsets in the original input.
///
/// Why this exists: collapsing consecutive horizontal whitespace (e.g. `"  "` or
/// `"　　"` → `" "`) shortens the normalized string. Recording the starting
/// original index of each normalized character in [indexMap] (with
/// `indexMap[normalized.length] == originalLength`) lets callers match patterns
/// against [text] and slice/replace the exact corresponding span in the
/// original string without disturbing surrounding spaces or line breaks.
class NormalizedText {
  final String text;
  final List<int> indexMap;

  const NormalizedText({
    required this.text,
    required this.indexMap,
  });

  /// Converts a half-open range `[start, end)` in [text] back into the
  /// corresponding half-open range in the original input string.
  ({int start, int end}) originalRange(int start, int end) {
    final safeStart = start.clamp(0, text.length);
    final safeEnd = end.clamp(safeStart, text.length);
    return (start: indexMap[safeStart], end: indexMap[safeEnd]);
  }
}

/// Normalizes Japanese/English text for PII and name lookup without mutating
/// the caller's original text outside matched spans.
abstract final class TextNormalizer {
  static const _dashCodeUnits = <int>{
    0x2010, // ‐ hyphen
    0x2011, // ‑ non-breaking hyphen
    0x2012, // ‒ figure dash
    0x2013, // – en dash
    0x2014, // — em dash
    0x2015, // ― horizontal bar
    0x2212, // − minus sign
    0x30FC, // ー katakana prolonged sound mark
    0xFF0D, // － full-width hyphen-minus
  };

  /// Normalizes [input] and returns both the normalized string and its
  /// character-offset mapping back to [input].
  ///
  /// Transformations applied:
  /// 1. Full-width ASCII digits (`０`–`９`) and Latin letters (`Ａ`–`Ｚ`, `ａ`–`ｚ`)
  ///    are converted to half-width.
  /// 2. Full-width `@` (`＠`) and `.` (`．`) are converted to half-width for
  ///    email lookup, while `［` / `］` are deliberately left intact so
  ///    neutralized user tokens are not confused with masking tokens.
  /// 3. Various dash characters (`－`, `ー`, `‐`, `—`, `–`, etc.) are converted
  ///    to ASCII `-` **only when immediately between two digits**, so katakana
  ///    words like `コンピューター` remain intact.
  /// 4. Full-width spaces (`　`) and consecutive horizontal whitespace (` `, `\t`)
  ///    are collapsed into a single ASCII space `' '`. Newlines are preserved.
  static NormalizedText normalizeWithMap(String input) {
    if (input.isEmpty) {
      return const NormalizedText(text: '', indexMap: [0]);
    }

    final buffer = StringBuffer();
    final map = <int>[];
    var inHorizontalSpace = false;

    for (var i = 0; i < input.length; i++) {
      final unit = input.codeUnitAt(i);

      if (_isHorizontalSpace(unit)) {
        if (!inHorizontalSpace) {
          buffer.writeCharCode(0x20);
          map.add(i);
          inHorizontalSpace = true;
        }
        continue;
      }

      inHorizontalSpace = false;
      final normalizedUnit = _normalizeChar(input, i, unit);
      buffer.writeCharCode(normalizedUnit);
      map.add(i);
    }

    map.add(input.length);
    return NormalizedText(text: buffer.toString(), indexMap: map);
  }

  /// Convenience helper for normalizing short strings (keys, names, cells) for
  /// comparison and lookup.
  static String normalizeForComparison(String input) => normalizeWithMap(input).text;

  static bool _isHorizontalSpace(int unit) =>
      unit == 0x20 || unit == 0x09 || unit == 0x3000;

  static bool _isDigitUnit(int unit) =>
      (unit >= 0x30 && unit <= 0x39) || (unit >= 0xFF10 && unit <= 0xFF19);

  static int _normalizeChar(String input, int index, int unit) {
    // Full-width digits ０-９ -> 0-9
    if (unit >= 0xFF10 && unit <= 0xFF19) return unit - 0xFEE0;
    // Full-width uppercase A-Z -> A-Z
    if (unit >= 0xFF21 && unit <= 0xFF3A) return unit - 0xFEE0;
    // Full-width lowercase a-z -> a-z
    if (unit >= 0xFF41 && unit <= 0xFF5A) return unit - 0xFEE0;
    // Full-width '@' and '.' for email normalization
    if (unit == 0xFF20) return 0x40;
    if (unit == 0xFF0E) return 0x2E;

    // Normalize dashes to '-' only when directly surrounded by digits.
    if (_dashCodeUnits.contains(unit)) {
      final hasPrevDigit = index > 0 && _isDigitUnit(input.codeUnitAt(index - 1));
      final hasNextDigit =
          index + 1 < input.length && _isDigitUnit(input.codeUnitAt(index + 1));
      if (hasPrevDigit && hasNextDigit) {
        return 0x2D; // '-'
      }
    }

    return unit;
  }
}
