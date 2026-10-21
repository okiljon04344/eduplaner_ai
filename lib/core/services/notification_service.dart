import 'dart:async';
import 'dart:ui' show Color;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import '../../core/constants/periods.dart';
import '../../core/l10n/app_strings.dart';
import '../../features/assignments/models/assignment_model.dart';
import '../../features/timetable/models/class_model.dart';

abstract class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;
  static bool _enabled = true;

  static bool get isEnabled => _enabled;

  // Must match default_notification_channel_id in AndroidManifest.xml and the
  // channelId in functions/index.js.
  static const _channelId = 'eduplanner_reminders';

  static AndroidNotificationDetails get _androidDetails => AndroidNotificationDetails(
    _channelId,
    AppStrings.t('notif_channel_name'),
    channelDescription: AppStrings.t('notif_channel_desc'),
    importance: Importance.high,
    priority: Priority.high,
    icon: 'ic_stat_notify',
    color: const Color(0xFF059669),
  );

  static NotificationDetails get _details => NotificationDetails(android: _androidDetails, iOS: const DarwinNotificationDetails());

  static Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool('notifications_enabled') ?? true;
    } catch (e) {
      debugPrint('Notification pref read error: $e');
    }
    const androidSettings = AndroidInitializationSettings('ic_stat_notify');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    await _plugin.initialize(
      const InitializationSettings(android: androidSettings, iOS: iosSettings),
      onDidReceiveNotificationResponse: _onNotificationTap,
    );
    _initialized = true;
    // FCM pushes name this channel; it must exist before the first one lands
    // or Android files them under its fallback "Miscellaneous" channel.
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(AndroidNotificationChannel(
          _channelId,
          AppStrings.t('notif_channel_name'),
          description: AppStrings.t('notif_channel_desc'),
          importance: Importance.high,
        ));

    // Web push requires a `firebase-messaging-sw.js` service worker file at
    // the site root (VAPID key setup, HTTPS-only registration, etc.) that
    // this project doesn't ship — without it, `getToken()` hangs forever
    // registering a service worker for a script that 404s. Skip entirely on
    // web rather than leave the browser with a permanently-stuck SW
    // registration; class/assignment reminders still work via the local
    // notifications plugin above on every platform.
    if (!_pushSupported) return;

    try {
      await FirebaseMessaging.instance.requestPermission();
      FirebaseMessaging.onMessage.listen(_onForegroundMessage);
      FirebaseMessaging.onMessageOpenedApp.listen(_onMessageOpenedApp);
      // Store the token for whoever is signed in *now or later*: at app
      // start on a fresh install nobody is signed in yet, so a one-shot
      // write here would never happen. Also re-store on token rotation.
      FirebaseAuth.instance.authStateChanges().listen((user) {
        if (user != null && _enabled) unawaited(_storeToken(user.uid));
      });
      FirebaseMessaging.instance.onTokenRefresh.listen((token) {
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid != null && _enabled) unawaited(_storeToken(uid, token));
      });
    } catch (e) {
      debugPrint('Firebase messaging init error: $e');
    }
  }

  /// Web needs a `firebase-messaging-sw.js` service worker this project
  /// doesn't ship (`getToken()` hangs forever without it), and
  /// Windows/Linux have no native push transport (`requestPermission()`/
  /// `getToken()` can hang there too). Local reminders don't depend on this.
  static bool get _pushSupported =>
      !kIsWeb &&
      defaultTargetPlatform != TargetPlatform.windows &&
      defaultTargetPlatform != TargetPlatform.linux;

  static Future<void> _storeToken(String uid, [String? token]) async {
    try {
      token ??= await FirebaseMessaging.instance.getToken();
      if (token == null) return;
      await FirebaseFirestore.instance.collection('users').doc(uid).set(
        {'fcmToken': token},
        SetOptions(merge: true),
      );
    } catch (e) {
      debugPrint('FCM token store error: $e');
    }
  }

  static void _onNotificationTap(NotificationResponse response) {
    debugPrint('Notification tapped: ${response.payload}');
  }

  static void _onForegroundMessage(RemoteMessage message) {
    debugPrint('Foreground message received: ${message.messageId}');
    if (!_enabled) return;
    final n = message.notification;
    if (n == null) return;
    unawaited(_plugin.show(
      message.messageId?.hashCode ?? DateTime.now().millisecondsSinceEpoch.toSigned(32),
      n.title,
      n.body,
      _details,
    ));
  }

  static void _onMessageOpenedApp(RemoteMessage message) {
    debugPrint('Message opened app: ${message.messageId}');
  }

  /// Updates the user's notification preference, persists it to
  /// [SharedPreferences], and either clears all active reminders + unlinks FCM
  /// (when disabled) or re-registers FCM + reschedules reminders (when enabled).
  static Future<void> setEnabled(
    bool enabled, {
    String? uid,
    Iterable<ClassModel> classes = const [],
    Iterable<AssignmentModel> assignments = const [],
  }) async {
    _enabled = enabled;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('notifications_enabled', enabled);
    } catch (e) {
      debugPrint('Notification pref write error: $e');
    }
    if (!enabled) {
      try {
        await cancelAll();
      } catch (e) {
        debugPrint('Cancel reminders error: $e');
      }
      if (uid != null && uid.isNotEmpty) {
        try {
          await unregisterPushToken(uid);
        } catch (e) {
          debugPrint('Unregister push token error: $e');
        }
      }
      return;
    }
    if (uid != null && uid.isNotEmpty && _pushSupported) {
      unawaited(_storeToken(uid));
    }
    await syncAllReminders(classes: classes, assignments: assignments);
  }

  /// Schedules local reminders for [classes] and incomplete [assignments]
  /// when notifications are initialized and enabled. Safe no-op in unit tests
  /// (where [initialize] is not called) or when notifications are disabled.
  static Future<void> syncAllReminders({
    Iterable<ClassModel> classes = const [],
    Iterable<AssignmentModel> assignments = const [],
  }) async {
    if (!_initialized || !_enabled) return;
    for (final c in classes) {
      try {
        await scheduleClassReminder(c);
      } catch (e) {
        debugPrint('Class reminder sync error: $e');
      }
    }
    for (final a in assignments) {
      if (a.status == AssignmentStatus.completed) continue;
      try {
        await scheduleAssignmentReminders(a);
      } catch (e) {
        debugPrint('Assignment reminder sync error: $e');
      }
    }
  }

  /// Class reminder body for [key]; drops the " ({room})" part when the
  /// (optional) room is blank so it never reads "Math ()".
  @visibleForTesting
  static String classReminderText(String key, ClassModel c) {
    final start = periodStart(c.period);
    final text = AppStrings.t(key, {
      'n': c.period,
      'subject': c.subject,
      'room': c.room.trim(),
      'time': start == null ? '' : formatHm(start),
    });
    // ponytail: heuristic strip; a subject that itself ends in "()" would lose it.
    return c.room.trim().isEmpty ? text.replaceAll(' ()', '').replaceAll('()', '') : text;
  }

  /// Start time of [period] — the same table the timetable/home cards show.
  @visibleForTesting
  static Hm? periodStart(int period) => kPeriodTimes[period]?.start;

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
    final weekday = weekdayFromKanji(c.dayOfWeek);
    final start = periodStart(c.period);
    if (weekday == null || start == null) return;

    // Clear the previous schedule first: an edit may move the class to a
    // different day/period, and the old weekly reminder must not survive.
    await cancelClassReminders(c.id);
    if (!_enabled) return;

    final classStart = _nextWeekdayTime(weekday: weekday, hour: start.$1, minute: start.$2);
    final morning = _nextWeekdayTime(weekday: weekday, hour: 7, minute: 0);
    var beforeClass = classStart.subtract(const Duration(minutes: 30));
    // Added less than 30 min before the class: start the weekly repeat next
    // week instead of never scheduling it at all.
    if (!beforeClass.isAfter(tz.TZDateTime.now(tz.local))) {
      beforeClass = beforeClass.add(const Duration(days: 7));
    }

    // The morning notice and the pre-class notice are independent
    // notifications (different ids/times) — schedule them concurrently.
    // Ids derive from the document id (stable across edits), never from
    // `c.hashCode`, which changes whenever any field changes.
    await Future.wait([
      _schedule(
        c.id.hashCode,
        AppStrings.t('notif_class_rem_title'),
        classReminderText('notif_class_rem_today', c),
        morning,
        matchComponents: DateTimeComponents.dayOfWeekAndTime,
      ),
      _schedule(
        c.id.hashCode + 1,
        AppStrings.t('notif_class_rem_title'),
        classReminderText('notif_class_rem_soon', c),
        beforeClass,
        matchComponents: DateTimeComponents.dayOfWeekAndTime,
      ),
    ]);
  }

  static Future<void> cancelClassReminders(String id) {
    return Future.wait([
      _plugin.cancel(id.hashCode),
      _plugin.cancel(id.hashCode + 1),
    ]);
  }

  /// Drops every pending local reminder — used on sign-out so the next
  /// account on this device doesn't inherit the previous user's schedule.
  static Future<void> cancelAll() => _plugin.cancelAll();

  /// Unlinks this device from [uid]'s push notifications (sign-out): clears
  /// the stored token so `onClassStatusChanged` stops targeting it, then
  /// invalidates the token itself.
  static Future<void> unregisterPushToken(String uid) async {
    if (!_pushSupported) return;
    // `update`, not `set(merge)`: right after deleteAccount the doc is gone,
    // and a merge-set would recreate it as an empty orphan.
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).update({'fcmToken': FieldValue.delete()});
    } catch (e) {
      debugPrint('FCM token unlink skipped: $e');
    }
    await FirebaseMessaging.instance.deleteToken();
  }

  static Future<void> scheduleAssignmentReminders(AssignmentModel a) async {
    await cancelAssignmentReminders(a.id);
    if (!_enabled || a.status == AssignmentStatus.completed) return;

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
