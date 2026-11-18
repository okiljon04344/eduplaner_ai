import 'package:flutter/foundation.dart' show listEquals;
import 'masking_session.dart';
import 'person_name.dart';
import 'pii_pattern_masker.dart';
import 'text_normalizer.dart';

class _TermTarget {
  final PersonName? uniquePerson;
  const _TermTarget.unique(PersonName person) : uniquePerson = person;
  const _TermTarget.ambiguous() : uniquePerson = null;
}

class _CompiledRoster {
  final RegExp? pattern;
  final Map<String, _TermTarget> targets;
  const _CompiledRoster({required this.pattern, required this.targets});
}

/// Default Japanese words that end with an honorific suffix (`さん`, `様`, etc.)
/// or precede `先生`, which must NOT be masked as a person's name.
const Set<String> kDefaultHonorificExceptions = {
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
};

/// Replaces known student and teacher names (plus their name parts/readings)
/// and honorific-suffixed Japanese names in free text with session-scoped
/// tokens from [MaskingSession].
class AnonymizerService {
  static const int minPartLength = 2;
  static final RegExp _latinOnlyRegex = RegExp(r'^[A-Za-z]+(?:\s+[A-Za-z]+)*$');

  /// Matches 1–4 kanji/kana characters immediately followed by a Japanese
  /// honorific (`さん`, `くん`, `君`, `ちゃん`, `先生`, `様`).
  /// Preceded by a negative lookbehind for kanji so a longer compound word is
  /// not sliced mid-word; particles in hiragana like `と佐藤さん` or `は田中先生`
  /// are split via [_leadingParticleChars] below.
  static final RegExp _honorificPattern = RegExp(
    r'([\u4E00-\u9FFF\u3040-\u309F\u30A0-\u30FFー]{1,4})(さん|くん|君|ちゃん|先生|様)',
  );

  /// Common single-hiragana particles that may directly precede a name in a
  /// sentence (e.g. `と田中さん`, `は佐藤先生`). If a match starts with one of
  /// these and the remaining stem is at least 1 kanji/katakana (or 2+ chars),
  /// the leading particle is left outside the token.
  static const Set<String> _leadingParticles = {
    'は',
    'が',
    'を',
    'に',
    'へ',
    'と',
    'で',
    'や',
    'の',
    'も',
    'か',
  };

  final Set<String> honorificExceptions;
  final bool enableHonorificFallback;

  List<PersonName>? _cachedPeople;
  _CompiledRoster? _cachedRoster;

  AnonymizerService({
    Set<String>? honorificExceptions,
    this.enableHonorificFallback = true,
  }) : honorificExceptions = {
          ...kDefaultHonorificExceptions,
          ...?honorificExceptions,
        };

  /// Full text anonymization pipeline matching the server-side `maskText`
  /// order:
  /// 1. Neutralizes preexisting `[TOKEN_1]` strings (`［TOKEN_1］`)
  /// 2. Masks structured PII patterns (`EMAIL`, `PHONE`, `POSTAL`, `STUDENT_ID`)
  ///    before name matching so email local-parts matching a known name (e.g.
  ///    `taro@gmail.com`) become `[EMAIL_1]` instead of `[STUDENT_1]@gmail.com`
  /// 3. Masks recognized names from [people] and honorific-suffixed names
  String maskText(
    String input,
    List<PersonName> people,
    MaskingSession session, {
    PiiPatternMasker piiMasker = const PiiPatternMasker(),
  }) {
    if (input.isEmpty) return input;

    final neutralized = MaskingSession.neutralizeTokens(input);
    final afterPii = piiMasker.mask(neutralized, session);
    return anonymize(afterPii, people, session);
  }

  /// Masks all recognized names from [people] (and, when enabled, unknown
  /// Japanese names followed by honorifics) in [input] using [session].
  ///
  /// Uses [TextNormalizer] for case-insensitive, full-width/half-width-agnostic
  /// matching while slicing and replacing exact positions in [input].
  String anonymize(
    String input,
    List<PersonName> people,
    MaskingSession session,
  ) {
    if (input.isEmpty) return input;

    var current = _anonymizeKnownPeople(input, people, session);
    if (enableHonorificFallback) {
      current = _anonymizeHonorifics(current, session);
    }
    return current;
  }

  String _anonymizeKnownPeople(
    String input,
    List<PersonName> people,
    MaskingSession session,
  ) {
    if (people.isEmpty) return input;

    final roster = _rosterFor(people);
    final pattern = roster.pattern;
    if (pattern == null) return input;

    final normalized = TextNormalizer.normalizeWithMap(input);
    final matches = pattern.allMatches(normalized.text).toList();
    if (matches.isEmpty) return input;

    final buffer = StringBuffer();
    var cursor = 0;

    for (final match in matches) {
      final matchedNorm = match.group(0);
      if (matchedNorm == null || matchedNorm.isEmpty) continue;

      final range = normalized.originalRange(match.start, match.end);
      if (range.start < cursor) continue;

      final originalSlice = input.substring(range.start, range.end);
      // Do not touch already-tokenized segments.
      if (MaskingSession.tokenPattern.hasMatch(originalSlice)) continue;

      final target = roster.targets[matchedNorm.toLowerCase()];
      if (target == null) continue;

      final String token;
      final person = target.uniquePerson;
      if (person != null) {
        token = session.tokenFor(
          person.fullName,
          prefix: person.tokenPrefix,
          canonicalKey: 'person:${person.id}',
        );
      } else {
        // Shared partial name across multiple people (e.g. same surname):
        // mask as generic PERSON since the individual cannot be disambiguated.
        token = session.tokenFor(
          originalSlice,
          prefix: 'PERSON',
          canonicalKey: 'ambiguous:${matchedNorm.toLowerCase()}',
        );
      }

      buffer.write(input.substring(cursor, range.start));
      buffer.write(token);
      cursor = range.end;
    }

    if (cursor == 0) return input;
    buffer.write(input.substring(cursor));
    return buffer.toString();
  }

