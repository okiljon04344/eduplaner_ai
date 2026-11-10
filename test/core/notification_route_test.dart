import 'package:edu_planner_ai/core/services/notification_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() {
    NotificationService.pendingRoute.value = null;
  });

  group('Route whitelist', () {
    test('contains exactly /home, /timetable, and /assignments', () {
      expect(
        NotificationService.allowedRoutes,
        containsAll(<String>['/home', '/timetable', '/assignments']),
      );
      expect(NotificationService.allowedRoutes, hasLength(3));
    });

    test('isAllowedRoute returns true only for whitelisted routes', () {
      expect(NotificationService.isAllowedRoute('/home'), isTrue);
      expect(NotificationService.isAllowedRoute('/timetable'), isTrue);
      expect(NotificationService.isAllowedRoute('/assignments'), isTrue);

      expect(NotificationService.isAllowedRoute('/settings'), isFalse);
      expect(NotificationService.isAllowedRoute('/'), isFalse);
      expect(NotificationService.isAllowedRoute('/login'), isFalse);
      expect(NotificationService.isAllowedRoute('/quiz'), isFalse);
      expect(NotificationService.isAllowedRoute('/profile-setup'), isFalse);
      expect(NotificationService.isAllowedRoute('/timetable?tab=1'), isFalse);
      expect(NotificationService.isAllowedRoute('/timetable/nested'), isFalse);
      expect(NotificationService.isAllowedRoute(''), isFalse);
      expect(NotificationService.isAllowedRoute('   '), isFalse);
      expect(NotificationService.isAllowedRoute('malicious_intent'), isFalse);
      expect(NotificationService.isAllowedRoute(null), isFalse);
    });

    test('sanitizeRoute returns route if allowed, otherwise null', () {
      expect(NotificationService.sanitizeRoute('/home'), '/home');
      expect(NotificationService.sanitizeRoute('/timetable'), '/timetable');
      expect(NotificationService.sanitizeRoute('/assignments'), '/assignments');

      expect(NotificationService.sanitizeRoute('/settings'), isNull);
      expect(NotificationService.sanitizeRoute('/login'), isNull);
      expect(NotificationService.sanitizeRoute(''), isNull);
      expect(NotificationService.sanitizeRoute(null), isNull);
    });

    test('pendingRoute ValueNotifier emits route updates to listeners', () {
      final notifications = <String?>[];
      void listener() {
        notifications.add(NotificationService.pendingRoute.value);
      }

      NotificationService.pendingRoute.addListener(listener);

      NotificationService.pendingRoute.value = '/timetable';
      NotificationService.pendingRoute.value = '/assignments';
      NotificationService.pendingRoute.value = null;

      NotificationService.pendingRoute.removeListener(listener);

      expect(notifications, ['/timetable', '/assignments', null]);
    });
  });
}
