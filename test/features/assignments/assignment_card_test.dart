import 'package:edu_planner_ai/core/providers/app_providers.dart';
import 'package:edu_planner_ai/core/theme/app_colors.dart';
import 'package:edu_planner_ai/features/assignments/models/assignment_model.dart';
import 'package:edu_planner_ai/features/assignments/widgets/assignment_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../../support/fakes.dart';

Widget _harness({required Widget child, required FakeAssignmentsRepository repo}) {
  return ProviderScope(
    overrides: [
      assignmentsRepositoryProvider.overrideWithValue(repo),
    ],
    child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child))),
  );
}

/// Extracts the first RichText whose plainText equals [title]. Matches both
/// the assignment title Text and the underlying render span used to check
/// [TextDecoration.lineThrough].
TextStyle? _styleForText(WidgetTester tester, String title) {
  final richText = tester.widgetList<RichText>(find.byType(RichText)).firstWhere(
        (rt) => (rt.text.toPlainText()) == title,
        orElse: () => throw StateError('RichText with plainText "$title" not found'),
      );
  return (richText.text as TextSpan).style;
}

void main() {
  // The app runs this in main(); completed cards format their due date.
  setUpAll(() => initializeDateFormatting(null));

  setUp(() => AppColors.applyBrightness(Brightness.dark));
  tearDown(() => AppColors.applyBrightness(Brightness.dark));

  testWidgets('renders title, subject, and status pill', (tester) async {
    final assignment = buildAssignment(
      id: 'a1',
      title: '数学ワークシート',
      subject: '数学',
      status: AssignmentStatus.inProgress,
      progress: 0.4,
      dueDate: DateTime.now().add(const Duration(days: 2)),
    );

    await tester.pumpWidget(_harness(
      repo: FakeAssignmentsRepository(initial: [assignment]),
      child: AssignmentCard(assignment: assignment),
    ));
    await tester.pumpAndSettle();

    expect(find.text('数学ワークシート'), findsOneWidget);
    expect(find.text('数学'), findsOneWidget);
    expect(find.text('進行中'), findsOneWidget, reason: 'inProgress status pill');
    expect(find.text('40% 完了'), findsOneWidget);
  });

  testWidgets('completed state applies line-through decoration to the title', (tester) async {
    final assignment = buildAssignment(
      id: 'a2',
      title: '完了済み課題',
      subject: '英語',
      status: AssignmentStatus.completed,
      progress: 1.0,
    );

    await tester.pumpWidget(_harness(
      repo: FakeAssignmentsRepository(initial: [assignment]),
      child: AssignmentCard(assignment: assignment),
    ));
    await tester.pumpAndSettle();

    final style = _styleForText(tester, '完了済み課題');
    expect(style, isNotNull);
    expect(style!.decoration, TextDecoration.lineThrough);
    expect(style.color, AppColors.textMuted, reason: 'completed titles use muted color');
    expect(find.text('完了'), findsOneWidget, reason: 'status pill reads 完了');
  });

  testWidgets('not-started title has no strikethrough', (tester) async {
    final assignment = buildAssignment(
      id: 'a3',
      title: 'まだ手つかず',
      status: AssignmentStatus.notStarted,
    );

    await tester.pumpWidget(_harness(
      repo: FakeAssignmentsRepository(initial: [assignment]),
      child: AssignmentCard(assignment: assignment),
    ));
    await tester.pumpAndSettle();

    final style = _styleForText(tester, 'まだ手つかず');
    expect(style?.decoration ?? TextDecoration.none, TextDecoration.none);
  });

  testWidgets('tapping the checkbox toggles status via the repository', (tester) async {
    final assignment = buildAssignment(
      id: 'a4',
      title: 'チェック対象',
      status: AssignmentStatus.notStarted,
    );
    final repo = FakeAssignmentsRepository(initial: [assignment]);

    await tester.pumpWidget(_harness(
      repo: repo,
      child: AssignmentCard(assignment: assignment),
    ));
    await tester.pumpAndSettle();

    // The card has exactly two GestureDetectors with onTap: the outer one
    // opens the detail sheet, the inner one is the checkbox. The checkbox is
    // the second in document order.
    final detectors = find.byType(GestureDetector);
    expect(detectors, findsNWidgets(2));

    await tester.tap(detectors.at(1), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(repo.statusProgressCalls, hasLength(1));
    expect(repo.statusProgressCalls.single.id, 'a4');
    expect(repo.statusProgressCalls.single.status, AssignmentStatus.completed,
        reason: 'notStarted → completed on tap');
    expect(repo.statusProgressCalls.single.progress, 1.0, reason: 'completed ⇒ progress 1.0');
  });

  testWidgets('tapping the checkbox on a completed assignment toggles back to notStarted', (tester) async {
    final assignment = buildAssignment(
      id: 'a5',
      title: '取り消し対象',
      status: AssignmentStatus.completed,
    );
    final repo = FakeAssignmentsRepository(initial: [assignment]);

    await tester.pumpWidget(_harness(
      repo: repo,
      child: AssignmentCard(assignment: assignment),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(GestureDetector).at(1), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(repo.statusProgressCalls.single.status, AssignmentStatus.notStarted);
    expect(repo.statusProgressCalls.single.progress, 0.0, reason: 'unticking resets progress');
  });
}
