import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import '../../core/l10n/app_strings.dart';
import '../../features/assignments/models/assignment_model.dart';
import '../../features/timetable/models/class_model.dart';

abstract class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();

  static AndroidNotificationDetails get _androidDetails => AndroidNotificationDetails(
    'eduplanner_reminders',
    AppStrings.t('notif_channel_name'),
    channelDescription: AppStrings.t('notif_channel_desc'),
    importance: Importance.high,
    priority: Priority.high,
  );

  static NotificationDetails get _details => NotificationDetails(android: _androidDetails, iOS: const DarwinNotificationDetails());

  static Future<void> initialize() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    await _plugin.initialize(
      const InitializationSettings(android: androidSettings, iOS: iosSettings),
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    // Web push requires a `firebase-messaging-sw.js` service worker file at
    // the site root (VAPID key setup, HTTPS-only registration, etc.) that
    // this project doesn't ship — without it, `getToken()` hangs forever
    // registering a service worker for a script that 404s. Skip entirely on
    // web rather than leave the browser with a permanently-stuck SW
    // registration; class/assignment reminders still work via the local
    // notifications plugin above on every platform.
    if (kIsWeb) return;

    // FCM push tokens aren't wired up to any desktop notification channel,
    // and `requestPermission()`/`getToken()` can hang indefinitely on
    // Windows/Linux (no native push transport there). Skip FCM entirely on
    // desktop, same as the web skip above — local reminders below (used on
    // every platform) don't depend on this and are unaffected.
    if (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux) {
      return;
    }

    try {
      await FirebaseMessaging.instance.requestPermission();
      FirebaseMessaging.onMessage.listen(_onForegroundMessage);
      FirebaseMessaging.onMessageOpenedApp.listen(_onMessageOpenedApp);
      final token = await FirebaseMessaging.instance.getToken();
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (token != null && uid != null) {
        await FirebaseFirestore.instance.collection('users').doc(uid).set(
          {'fcmToken': token},
          SetOptions(merge: true),
        );
      }
    } catch (e) {
      debugPrint('Firebase messaging init error: $e');
    }
  }

  static void _onNotificationTap(NotificationResponse response) {
    debugPrint('Notification tapped: ${response.payload}');
  }

  static void _onForegroundMessage(RemoteMessage message) {
    debugPrint('Foreground message received: ${message.messageId}');
  }

  static void _onMessageOpenedApp(RemoteMessage message) {
    debugPrint('Message opened app: ${message.messageId}');
  }

  static (int, int)? _periodStart(int period) {
    switch (period) {
      case 1:
        return (9, 0);
      case 2:
        return (10, 50);
      case 3:
        return (13, 0);
      case 4:
        return (14, 50);
      case 5:
        return (16, 40);
      case 6:
        return (18, 30);
      default:
        return null;
    }
  }

  static int? _weekday(String day) {
    switch (day) {
      case '月':
        return DateTime.monday;
      case '火':
        return DateTime.tuesday;
      case '水':
        return DateTime.wednesday;
      case '木':
        return DateTime.thursday;
      case '金':
        return DateTime.friday;
      default:
        return null;
    }
  }

  static tz.TZDateTime _nextWeekdayTime({required int weekday, required int hour, required int minute}) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    final diff = (weekday - scheduled.weekday) % 7;
    scheduled = scheduled.add(Duration(days: diff));
    if (!scheduled.isAfter(now)) scheduled = scheduled.add(const Duration(days: 7));
    return scheduled;
  }

  /// Shared `zonedSchedule` call shape used by every reminder below.
  static Future<void> _schedule(
    int id,
    String title,
    String body,
    tz.TZDateTime time, {
    DateTimeComponents? matchComponents,
  }) {
    return _plugin.zonedSchedule(
      id,
      title,
      body,
      time,
      _details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: matchComponents,
    );
  }

  static Future<void> scheduleClassReminder(ClassModel c) async {
    final weekday = _weekday(c.dayOfWeek);
    final start = _periodStart(c.period);
    if (weekday == null || start == null) return;

    final classStart = _nextWeekdayTime(weekday: weekday, hour: start.$1, minute: start.$2);
    final morning = _nextWeekdayTime(weekday: weekday, hour: 7, minute: 0);
    final beforeClass = classStart.subtract(const Duration(minutes: 30));
    final args = {'n': c.period, 'subject': c.subject, 'room': c.room};

    // The morning notice and the pre-class notice are independent
    // notifications (different ids/times) — schedule them concurrently.
    final futures = <Future<void>>[
      _schedule(
        c.hashCode,
        AppStrings.t('notif_class_rem_title'),
        AppStrings.t('notif_class_rem_today', args),
        morning,
        matchComponents: DateTimeComponents.dayOfWeekAndTime,
      ),
    ];
    if (beforeClass.isAfter(tz.TZDateTime.now(tz.local))) {
      futures.add(_schedule(
        c.hashCode + 1,
        AppStrings.t('notif_class_rem_title'),
        AppStrings.t('notif_class_rem_soon', args),
        beforeClass,
        matchComponents: DateTimeComponents.dayOfWeekAndTime,
      ));
    }
    await Future.wait(futures);
  }

  static Future<void> scheduleAssignmentReminders(AssignmentModel a) async {
    await cancelAssignmentReminders(a.id);
    if (a.status == AssignmentStatus.completed) return;

    final dueDay = DateTime(a.dueDate.year, a.dueDate.month, a.dueDate.day);
    final now = tz.TZDateTime.now(tz.local);

    final threeDaysBefore = tz.TZDateTime.from(dueDay.subtract(const Duration(days: 3)).add(const Duration(hours: 9)), tz.local);
    final oneDayBefore = tz.TZDateTime.from(dueDay.subtract(const Duration(days: 1)).add(const Duration(hours: 9)), tz.local);
    final onDueDay = tz.TZDateTime.from(dueDay.add(const Duration(hours: 8)), tz.local);

    final title = AppStrings.t('notif_assign_rem_title');
    final args = {'subject': a.subject, 'title': a.title};

    // The three reminders are independent notifications — schedule the ones
    // that are still in the future concurrently instead of one-by-one.
    final futures = <Future<void>>[];
    if (threeDaysBefore.isAfter(now)) {
      futures.add(_schedule(a.id.hashCode, title, AppStrings.t('notif_assign_rem_3d', args), threeDaysBefore));
    }
    if (oneDayBefore.isAfter(now)) {
      futures.add(_schedule(a.id.hashCode + 1, title, AppStrings.t('notif_assign_rem_1d', args), oneDayBefore));
    }
    if (onDueDay.isAfter(now)) {
      futures.add(_schedule(a.id.hashCode + 2, title, AppStrings.t('notif_assign_rem_today', args), onDueDay));
    }
    await Future.wait(futures);
  }

  static Future<void> cancelAssignmentReminders(String id) {
    return Future.wait([
      _plugin.cancel(id.hashCode),
      _plugin.cancel(id.hashCode + 1),
      _plugin.cancel(id.hashCode + 2),
    ]);
  }
}
