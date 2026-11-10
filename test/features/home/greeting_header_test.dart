import 'package:edu_planner_ai/core/l10n/app_strings.dart';
import 'package:edu_planner_ai/core/providers/clock_provider.dart';
import 'package:edu_planner_ai/core/theme/app_colors.dart';
import 'package:edu_planner_ai/features/assignments/models/assignment_model.dart';
import 'package:edu_planner_ai/features/assignments/providers/assignments_provider.dart';
import 'package:edu_planner_ai/features/auth/models/user_model.dart';
import 'package:edu_planner_ai/features/auth/providers/auth_provider.dart';
import 'package:edu_planner_ai/features/home/widgets/greeting_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../../support/fakes.dart';

final _now = DateTime(2026, 10, 29, 9);

String _greeting(String name) =>
    AppStrings.t('home_greet_morning', {'name': name});

Widget _harness({
  required UserModel? user,
  required List<AssignmentModel> assignments,
}) {
  return ProviderScope(
    overrides: [
      // Short-circuit auth: skip AuthRepository (which would touch
      // FirebaseAuth.instance during construction).
      authStateProvider.overrideWith((_) => Stream<UserModel?>.value(user)),
      // Short-circuit the assignments stream: no Firestore call, and no need
      // to fake the repository at all for the count-based badge.
      assignmentsStreamProvider.overrideWith((_) => Stream.value(assignments)),
      // Fixed 09:00 so the greeting key is deterministic (morning).
      minuteTickProvider.overrideWith((_) => Stream.value(_now)),
    ],
    child: const MaterialApp(
      home: Scaffold(
        // GreetingHeader lives inside a hero container in production; wrap in
        // a fixed-height SizedBox so its Row layout has bounded width.
        body: Padding(
          padding: EdgeInsets.all(16),
          child: SizedBox(width: 400, child: GreetingHeader()),
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(() => initializeDateFormatting());
  setUp(() => AppColors.applyBrightness(Brightness.dark));
  tearDown(() => AppColors.applyBrightness(Brightness.dark));

  test('greetingKey follows the time of day', () {
    expect(GreetingHeader.greetingKey(DateTime(2026, 1, 1, 9)), 'home_greet_morning');
    expect(GreetingHeader.greetingKey(DateTime(2026, 1, 1, 13)), 'home_greet_day');
    expect(GreetingHeader.greetingKey(DateTime(2026, 1, 1, 19)), 'home_greet_evening');
  });

  testWidgets('greets the current user by name', (tester) async {
    await tester.pumpWidget(_harness(user: buildUser(name: '田中太郎'), assignments: const []));
    await tester.pumpAndSettle();

    expect(find.text(_greeting('田中太郎')), findsOneWidget);
  });

  testWidgets('falls back to the guest name when no user is signed in', (tester) async {
    await tester.pumpWidget(_harness(user: null, assignments: const []));
    await tester.pumpAndSettle();

    expect(find.text(_greeting(AppStrings.t('home_guest'))), findsOneWidget);
  });

  testWidgets('bell has no dot when nothing is urgent', (tester) async {
    await tester.pumpWidget(_harness(
      user: buildUser(),
      assignments: [
        // due 30 days out -> not urgent
        buildAssignment(dueDate: DateTime.now().add(const Duration(days: 30))),
      ],
    ));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.notifications_none_rounded), findsOneWidget);
    expect(find.byKey(const ValueKey('urgent-dot')), findsNothing);
  });

  testWidgets('bell shows a dot when an assignment is due soon', (tester) async {
    await tester.pumpWidget(_harness(
      user: buildUser(),
      assignments: [buildAssignment(dueDate: DateTime.now().add(const Duration(days: 1)))],
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('urgent-dot')), findsOneWidget);
  });

  testWidgets('renders cleanly in both dark and light themes', (tester) async {
    for (final brightness in [Brightness.dark, Brightness.light]) {
      AppColors.applyBrightness(brightness);
      await tester.pumpWidget(_harness(user: buildUser(name: 'テスト'), assignments: const []));
      await tester.pumpAndSettle();

      expect(find.text(_greeting('テスト')), findsOneWidget, reason: 'theme=$brightness');
      expect(tester.takeException(), isNull);
    }
  });
}
