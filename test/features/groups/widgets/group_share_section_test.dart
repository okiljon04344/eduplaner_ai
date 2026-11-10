import 'package:edu_planner_ai/core/l10n/app_strings.dart';
import 'package:edu_planner_ai/core/providers/app_providers.dart';
import 'package:edu_planner_ai/core/theme/app_colors.dart';
import 'package:edu_planner_ai/features/auth/providers/auth_provider.dart';
import 'package:edu_planner_ai/features/groups/models/study_group_model.dart';
import 'package:edu_planner_ai/features/groups/providers/groups_provider.dart';
import 'package:edu_planner_ai/features/settings/widgets/group_share_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toastification/toastification.dart';

import '../../../support/fakes.dart';

Widget _harness({
  required Widget child,
  StudyGroupModel? group,
  bool isLoading = false,
  FakeGroupsRepository? repo,
}) {
  return ProviderScope(
    overrides: [
      currentUserProvider.overrideWithValue(buildUser(uid: 'u1')),
      groupsRepositoryProvider.overrideWithValue(repo ?? FakeGroupsRepository(currentGroup: group)),
      myGroupProvider.overrideWith(
        (_) => isLoading ? const Stream.empty() : Stream.value(group),
      ),
    ],
    child: ToastificationWrapper(
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: child),
        ),
      ),
    ),
  );
}

void main() {
  setUp(() {
    AppColors.applyBrightness(Brightness.dark);
  });

  group('GroupShareSection widget', () {
    testWidgets('renders create and join buttons in Japanese when not in a group', (tester) async {
      await tester.pumpWidget(_harness(
        child: const GroupShareSection(),
        group: null,
      ));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.t('grp_create')), findsOneWidget, reason: 'グループを作成 button');
      expect(find.text(AppStrings.t('grp_join')), findsOneWidget, reason: 'コードで参加 button');
    });

    testWidgets('tapping グループを作成 opens prompt dialog with Japanese labels', (tester) async {
      await tester.pumpWidget(_harness(
        child: const GroupShareSection(),
        group: null,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text(AppStrings.t('grp_create')));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text(AppStrings.t('grp_create_hint')), findsOneWidget);
      expect(find.text(AppStrings.t('grp_create_btn')), findsOneWidget);
      expect(find.text(AppStrings.t('common_cancel')), findsOneWidget);
    });

    testWidgets('tapping コードで参加 opens prompt dialog with Japanese labels', (tester) async {
      await tester.pumpWidget(_harness(
        child: const GroupShareSection(),
        group: null,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text(AppStrings.t('grp_join')));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text(AppStrings.t('grp_join_hint')), findsOneWidget);
      expect(find.text(AppStrings.t('grp_join_btn')), findsOneWidget);
      expect(find.text(AppStrings.t('common_cancel')), findsOneWidget);
    });

    testWidgets('renders group details, invite code, and leave button when user has a group', (tester) async {
      final group = buildStudyGroup(
        name: '情報工学科2組',
        code: 'XYZ888',
        memberIds: ['u1', 'u2', 'u3'],
      );

      await tester.pumpWidget(_harness(
        child: const GroupShareSection(),
        group: group,
      ));
      await tester.pumpAndSettle();

      expect(find.text('情報工学科2組'), findsOneWidget);
      expect(find.text(AppStrings.t('grp_members').replaceAll('{n}', '3')), findsOneWidget,
          reason: 'member count in Japanese');
      expect(find.text('XYZ888'), findsOneWidget, reason: 'share code');
      expect(find.text(AppStrings.t('common_copy')), findsOneWidget, reason: 'copy button');
      expect(find.text(AppStrings.t('grp_leave')), findsOneWidget, reason: 'leave button');
    });

    testWidgets('tapping グループから退出 opens confirm dialog with Japanese warning', (tester) async {
      final group = buildStudyGroup(
        name: '共有グループ',
        code: 'GRP123',
        memberIds: ['u1'],
      );

      await tester.pumpWidget(_harness(
        child: const GroupShareSection(),
        group: group,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text(AppStrings.t('grp_leave')));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.t('grp_leave_msg')), findsOneWidget,
          reason: '本当にこのグループから退出しますか？ confirmation message');
      expect(find.text(AppStrings.t('common_cancel')), findsOneWidget);
    });
  });
}
