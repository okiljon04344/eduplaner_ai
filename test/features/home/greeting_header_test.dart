import 'package:edu_planner_ai/core/theme/app_colors.dart';
import 'package:edu_planner_ai/features/assignments/models/assignment_model.dart';
import 'package:edu_planner_ai/features/assignments/providers/assignments_provider.dart';
import 'package:edu_planner_ai/features/auth/models/user_model.dart';
import 'package:edu_planner_ai/features/auth/providers/auth_provider.dart';
import 'package:edu_planner_ai/features/home/widgets/greeting_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fakes.dart';

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
  setUp(() => AppColors.applyBrightness(Brightness.dark));
  tearDown(() => AppColors.applyBrightness(Brightness.dark));

  testWidgets('renders "やあ、<name>さん 👋" greeting for the current user', (tester) async {
    await tester.pumpWidget(_harness(
      user: buildUser(name: '田中太郎'),
      assignments: const [],
    ));
    await tester.pumpAndSettle();

    expect(find.text('やあ、田中太郎さん 👋'), findsOneWidget);
    expect(find.text('オンライン'), findsOneWidget);
  });

  testWidgets('falls back to "ゲスト" when no user is signed in', (tester) async {
    await tester.pumpWidget(_harness(user: null, assignments: const []));
    await tester.pumpAndSettle();

    expect(find.text('やあ、ゲストさん 👋'), findsOneWidget);
  });

  testWidgets('shows school name as subtitle when the user has one', (tester) async {
    await tester.pumpWidget(_harness(
      user: buildUser(name: '山田花子', school: '東京専門学校'),
      assignments: const [],
    ));
    await tester.pumpAndSettle();

    expect(find.text('東京専門学校'), findsOneWidget);
    expect(find.text('今日も一日、頑張ろう！'), findsNothing);
  });

  testWidgets('falls back to encouragement message when school is empty', (tester) async {
    await tester.pumpWidget(_harness(
      user: buildUser(name: '山田花子'),
      assignments: const [],
    ));
    await tester.pumpAndSettle();

    expect(find.text('今日も一日、頑張ろう！'), findsOneWidget);
  });

  testWidgets('shows no urgent badge when there are 0 urgent assignments', (tester) async {
    await tester.pumpWidget(_harness(
      user: buildUser(),
      assignments: [
        // due 30 days out -> not urgent
        buildAssignment(dueDate: DateTime.now().add(const Duration(days: 30))),
      ],
    ));
    await tester.pumpAndSettle();

    // Only digits/9+ text appears in the badge; none should be present.
    expect(find.text('9+'), findsNothing);
    for (final n in ['1', '2', '3', '4', '5', '6', '7', '8', '9']) {
      expect(find.text(n), findsNothing, reason: 'no badge digit "$n" when urgent count is 0');
    }
  });

  testWidgets('shows the urgent badge with the correct number when >0', (tester) async {
    final today = DateTime.now();
    await tester.pumpWidget(_harness(
      user: buildUser(),
      assignments: [
        buildAssignment(id: 'a', dueDate: today),
        buildAssignment(id: 'b', dueDate: today.add(const Duration(days: 1))),
      ],
    ));
    await tester.pumpAndSettle();

    expect(find.text('2'), findsOneWidget, reason: 'badge shows the raw count');
  });

  testWidgets('caps the urgent badge at "9+"', (tester) async {
    final today = DateTime.now();
    await tester.pumpWidget(_harness(
      user: buildUser(),
      assignments: List.generate(
        12,
        (i) => buildAssignment(
          id: 'a$i',
          dueDate: today.add(Duration(days: i % 4)),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('9+'), findsOneWidget);
  });

  testWidgets('shows the user\'s first-character initial in the avatar', (tester) async {
    await tester.pumpWidget(_harness(
      user: buildUser(name: 'Alice'),
      assignments: const [],
    ));
    await tester.pumpAndSettle();

    expect(find.text('A'), findsOneWidget);
  });

  testWidgets('renders cleanly in both dark and light themes', (tester) async {
    for (final brightness in [Brightness.dark, Brightness.light]) {
      AppColors.applyBrightness(brightness);
      await tester.pumpWidget(_harness(
        user: buildUser(name: 'テスト'),
        assignments: const [],
      ));
      await tester.pumpAndSettle();

      expect(find.text('やあ、テストさん 👋'), findsOneWidget, reason: 'theme=$brightness');
      expect(tester.takeException(), isNull);
    }
  });
}
