import 'dart:async';
import 'package:edu_planner_ai/core/l10n/app_strings.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runs once before every test file under test/.
///
/// Widgets call AppStrings.t() to resolve localized text, but AppStrings'
/// static cache is only populated by an explicit AppStrings.load() call
/// (normally done once at app startup in main.dart). Without this, every
/// widget test that asserts on translated text sees raw i18n keys instead
/// of the real Japanese strings and fails.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await AppStrings.load('ja');
  await testMain();
}
