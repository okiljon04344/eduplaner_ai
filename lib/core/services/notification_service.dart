import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import '../../features/assignments/models/assignment_model.dart';
import '../../features/timetable/models/class_model.dart';

abstract class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();

  static const _androidDetails = AndroidNotificationDetails(
    'eduplanner_reminders',
    'EduPlanner Reminders',
    channelDescription: '授業と課題のリマインダー通知',
    importance: Importance.high,
    priority: Priority.high,
  );

  static const _details = NotificationDetails(android: _androidDetails, iOS: DarwinNotificationDetails());

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

  static Future<void> scheduleClassReminder(ClassModel c) async {
    final weekday = _weekday(c.dayOfWeek);
    final start = _periodStart(c.period);
    if (weekday == null || start == null) return;

    final classStart = _nextWeekdayTime(weekday: weekday, hour: start.$1, minute: start.$2);
    final morning = _nextWeekdayTime(weekday: weekday, hour: 7, minute: 0);
    final beforeClass = classStart.subtract(const Duration(minutes: 30));

    await _plugin.zonedSchedule(
      c.hashCode,
      '授業リマインダー',
      '${c.period}限 ${c.subject} (${c.room}) が今日あります',
      morning,
      _details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
    );

    if (beforeClass.isAfter(tz.TZDateTime.now(tz.local))) {
      await _plugin.zonedSchedule(
        c.hashCode + 1,
        '授業リマインダー',
        '${c.period}限 ${c.subject} (${c.room}) が30分後に始まります',
        beforeClass,
        _details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
      );
    }
  }

  static Future<void> scheduleAssignmentReminders(AssignmentModel a) async {
    await cancelAssignmentReminders(a.id);
    if (a.status == AssignmentStatus.completed) return;

    final dueDay = DateTime(a.dueDate.year, a.dueDate.month, a.dueDate.day);
    final now = tz.TZDateTime.now(tz.local);

    final threeDaysBefore = tz.TZDateTime.from(dueDay.subtract(const Duration(days: 3)).add(const Duration(hours: 9)), tz.local);
    final oneDayBefore = tz.TZDateTime.from(dueDay.subtract(const Duration(days: 1)).add(const Duration(hours: 9)), tz.local);
    final onDueDay = tz.TZDateTime.from(dueDay.add(const Duration(hours: 8)), tz.local);

    if (threeDaysBefore.isAfter(now)) {
      await _plugin.zonedSchedule(
        a.id.hashCode,
        '課題リマインダー',
        '${a.subject}「${a.title}」の締め切りまで3日です',
        threeDaysBefore,
        _details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      );
    }
    if (oneDayBefore.isAfter(now)) {
      await _plugin.zonedSchedule(
        a.id.hashCode + 1,
        '課題リマインダー',
        '${a.subject}「${a.title}」の締め切りは明日です！',
        oneDayBefore,
        _details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      );
    }
    if (onDueDay.isAfter(now)) {
      await _plugin.zonedSchedule(
        a.id.hashCode + 2,
        '課題リマインダー',
        '今日が締め切り！${a.subject}「${a.title}」を提出しましょう',
        onDueDay,
        _details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      );
    }
  }

  static Future<void> cancelAssignmentReminders(String id) async {
    await _plugin.cancel(id.hashCode);
    await _plugin.cancel(id.hashCode + 1);
    await _plugin.cancel(id.hashCode + 2);
  }
}
