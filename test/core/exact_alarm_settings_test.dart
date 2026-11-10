import 'package:edu_planner_ai/core/l10n/app_strings.dart';
import 'package:edu_planner_ai/core/providers/app_providers.dart';
import 'package:edu_planner_ai/core/providers/locale_provider.dart';
import 'package:edu_planner_ai/core/providers/theme_provider.dart';
import 'package:edu_planner_ai/core/services/notification_service.dart';
import 'package:edu_planner_ai/core/theme/app_colors.dart';
import 'package:edu_planner_ai/features/assignments/providers/assignments_provider.dart';
import 'package:edu_planner_ai/features/auth/providers/auth_provider.dart';
import 'package:edu_planner_ai/features/groups/providers/groups_provider.dart';
import 'package:edu_planner_ai/features/school/school_providers.dart';
import 'package:edu_planner_ai/features/settings/screens/settings_screen.dart';
import 'package:edu_planner_ai/features/timetable/providers/timetable_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toastification/toastification.dart';

import '../support/fakes.dart';

Widget _harness() {
  return ProviderScope(
    overrides: [
      currentUserProvider.overrideWithValue(buildUser(name: 'テスト', email: 'test@example.com')),
      themeProvider.overrideWith(ThemeNotifier.new),
      localeProvider.overrideWith(LocaleNotifier.new),
      schoolRoleProvider.overrideWithValue((teacher: false, admin: false)),
      myGroupProvider.overrideWith((_) => Stream.value(null)),
      groupsRepositoryProvider.overrideWithValue(FakeGroupsRepository()),
      authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
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

void main() {
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');

  setUp(() async {
    AppColors.applyBrightness(Brightness.dark);
    await AppStrings.load('ja');
    SharedPreferences.setMockInitialValues({
      'notifications_enabled': true,
      'theme_mode': 'system',
      'locale': 'ja',
    });
  });

  testWidgets('shows exact alarm row on Android when permission is needed', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'canScheduleExactNotifications') return false;
        if (call.method == 'requestExactAlarmsPermission') return true;
        return null;
      });

      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;

      await NotificationService.refreshExactAlarmPermission();
      expect(NotificationService.needsExactAlarmPermission, isTrue);

      await tester.pumpWidget(_harness());
      await tester.pumpAndSettle();

      expect(find.text('正確な時間に通知する'), findsOneWidget);
      expect(find.text('許可しないと通知が最大1時間遅れることがあります'), findsOneWidget);
      expect(find.text('許可する'), findsOneWidget);

      // Simulate app resuming
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(find.text('正確な時間に通知する'), findsOneWidget);
    } finally {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('hides exact alarm row after permission is granted on resumed', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    var exactGranted = false;
    try {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'canScheduleExactNotifications') return exactGranted;
        if (call.method == 'requestExactAlarmsPermission') {
          exactGranted = true;
          return true;
        }
        return null;
      });

      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;

      await NotificationService.refreshExactAlarmPermission();
      expect(NotificationService.needsExactAlarmPermission, isTrue);

      await tester.pumpWidget(_harness());
      await tester.pumpAndSettle();

      expect(find.text('正確な時間に通知する'), findsOneWidget);

      // User grants permission in system settings and returns to the app
      exactGranted = true;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(NotificationService.needsExactAlarmPermission, isFalse);
      expect(find.text('正確な時間に通知する'), findsNothing);
    } finally {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('hides exact alarm row on non-Android platform (e.g. iOS)', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;

      await NotificationService.refreshExactAlarmPermission();
      expect(NotificationService.needsExactAlarmPermission, isFalse);

      await tester.pumpWidget(_harness());
      await tester.pumpAndSettle();

      expect(find.text('正確な時間に通知する'), findsNothing);
    } finally {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
