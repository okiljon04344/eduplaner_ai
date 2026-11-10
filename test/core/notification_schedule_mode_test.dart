import 'package:edu_planner_ai/core/services/notification_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('scheduleModeFor', () {
    test('returns exactAllowWhileIdle when exactAllowed is true', () {
      expect(
        scheduleModeFor(exactAllowed: true),
        equals(AndroidScheduleMode.exactAllowWhileIdle),
      );
      expect(
        NotificationService.scheduleModeFor(exactAllowed: true),
        equals(AndroidScheduleMode.exactAllowWhileIdle),
      );
    });

    test('returns inexactAllowWhileIdle when exactAllowed is false', () {
      expect(
        scheduleModeFor(exactAllowed: false),
        equals(AndroidScheduleMode.inexactAllowWhileIdle),
      );
      expect(
        NotificationService.scheduleModeFor(exactAllowed: false),
        equals(AndroidScheduleMode.inexactAllowWhileIdle),
      );
    });
  });

  group('exact alarm permission helpers', () {
    test('non-Android platform refresh returns true and sets isExactAllowed', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final allowed = await NotificationService.refreshExactAlarmPermission();
      expect(allowed, isTrue);
      expect(NotificationService.isExactAllowed, isTrue);
    });

    test('requestExactAlarmPermission on non-Android returns true', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final allowed = await NotificationService.requestExactAlarmPermission();
      expect(allowed, isTrue);
    });

    test('on error (e.g. unmocked Android method channel) returns false', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final allowed = await NotificationService.refreshExactAlarmPermission();
      expect(allowed, isFalse);
      expect(NotificationService.isExactAllowed, isFalse);
    });
  });
}
