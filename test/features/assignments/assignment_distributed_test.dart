import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:edu_planner_ai/core/l10n/app_strings.dart';
import 'package:edu_planner_ai/core/providers/app_providers.dart';
import 'package:edu_planner_ai/core/theme/app_colors.dart';
import 'package:edu_planner_ai/features/assignments/models/assignment_model.dart';
import 'package:edu_planner_ai/features/assignments/providers/assignments_provider.dart';
import 'package:edu_planner_ai/features/assignments/widgets/assignment_card.dart';
import 'package:edu_planner_ai/features/assignments/widgets/assignment_detail_sheet.dart';
import 'package:edu_planner_ai/features/auth/providers/auth_provider.dart';
import 'package:edu_planner_ai/features/home/widgets/assignment_row_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../../support/fakes.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting(null);
    await AppStrings.load('ja');
  });
  setUp(() => AppColors.applyBrightness(Brightness.dark));
  tearDown(() => AppColors.applyBrightness(Brightness.dark));

  group('AssignmentModel distributed fields', () {
    test('fromFirestore reads sourceId and sourceTeacher', () {
      final now = DateTime(2026, 11, 10, 12, 0);
      final doc = FakeDocumentSnapshot('assign_dist_1', {
        'userId': 'student_1',
        'title': '数学演習1',
        'subject': '数学',
        'dueDate': Timestamp.fromDate(now),
        'status': 'notStarted',
        'difficulty': 2,
        'progress': 0.0,
        'createdAt': Timestamp.fromDate(now),
        'sourceId': 'school_assign_99',
        'sourceTeacher': '山田先生',
      });

      final model = AssignmentModel.fromFirestore(doc);

      expect(model.id, 'assign_dist_1');
      expect(model.sourceId, 'school_assign_99');
      expect(model.sourceTeacher, '山田先生');
      expect(model.isDistributed, isTrue);
    });

    test('isDistributed is false when sourceId is null or absent', () {
      final now = DateTime(2026, 11, 10, 12, 0);
      final doc = FakeDocumentSnapshot('assign_personal_1', {
        'userId': 'student_1',
        'title': '英単語暗記',
        'subject': '英語',
        'dueDate': Timestamp.fromDate(now),
        'status': 'inProgress',
        'difficulty': 1,
        'progress': 0.5,
        'createdAt': Timestamp.fromDate(now),
      });

      final model = AssignmentModel.fromFirestore(doc);

      expect(model.sourceId, isNull);
      expect(model.sourceTeacher, isNull);
      expect(model.isDistributed, isFalse);
    });

    test('toFirestore does NOT contain sourceId, sourceTeacher, or sourceDomain', () {
      final assignment = buildAssignment(
        id: 'a1',
        title: '配布課題テスト',
        subject: 'プログラミング',
      ).copyWith(
        sourceId: 'school_assign_100',
        sourceTeacher: '高橋先生',
      );

      final data = assignment.toFirestore();

      expect(data.containsKey('sourceId'), isFalse, reason: 'Firestore rules reject client writes to sourceId');
      expect(data.containsKey('sourceTeacher'), isFalse, reason: 'Firestore rules reject client writes to sourceTeacher');
      expect(data.containsKey('sourceDomain'), isFalse, reason: 'Firestore rules reject client writes to sourceDomain');
    });
  });

  group('AssignmentDetailSheet distributed assignment UI', () {
    testWidgets('hides edit and delete actions and shows progress hint for distributed assignment', (tester) async {
      final distributedAssignment = buildAssignment(
        id: 'dist_a1',
        title: '配布レポート課題',
        subject: '情報',
      ).copyWith(
        sourceId: 'school_assign_77',
        sourceTeacher: '佐藤先生',
      );

      final repo = FakeAssignmentsRepository(initial: [distributedAssignment]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            assignmentsRepositoryProvider.overrideWithValue(repo),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) => ElevatedButton(
                  onPressed: () => showAssignmentDetailSheet(context, ref, distributedAssignment),
                  child: const Text('OpenSheet'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('OpenSheet'));
      await tester.pumpAndSettle();

      // Badge with teacher name is shown
      expect(find.text('佐藤先生から'), findsOneWidget);

      // Hint line is shown
      expect(find.text('この課題の進み具合は担当の先生に表示されます'), findsOneWidget);

      // Edit and delete actions must be completely hidden
      expect(find.text('編集'), findsNothing);
      expect(find.text('削除'), findsNothing);
    });

    testWidgets('shows edit and delete actions for personal assignment', (tester) async {
      final personalAssignment = buildAssignment(
        id: 'pers_a1',
        title: '個人用課題',
        subject: '数学',
      );

      final repo = FakeAssignmentsRepository(initial: [personalAssignment]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            assignmentsRepositoryProvider.overrideWithValue(repo),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) => ElevatedButton(
                  onPressed: () => showAssignmentDetailSheet(context, ref, personalAssignment),
                  child: const Text('OpenSheet'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('OpenSheet'));
      await tester.pumpAndSettle();

      // Edit and delete actions are shown for normal assignments
      expect(find.text('編集'), findsOneWidget);
      expect(find.text('削除'), findsOneWidget);

      // Distributed hint is NOT shown
      expect(find.text('この課題の進み具合は担当の先生に表示されます'), findsNothing);
      expect(find.text('先生から'), findsNothing);
    });

    testWidgets('AssignmentCard and AssignmentRowItem display distributed badge', (tester) async {
      final namedAssignment = buildAssignment(
        id: 'named_1',
        title: '物理レポート',
        subject: '物理',
      ).copyWith(
        sourceId: 'src_1',
        sourceTeacher: '田中',
      );

      final unNamedAssignment = buildAssignment(
        id: 'unnamed_1',
        title: '化学プリント',
        subject: '化学',
      ).copyWith(
        sourceId: 'src_2',
        sourceTeacher: '',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            assignmentsRepositoryProvider.overrideWithValue(FakeAssignmentsRepository()),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  AssignmentCard(assignment: namedAssignment),
                  AssignmentRowItem(assignment: unNamedAssignment),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('田中先生から'), findsOneWidget);
      expect(find.text('先生から'), findsOneWidget);
    });
  });

  group('AssignmentsNotifier guards against forbidden writes', () {
    test('updateAssignment rejects distributed assignment with error message', () async {
      final container = ProviderContainer(
        overrides: [
          assignmentsRepositoryProvider.overrideWithValue(FakeAssignmentsRepository()),
        ],
      );
      addTearDown(container.dispose);

      final distributed = buildAssignment(id: 'd1').copyWith(sourceId: 'src_10');
      final notifier = container.read(assignmentsNotifierProvider.notifier);

      final error = await notifier.updateAssignment(distributed);
      expect(error, AppStrings.t('sas_distributed_no_edit'));
    });

    test('delete rejects distributed assignment with error message', () async {
      final distributed = buildAssignment(id: 'd2', userId: 'u1').copyWith(sourceId: 'src_20');
      final container = ProviderContainer(
        overrides: [
          currentUserProvider.overrideWith((ref) => buildUser(uid: 'u1')),
          assignmentsRepositoryProvider.overrideWithValue(FakeAssignmentsRepository(initial: [distributed])),
        ],
      );
      addTearDown(container.dispose);

      // Ensure stream has loaded the assignment into state
      await container.read(assignmentsStreamProvider.future);

      final notifier = container.read(assignmentsNotifierProvider.notifier);
      final error = await notifier.delete('d2');
      expect(error, AppStrings.t('sas_distributed_no_delete'));
    });
  });
}
