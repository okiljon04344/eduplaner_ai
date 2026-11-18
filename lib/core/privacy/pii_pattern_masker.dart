import 'masking_session.dart';
import 'text_normalizer.dart';

class _PiiMatch {
  final int start;
  final int end;
  final String prefix;
  const _PiiMatch({
    required this.start,
    required this.end,
    required this.prefix,
  });
}

/// Masks structured PII patterns (email addresses, Japanese phone numbers,
/// postal codes, and optional school-specific student ID patterns) into
/// [MaskingSession] tokens.
///
/// Run *before* name anonymization (via `AnonymizerService.maskText`) so email
/// local-parts that match a person's name (e.g. `taro@gmail.com`) become
/// `[EMAIL_1]` rather than `[STUDENT_1]@gmail.com`. Existing token syntax
/// is protected via [_protectedTokenPattern].
class PiiPatternMasker {
  static final RegExp _emailPattern = RegExp(
    r'[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}',
  );

  // Hyphenated Japanese phone (e.g. 090-1234-5678, 03-1234-5678, 0120-123-456)
  // or contiguous 10–11 digits starting with 0 (e.g. 09012345678).
  // Bounded by (?<!\d|-) and (?!\d|-) so dates like 2026-11-17 or substrings
  // of longer numbers do not match.
  static final RegExp _phonePattern = RegExp(
    r'(?<![\d-])(?:0\d{1,4}-\d{1,4}-\d{3,4}|0\d{9,10})(?![\d-])',
  );

  // Japanese postal code: `〒086-1100` or `086-1100`.
  // Bounded so 4-digit year dates (2026-1100...) and 3-part phone numbers do not match.
  static final RegExp _postalPattern = RegExp(
    r'(?<![\d-])〒?\s?\d{3}-\d{4}(?![\d-])',
  );

  static final RegExp _protectedTokenPattern = RegExp(
    r'(?:\[[A-Z]+(?:_[A-Z]+)*_\d+\]|［[A-Z]+(?:_[A-Z]+)*_\d+］)',
  );

  /// School-specific student ID (`学籍番号`) patterns supplied by configuration.
  final List<RegExp> extraPatterns;

  const PiiPatternMasker({this.extraPatterns = const []});

  /// Replaces detected PII patterns in [input] with tokens in [session].
  String mask(String input, MaskingSession session) {
    if (input.isEmpty) return input;

    final normalized = TextNormalizer.normalizeWithMap(input);
    final normText = normalized.text;

    final protectedSpans = <({int start, int end})>[
      for (final m in _protectedTokenPattern.allMatches(normText))
        (start: m.start, end: m.end),
    ];

    final accepted = <_PiiMatch>[];

    bool overlapsExisting(int start, int end) {
      for (final p in protectedSpans) {
        if (start < p.end && end > p.start) return true;
      }
      for (final a in accepted) {
        if (start < a.end && end > a.start) return true;
      }
      return false;
    }

    void collect(RegExp regex, String prefix, {bool Function(String)? validator}) {
      for (final m in regex.allMatches(normText)) {
        final slice = m.group(0);
        if (slice == null || slice.isEmpty) continue;
        if (validator != null && !validator(slice)) continue;
        if (overlapsExisting(m.start, m.end)) continue;
        accepted.add(_PiiMatch(start: m.start, end: m.end, prefix: prefix));
      }
    }

    collect(_emailPattern, 'EMAIL');
    collect(_phonePattern, 'PHONE', validator: _isValidJapanesePhone);
    collect(_postalPattern, 'POSTAL');
    for (final pattern in extraPatterns) {
      collect(pattern, 'STUDENT_ID');
    }

    if (accepted.isEmpty) return input;

    accepted.sort((a, b) => a.start.compareTo(b.start));

    final buffer = StringBuffer();
    var cursor = 0;
    for (final item in accepted) {
      final range = normalized.originalRange(item.start, item.end);
      if (range.start < cursor) continue;

      final originalSlice = input.substring(range.start, range.end);
      final token = session.tokenFor(originalSlice, prefix: item.prefix);

      buffer.write(input.substring(cursor, range.start));
      buffer.write(token);
      cursor = range.end;
    }
    buffer.write(input.substring(cursor));
    return buffer.toString();
  }

  static bool _isValidJapanesePhone(String normalizedSlice) {
    final digitsOnly = normalizedSlice.replaceAll('-', '');
    return digitsOnly.length == 10 || digitsOnly.length == 11;
  }
}