  String _anonymizeHonorifics(String input, MaskingSession session) {
    final matches = _honorificPattern.allMatches(input).toList();
    if (matches.isEmpty) return input;

    final buffer = StringBuffer();
    var cursor = 0;

    for (final match in matches) {
      final rawStem = match.group(1);
      final suffix = match.group(2);
      if (rawStem == null || suffix == null) continue;
      if (match.start < cursor) continue;

      // Trim any leading Japanese particle (e.g. `と佐藤` -> particle `と`, stem `佐藤`).
      var stemStartOffset = 0;
      var stem = rawStem;
      while (stem.length >= 2 && _leadingParticles.contains(stem[0])) {
        final rest = stem.substring(1);
        final restStartsWithKanjiOrKatakana =
            RegExp(r'^[\u4E00-\u9FFF\u30A0-\u30FF]').hasMatch(rest);
        if (restStartsWithKanjiOrKatakana || rest.length >= 2) {
          stemStartOffset += 1;
          stem = rest;
        } else {
          break;
        }
      }

      final fullPhrase = '$stem$suffix';
      if (honorificExceptions.contains(stem) ||
          honorificExceptions.contains(fullPhrase)) {
        continue;
      }

      final nameStart = match.start + stemStartOffset;
      final nameEnd = nameStart + stem.length;
      final token = session.tokenFor(stem, prefix: 'PERSON');

      buffer.write(input.substring(cursor, nameStart));
      buffer.write(token);
      buffer.write(suffix);
      cursor = nameEnd + suffix.length;
    }

    if (cursor == 0) return input;
    buffer.write(input.substring(cursor));
    return buffer.toString();
  }

  _CompiledRoster _rosterFor(List<PersonName> people) {
    final cachedPeople = _cachedPeople;
    final cachedRoster = _cachedRoster;
    if (cachedPeople != null &&
        cachedRoster != null &&
        (identical(people, cachedPeople) || listEquals(people, cachedPeople))) {
      return cachedRoster;
    }

    final compiled = _compileRoster(people);
    _cachedPeople = List<PersonName>.unmodifiable(people);
    _cachedRoster = compiled;
    return compiled;
  }

  static _CompiledRoster _compileRoster(List<PersonName> people) {
    final fullOwners = <String, Set<PersonName>>{};
    final allOwners = <String, Set<PersonName>>{};
    final termDisplay = <String, String>{};

    void registerTerm(String raw, PersonName person, {required bool isFullName}) {
      final norm = TextNormalizer.normalizeForComparison(raw).trim();
      if (norm.length < minPartLength) return;
      final key = norm.toLowerCase();
      termDisplay.putIfAbsent(key, () => norm);
      allOwners.putIfAbsent(key, () => <PersonName>{}).add(person);
      if (isFullName) {
        fullOwners.putIfAbsent(key, () => <PersonName>{}).add(person);
      }
    }

    for (final person in people) {
      final full = person.fullName.trim();
      if (full.isEmpty) continue;
      registerTerm(full, person, isFullName: true);
      final noSpaces = full.replaceAll(RegExp(r'[\s　]+'), '');
      if (noSpaces != full) {
        registerTerm(noSpaces, person, isFullName: true);
      }
      for (final part in person.parts) {
        registerTerm(part, person, isFullName: false);
      }
    }

    if (termDisplay.isEmpty) {
      return const _CompiledRoster(pattern: null, targets: {});
    }

    final targets = <String, _TermTarget>{};
    for (final key in termDisplay.keys) {
      final fullSet = fullOwners[key];
      final allSet = allOwners[key];
      if (fullSet != null && fullSet.length == 1) {
        targets[key] = _TermTarget.unique(fullSet.first);
      } else if ((fullSet == null || fullSet.isEmpty) &&
          allSet != null &&
          allSet.length == 1) {
        targets[key] = _TermTarget.unique(allSet.first);
      } else {
        targets[key] = const _TermTarget.ambiguous();
      }
    }

    // Longest terms first so `山田太郎` always wins over `山田` or `太郎`.
    final sortedTerms = termDisplay.values.toList()
      ..sort((a, b) {
        final lenCmp = b.length.compareTo(a.length);
        return lenCmp != 0 ? lenCmp : a.compareTo(b);
      });

    final patternParts = sortedTerms.map((term) {
      final escaped = RegExp.escape(term);
      if (_latinOnlyRegex.hasMatch(term)) {
        return '(?<![A-Za-z])$escaped(?![A-Za-z])';
      }
      return escaped;
    }).toList();

    final regex = RegExp(patternParts.join('|'), caseSensitive: false);
    return _CompiledRoster(pattern: regex, targets: targets);
  }
}
