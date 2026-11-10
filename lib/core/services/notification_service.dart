import 'dart:async';
import 'dart:ui' show Color;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import '../../core/constants/periods.dart';
import '../../core/l10n/app_strings.dart';
import '../../features/assignments/models/assignment_model.dart';
import '../../features/school/models/school.dart';
import '../../features/timetable/models/class_model.dart';

abstract class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;
  static bool _enabled = true;

  static bool get isEnabled => _enabled;

  /// Whitelisted navigation routes that can be opened via notifications.
  static const Set<String> allowedRoutes = {
    '/home',
    '/timetable',
    '/assignments',
  };

  /// Returns true if [route] is non-null and present in [allowedRoutes].
  static bool isAllowedRoute(String? route) =>
      route != null && allowedRoutes.contains(route);

  /// Validates [route] against [allowedRoutes], returning the route if valid
  /// or null if invalid/null.
  static String? sanitizeRoute(String? route) =>
      isAllowedRoute(route) ? route : null;

  /// Holds a pending route requested by tapping a notification or handling an
  /// FCM intent / cold-start launch. Observed in `lib/app.dart`.
  static final ValueNotifier<String?> pendingRoute = ValueNotifier<String?>(null);

  static void _handleRoutePayload(String? route) {
    final validRoute = sanitizeRoute(route);
    if (validRoute != null) {
      pendingRoute.value = validRoute;
    }
  }

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
    // No permission prompt at launch: the home screen asks once the user can
    // see what notifications are for (NotificationPromptCard).
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
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

    // Check cold start from local notification launch details.
    try {
      final launchDetails = await _plugin.getNotificationAppLaunchDetails();
      if (launchDetails?.didNotificationLaunchApp ?? false) {
        _handleRoutePayload(launchDetails?.notificationResponse?.payload);
      }
    } catch (e) {
      debugPrint('Notification launch details error: $e');
    }

    // Web push requires a `firebase-messaging-sw.js` service worker file at
    // the site root (VAPID key setup, HTTPS-only registration, etc.) that
    // this project doesn't ship — without it, `getToken()` hangs forever
    // registering a service worker for a script that 404s. Skip entirely on
    // web rather than leave the browser with a permanently-stuck SW
    // registration; class/assignment reminders still work via the local
    // notifications plugin above on every platform.
    if (!_pushSupported) return;

    try {
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

      // Check cold start from FCM initial message.
      final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
      if (initialMessage != null) {
        final rawRoute = initialMessage.data['route'] as String?;
        final route = rawRoute != null && rawRoute.isNotEmpty ? rawRoute : '/timetable';
        _handleRoutePayload(route);
      }
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

  static const _promptDoneKey = 'notif_prompt_done';

  /// Android/iOS only: the platforms with a runtime notification permission.
  static bool get _hasRuntimePermission =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// True when the home screen should offer to turn notifications on: a
  /// runtime-permission platform, not yet granted, and not answered before.
  static Future<bool> needsPermissionPrompt() async {
    if (!_hasRuntimePermission || !_enabled) return false;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_promptDoneKey) ?? false) return false;
      return !(await Permission.notification.status).isGranted;
    } catch (e) {
      debugPrint('Notification permission check error: $e');
      return false;
    }
  }

  /// Shows the OS permission dialog; returns whether it was granted. Either
  /// answer ends the home-screen prompt (Settings can still turn it on).
  static Future<bool> requestPermission({String? uid}) async {
    await dismissPermissionPrompt();
    if (!_hasRuntimePermission) return true;
    try {
      final granted = (await Permission.notification.request()).isGranted;
      if (granted && uid != null && uid.isNotEmpty && _pushSupported) unawaited(_storeToken(uid));
      return granted;
    } catch (e) {
      debugPrint('Notification permission request error: $e');
      return false;
    }
  }

  static Future<void> dismissPermissionPrompt() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_promptDoneKey, true);
    } catch (e) {
      debugPrint('Notification prompt pref error: $e');
    }
  }

  static Future<void> _storeToken(String uid, [String? token]) async {
    try {
      token ??= await FirebaseMessaging.instance.getToken();
      if (token == null) return;
      // `language` lets the server write pushes in the app's language.
      await FirebaseFirestore.instance.collection('users').doc(uid).set(
        {'fcmToken': token, 'language': AppStrings.currentLocale},
        SetOptions(merge: true),
      );
    } catch (e) {
      debugPrint('FCM token store error: $e');
    }
  }

  static void _onNotificationTap(NotificationResponse response) {
    debugPrint('Notification tapped: ${response.payload}');
    _handleRoutePayload(response.payload);
  }

  static void _onForegroundMessage(RemoteMessage message) {
    debugPrint('Foreground message received: ${message.messageId}');
    if (!_enabled) return;
    final n = message.notification;
    if (n == null) return;
    final rawRoute = message.data['route'] as String?;
    final route = rawRoute != null && rawRoute.isNotEmpty ? rawRoute : '/timetable';
    final payload = sanitizeRoute(route) ?? '/timetable';
    unawaited(_plugin.show(
      message.messageId?.hashCode ?? DateTime.now().millisecondsSinceEpoch.toSigned(32),
      n.title,
      n.body,
      _details,
      payload: payload,
    ));
  }

  static void _onMessageOpenedApp(RemoteMessage message) {
    debugPrint('Message opened app: ${message.messageId}');
    final rawRoute = message.data['route'] as String?;
    final route = rawRoute != null && rawRoute.isNotEmpty ? rawRoute : '/timetable';
    _handleRoutePayload(route);
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
    try {
      await scheduleMorningReminders(classes);
    } catch (e) {
      debugPrint('Morning reminder sync error: $e');
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

  /// Stable notification id for morning summary notifications per weekday (1..7).
  @visibleForTesting
  static int morningReminderId(int weekday) => 7000 + weekday;

  /// Morning digest title key `notif_morning_title` ("今日の授業は{n}コマ").
  @visibleForTesting
  static String morningDigestTitle(int count) {
    return AppStrings.t('notif_morning_title', {'n': count});
  }

  /// Builds the morning summary body: classes sorted by period joined like
  /// "1限 数学 · 2限 英語", truncated to ~120 characters.
  @visibleForTesting
  static String morningDigestBody(Iterable<ClassModel> classes, {int maxLength = 120}) {
    if (classes.isEmpty) return '';
    final sorted = classes.toList()..sort((a, b) {
      final pComp = a.period.compareTo(b.period);
      if (pComp != 0) return pComp;
      return a.subject.compareTo(b.subject);
    });
    final parts = sorted.map((c) {
      final periodLabel = AppStrings.t('tt_period', {'n': c.period});
      final subject = c.subject.trim();
      return '$periodLabel $subject';
    });
    final joined = parts.join(' · ');
    if (joined.length <= maxLength) return joined;
    if (maxLength <= 1) return joined.substring(0, maxLength);
    return '${joined.substring(0, maxLength - 1)}…';
  }

  /// Schedules one notification per weekday at 7:00 summarizing that day's
  /// classes. Cancels weekday reminders for days that have no classes.
  @visibleForTesting
  static Future<void> scheduleMorningReminders(Iterable<ClassModel> classes) async {
    if (!_initialized || !_enabled) return;

    final Map<int, List<ClassModel>> byWeekday = {};
    for (final c in classes) {
      final w = weekdayFromKanji(c.dayOfWeek);
      if (w != null) {
        (byWeekday[w] ??= []).add(c);
      }
    }

    final futures = <Future<void>>[];
    for (var w = 1; w <= 7; w++) {
      final dayClasses = byWeekday[w];
      if (dayClasses != null && dayClasses.isNotEmpty) {
        final morningTime = _nextWeekdayTime(weekday: w, hour: 7, minute: 0);
        final title = morningDigestTitle(dayClasses.length);
        final body = morningDigestBody(dayClasses);
        futures.add(_schedule(
          morningReminderId(w),
          title,
          body,
          morningTime,
          matchComponents: DateTimeComponents.dayOfWeekAndTime,
          payload: '/timetable',
        ));
      } else {
        futures.add(_plugin.cancel(morningReminderId(w)));
      }
    }
    if (futures.isNotEmpty) {
      await Future.wait(futures);
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

  /// School lesson reminder body using [notif_class_rem_soon]; drops the
  /// " ({room})" part when the room is blank, matching [classReminderText].
  @visibleForTesting
  static String schoolReminderText(SchoolSlot slot, SchoolPeriod period) {
    final n = period.label.replaceAll('限', '');
    final text = AppStrings.t('notif_class_rem_soon', {
      'n': n.isEmpty ? period.key.replaceAll('限', '') : n,
      'subject': slot.subject,
      'room': slot.room.trim(),
      'time': formatHm(period.start),
    });
    return slot.room.trim().isEmpty ? text.replaceAll(' ()', '').replaceAll('()', '') : text;
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
    String? payload,
  }) {
    return _plugin.zonedSchedule(
      id,
      title,
      body,
      time,
      _details,
      payload: payload,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: matchComponents,
    );
  }

  static Future<void> scheduleClassReminder(ClassModel c) async {
    final weekday = weekdayFromKanji(c.dayOfWeek);
    final start = periodStart(c.period);
    if (weekday == null || start == null) return;

    // Clear previous schedules: cancelClassReminders cancels both the old
    // per-class morning reminder id (c.id.hashCode) and the pre-class reminder id.
    await cancelClassReminders(c.id);
    if (!_enabled) return;

    final classStart = _nextWeekdayTime(weekday: weekday, hour: start.$1, minute: start.$2);
    var beforeClass = classStart.subtract(const Duration(minutes: 30));
    // Added less than 30 min before the class: start the weekly repeat next
    // week instead of never scheduling it at all.
    if (!beforeClass.isAfter(tz.TZDateTime.now(tz.local))) {
      beforeClass = beforeClass.add(const Duration(days: 7));
    }

    // Keep pre-class reminder unchanged (id: c.id.hashCode + 1) with payload '/timetable'.
    await _schedule(
      c.id.hashCode + 1,
      AppStrings.t('notif_class_rem_title'),
      classReminderText('notif_class_rem_soon', c),
      beforeClass,
      matchComponents: DateTimeComponents.dayOfWeekAndTime,
      payload: '/timetable',
    );
  }

  static Future<void> cancelClassReminders(String id) {
    return Future.wait([
      _plugin.cancel(id.hashCode),
      _plugin.cancel(id.hashCode + 1),
    ]);
  }

  /// Schedules one-shot local reminders for the school [week] and [periods]
  /// at lesson start - 30 minutes, for slots with status normal or elective.
  /// Cancels any existing reminders for the 5 days before scheduling.
  static Future<void> scheduleSchoolReminders(
    Map<String, SchoolDay> week,
    List<SchoolPeriod> periods,
  ) async {
    if (!_initialized || !_enabled) return;

    // Determine the 5 days to cancel.
    final dayDates = <String>{};
    for (final dStr in week.keys) {
      final d = DateTime.tryParse(dStr);
      if (d != null) {
        final monday = DateTime(d.year, d.month, d.day - (d.weekday - 1));
        for (var i = 0; i < 5; i++) {
          final di = DateTime(monday.year, monday.month, monday.day + i);
          dayDates.add(
            '${di.year.toString().padLeft(4, '0')}-'
            '${di.month.toString().padLeft(2, '0')}-'
            '${di.day.toString().padLeft(2, '0')}',
          );
        }
        break;
      }
    }
    dayDates.addAll(week.keys);
    for (final day in week.values) {
      if (day.date.isNotEmpty) dayDates.add(day.date);
    }

    final cancels = <Future<void>>[];
    for (final date in dayDates) {
      for (final p in periods) {
        cancels.add(_plugin.cancel('school_${date}_${p.key}'.hashCode));
      }
    }
    if (cancels.isNotEmpty) {
      await Future.wait(cancels);
    }

    if (!_enabled) return;

    final periodMap = {for (final p in periods) p.key: p};
    final now = tz.TZDateTime.now(tz.local);
    final title = AppStrings.t('notif_class_rem_title');
    final schedules = <Future<void>>[];

    for (final entry in week.entries) {
      final day = entry.value;
      final dateStr = day.date.isNotEmpty ? day.date : entry.key;
      final date = DateTime.tryParse(dateStr);
      if (date == null) continue;

      for (final slot in day.slots) {
        if (slot.status != SchoolSlotStatus.normal &&
            slot.status != SchoolSlotStatus.elective) {
          continue;
        }
        if (slot.subject.trim().isEmpty) continue;

        final p = periodMap[slot.period];
        if (p == null) continue;

        final startDt = tz.TZDateTime(
          tz.local,
          date.year,
          date.month,
          date.day,
          p.start.$1,
          p.start.$2,
        );
        final reminderTime = startDt.subtract(const Duration(minutes: 30));
        if (!reminderTime.isAfter(now)) continue;

        final id = 'school_${dateStr}_${slot.period}'.hashCode;
        final body = schoolReminderText(slot, p);
        schedules.add(_schedule(id, title, body, reminderTime, payload: '/timetable'));
      }
    }

    if (schedules.isNotEmpty) {
      await Future.wait(schedules);
    }
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
      futures.add(_schedule(a.id.hashCode, title, AppStrings.t('notif_assign_rem_3d', args), threeDaysBefore, payload: '/assignments'));
    }
    if (oneDayBefore.isAfter(now)) {
      futures.add(_schedule(a.id.hashCode + 1, title, AppStrings.t('notif_assign_rem_1d', args), oneDayBefore, payload: '/assignments'));
    }
    if (onDueDay.isAfter(now)) {
      futures.add(_schedule(a.id.hashCode + 2, title, AppStrings.t('notif_assign_rem_today', args), onDueDay, payload: '/assignments'));
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
