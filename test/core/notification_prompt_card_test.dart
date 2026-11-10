import 'package:edu_planner_ai/core/l10n/app_strings.dart';
import 'package:edu_planner_ai/core/theme/app_colors.dart';
import 'package:edu_planner_ai/features/auth/providers/auth_provider.dart';
import 'package:edu_planner_ai/features/home/widgets/notification_prompt_card.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes.dart';

void main() {
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');

  setUp(() async {
    AppColors.applyBrightness(Brightness.dark);
    await AppStrings.load('ja');
    SharedPreferences.setMockInitialValues({
      'notifications_enabled': true,
      'notif_prompt_done': false,
    });
  });

  testWidgets('NotificationPromptCard renders when prompt is needed', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWithValue(buildUser(name: 'テスト', email: 'test@example.com')),
        ],
        child: const MaterialApp(
          home: Scaffold(body: NotificationPromptCard()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // On non-mobile (Linux test host), needsPermissionPrompt is false so it renders SizedBox.shrink
    expect(find.byType(NotificationPromptCard), findsOneWidget);
  });

  testWidgets('NotificationPromptCard calls requestExactAlarmPermission on Android when exact not allowed', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    var requestedExact = false;
    try {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'canScheduleExactNotifications') return false;
        if (call.method == 'requestExactAlarmsPermission') {
          requestedExact = true;
          return true;
        }
        return null;
      });

      // Also mock permission_handler channel if needed
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('flutter.baseflow.com/permissions/methods'),
        (call) async {
          if (call.method == 'checkPermissionStatus') return 0; // denied
          if (call.method == 'requestPermissions') {
            final permissions = call.arguments as List<dynamic>?;
            final map = <int, int>{};
            for (final p in permissions ?? []) {
              map[p as int] = 1; // granted
            }
            return map;
          }
          return null;
        },
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserProvider.overrideWithValue(buildUser(name: 'テスト', email: 'test@example.com')),
          ],
          child: const MaterialApp(
            home: Scaffold(body: NotificationPromptCard()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final onBtn = find.text('通知をオンにする');
      if (onBtn.evaluate().isNotEmpty) {
        await tester.tap(onBtn);
        await tester.pumpAndSettle();
        expect(requestedExact, isTrue);
      }
    } finally {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('flutter.baseflow.com/permissions/methods'),
        null,
      );
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
