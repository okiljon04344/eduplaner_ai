import 'dart:convert';
import 'dart:io';

import 'package:edu_planner_ai/core/l10n/app_strings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

/// Every supported locale must carry every key the app reads, otherwise
/// `AppStrings.t` shows the raw key (e.g. `social_proof`) on screen.
void main() {
  Map<String, dynamic> load(String code) =>
      jsonDecode(File('assets/l10n/$code.json').readAsStringSync()) as Map<String, dynamic>;
  Set<String> placeholders(String s) => RegExp(r'\{(\w+)\}').allMatches(s).map((m) => m.group(1)!).toSet();

  final ja = load('ja');
  // Only read when the locale is ja (DateHelper.formatJapaneseDate).
  const jaOnly = {'date_format_jp'};

  for (final (code, _, _) in AppStrings.locales) {
    test('$code has every key, no unknown placeholders', () {
      final strings = load(code);
      expect(ja.keys.toSet().difference(jaOnly).difference(strings.keys.toSet()), isEmpty);
      for (final key in strings.keys.where(ja.containsKey)) {
        // A placeholder ja doesn't pass in would be shown raw, e.g. "{n}".
        expect(placeholders(strings[key] as String).difference(placeholders(ja[key] as String)), isEmpty, reason: key);
      }
    });
  }

  test('every locale can format a date', () async {
    await initializeDateFormatting(null);
    for (final (code, _, _) in AppStrings.locales) {
      expect(DateFormat.yMMMMEEEEd(code).format(DateTime(2026, 10, 13)), isNotEmpty, reason: code);
    }
  });
}
