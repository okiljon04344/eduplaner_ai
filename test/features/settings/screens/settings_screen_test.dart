import 'package:edu_planner_ai/core/l10n/app_strings.dart';
import 'package:edu_planner_ai/core/providers/app_providers.dart';
import 'package:edu_planner_ai/core/providers/locale_provider.dart';
import 'package:edu_planner_ai/core/providers/theme_provider.dart';
import 'package:edu_planner_ai/core/theme/app_colors.dart';
import 'package:edu_planner_ai/features/assignments/providers/assignments_provider.dart';
import 'package:edu_planner_ai/features/auth/models/user_model.dart';
import 'package:edu_planner_ai/features/auth/providers/auth_provider.dart';
import 'package:edu_planner_ai/features/groups/models/study_group_model.dart';
import 'package:edu_planner_ai/features/groups/providers/groups_provider.dart';
import 'package:edu_planner_ai/features/school/school_providers.dart';
import 'package:edu_planner_ai/features/settings/screens/settings_screen.dart';
import 'package:edu_planner_ai/features/timetable/providers/timetable_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toastification/toastification.dart';

import '../../../support/fakes.dart';

Widget _harness({
  UserModel? user,
  StudyGroupModel? group,
  ({bool teacher, bool admin}) role = (teacher: false, admin: false),
  FakeAuthRepository? authRepo,
  FakeGroupsRepository? groupsRepo,
}) {
  return ProviderScope(
    overrides: [
      currentUserProvider.overrideWithValue(user),
      themeProvider.overrideWith(ThemeNotifier.new),
      localeProvider.overrideWith(LocaleNotifier.new),
      schoolRoleProvider.overrideWithValue(role),
      myGroupProvider.overrideWith((_) => Stream.value(group)),
      groupsRepositoryProvider.overrideWithValue(groupsRepo ?? FakeGroupsRepository(currentGroup: group)),
      authRepositoryProvider.overrideWithValue(authRepo ?? FakeAuthRepository(currentUser: user)),
      timetableStreamProvider.overrideWith((_) => Stream.value(const [])),
      assignmentsStreamProvider.overrideWith((_) => Stream.value(const [])),
    ],
    child: const ToastificationWrapper(
      child: MaterialApp(
        home: SettingsScreen(),
      ),
    ),
  );
}

void _setupTallView(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  setUp(() {
    AppColors.applyBrightness(Brightness.dark);
    SharedPreferences.setMockInitialValues({
      'notifications_enabled': true,
      'theme_mode': 'system',
      'locale': 'ja',
    });
  });

  group('SettingsScreen', () {
    testWidgets('renders all section titles and key items in Japanese', (tester) async {
      _setupTallView(tester);
      final user = buildUser(
        name: '山田 太郎',
        email: 'yamada@example.com',
        school: '東京工科大学',
      );

      await tester.pumpWidget(_harness(user: user));
      await tester.pumpAndSettle();

      // Screen title
      expect(find.text(AppStrings.t('set_title')), findsOneWidget, reason: '設定 app bar');

      // Profile info
      expect(find.text('山田 太郎'), findsOneWidget);
      expect(find.text('yamada@example.com'), findsOneWidget);

      // Section titles
      expect(find.text(AppStrings.t('settings_school_info')), findsOneWidget, reason: '学校情報');
      expect(find.text(AppStrings.t('settings_section_ai')), findsOneWidget, reason: 'AI学習アシスタント');
      expect(find.text(AppStrings.t('set_class_share')), findsOneWidget, reason: 'クラス全体での共有');
      expect(find.text(AppStrings.t('settings_section_notifications')), findsOneWidget, reason: '通知');
      expect(find.text(AppStrings.t('settings_section_display')), findsOneWidget, reason: '表示・テーマ');
      expect(find.text(AppStrings.t('settings_section_other')), findsOneWidget, reason: 'その他');

      // Theme options
      expect(find.text(AppStrings.t('set_theme_light')), findsOneWidget, reason: 'ライト');
      expect(find.text(AppStrings.t('set_theme_system')), findsOneWidget, reason: '端末');
      expect(find.text(AppStrings.t('set_theme_dark')), findsOneWidget, reason: 'ダーク');

      // Logout & Delete account buttons
      expect(find.text(AppStrings.t('set_logout')), findsOneWidget, reason: 'ログアウト');
      expect(find.text(AppStrings.t('set_delete_account')), findsOneWidget, reason: 'アカウント削除');
    });

    testWidgets('falls back to default user name when user name is empty', (tester) async {
      final user = buildUser(name: '', email: 'guest@example.com');

      await tester.pumpWidget(_harness(user: user));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.t('set_user_fallback')), findsOneWidget, reason: 'ユーザー');
    });

    testWidgets('renders teacher and admin rows when user has teacher/admin role', (tester) async {
      final user = buildUser();

      await tester.pumpWidget(_harness(
        user: user,
        role: (teacher: true, admin: true),
      ));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.t('teacher_title')), findsOneWidget, reason: '教員メニュー');
      expect(find.text(AppStrings.t('school_admin_title')), findsOneWidget, reason: '学校の管理');
    });

    testWidgets('tapping logout button displays confirmation dialog in Japanese', (tester) async {
      _setupTallView(tester);
      final user = buildUser();
      await tester.pumpWidget(_harness(user: user));
      await tester.pumpAndSettle();

      await tester.tap(find.text(AppStrings.t('set_logout')));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text(AppStrings.t('set_logout_msg')), findsOneWidget, reason: 'ログアウトしますか？');
      expect(find.text(AppStrings.t('common_cancel')), findsOneWidget);
    });

    testWidgets('tapping delete account button displays confirmation dialog in Japanese', (tester) async {
      _setupTallView(tester);
      final user = buildUser();
      await tester.pumpWidget(_harness(user: user));
      await tester.pumpAndSettle();

      await tester.tap(find.text(AppStrings.t('set_delete_account')));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text(AppStrings.t('set_delete_msg')), findsOneWidget);
      expect(find.text(AppStrings.t('set_delete_confirm')), findsOneWidget);
      expect(find.text(AppStrings.t('common_cancel')), findsOneWidget);
    });

    testWidgets('changing theme segment updates theme mode', (tester) async {
      _setupTallView(tester);
      final user = buildUser();
      await tester.pumpWidget(_harness(user: user));
      await tester.pumpAndSettle();

      // Tap dark mode
      await tester.tap(find.text(AppStrings.t('set_theme_dark')));
      await tester.pumpAndSettle();

      final segmentedButton = tester.widget<SegmentedButton<ThemeMode>>(
        find.byType(SegmentedButton<ThemeMode>),
      );
      expect(segmentedButton.selected, {ThemeMode.dark});
    });
  });
}
