import 'text_normalizer.dart';

/// Holds the bidirectional mapping between real PII values and anonymous tokens
/// (such as `[STUDENT_1]`, `[PHONE_1]`, `[STUDENT_ID_1]`) for a single AI
/// request or file import.
///
/// The mapping never leaves the device and [toString] is overridden so
/// accidental logging cannot expose personal information.
class MaskingSession {
  static final RegExp tokenPattern = RegExp(r'\[[A-Z]+(?:_[A-Z]+)*_\d+\]');
  static final RegExp _neutralizedTokenPattern =
      RegExp(r'［[A-Z]+(?:_[A-Z]+)*_\d+］');

  /// Matches unresolved or AI-corrupted tokens after [restore]:
  /// - unmapped `[PREFIX_1]`
  /// - bracketed space/hyphen variants like `[PERSON 1]`, `[PERSON-1]`
  /// - lenticular bracket variants like `【PERSON_1】`, `【PERSON 1】`, `【PERSON-1】`
  /// - bare known-prefix variants like `PERSON 1`, `PERSON-1`, `STUDENT_1`
  ///   (excluding neutralized `［...］` tokens written by [neutralizeTokens]).
  static final RegExp _corruptedOrUnresolvedPattern = RegExp(
    r'\[[A-Z]+(?:_[A-Z]+)*(?:_|\s+|-)\d+\]'
    r'|【[A-Z]+(?:_[A-Z]+)*(?:_|\s+|-)\d+】'
    r'|(?<!［)\b(?:STUDENT|TEACHER|PERSON|EMAIL|PHONE|POSTAL|STUDENT_ID|ID)(?:_|\s+|-)\d+\b(?!］)',
  );

  final Map<String, String> _keyToToken = {};
  final Map<String, String> _tokenToValue = {};
  final Map<String, int> _counters = {};

  /// Unmodifiable view of `token -> original value` for the current session.
  Map<String, String> get tokenToValue => Map.unmodifiable(_tokenToValue);

  /// True when at least one value has been masked in this session.
  bool get hasMaskedData => _tokenToValue.isNotEmpty;

  /// Neutralizes preexisting token-like strings (e.g. user-typed `[PERSON_1]`)
  /// before masking so [restore] never replaces user-authored text with a real
  /// person's name. Converts `[` / `]` of matching tokens into full-width `［` / `］`.
  static String neutralizeTokens(String input) {
    if (input.isEmpty) return input;
    return input.replaceAllMapped(tokenPattern, (m) {
      final raw = m.group(0) ?? '';
      if (raw.length < 2) return raw;
      return '［${raw.substring(1, raw.length - 1)}］';
    });
  }

  /// Returns a stable token for [value] under [prefix] (e.g. `[STUDENT_1]`).
  ///
  /// Equivalent values (after [TextNormalizer.normalizeForComparison], trim, and
  /// lowercasing) always receive the same token within this session. An explicit
  /// [canonicalKey] can be supplied when multiple surface forms (such as a
  /// surname and a given name of the same person) should share one token.
  String tokenFor(
    String value, {
    required String prefix,
    String? canonicalKey,
  }) {
    final trimmed = value.trim();
    if (trimmed.isEmpty && canonicalKey == null) return value;

    final normalizedKey = TextNormalizer.normalizeForComparison(
      canonicalKey ?? trimmed,
    ).trim().toLowerCase();
    final lookupKey = '$prefix:$normalizedKey';

    final existing = _keyToToken[lookupKey];
    if (existing != null) return existing;

    final nextIndex = (_counters[prefix] ?? 0) + 1;
    _counters[prefix] = nextIndex;
    final token = '[$prefix' '_$nextIndex]';

    _keyToToken[lookupKey] = token;
    _tokenToValue[token] = trimmed.isNotEmpty ? trimmed : value;
    return token;
  }

  /// Replaces valid session tokens in [text] with their original values.
  /// Any `[PREFIX_N]` token not found in this session is left untouched.
  String restore(String text) {
    if (text.isEmpty || _tokenToValue.isEmpty) return text;
    return text.replaceAllMapped(tokenPattern, (m) {
      final token = m.group(0);
      if (token == null) return '';
      return _tokenToValue[token] ?? token;
    });
  }

  /// Scans [text] (typically after [restore]) for leftover unknown tokens or
  /// AI-corrupted token variants such as `PERSON 1`, `[PERSON-1]`, `【PERSON_1】`.
  List<String> findUnresolvedTokens(String text) {
    if (text.isEmpty) return const [];

    // Strip neutralized user-authored tokens before scanning so a user-typed
    // `[PERSON_1]` (neutralized to `［PERSON_1］`) is not flagged as an AI error.
    final cleaned = text.replaceAll(_neutralizedTokenPattern, ' ');
    final found = <String>[];
    for (final match in _corruptedOrUnresolvedPattern.allMatches(cleaned)) {
      final token = match.group(0);
      if (token != null && !found.contains(token)) {
        found.add(token);
      }
    }
    return found;
  }

  /// Never prints stored PII values or mappings.
  @override
  String toString() => 'MaskingSession(maskedCount: ${_tokenToValue.length})';
}
