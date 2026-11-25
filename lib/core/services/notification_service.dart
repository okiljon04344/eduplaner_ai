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

/// Coordinates local and push notifications, managing channel setup,
/// exact alarm permissions, FCM tokens, and reminders for classes and assignments.
///
/// UZ: Mahalliy va push xabarnomalarini muvofiqlashtiradi, kanal sozlamalarini,
/// aniq signal (exact alarm) ruxsatlarini, FCM tokenlarini hamda darslar va topshiriqlar uchun eslatmalarni boshqaradi.
abstract class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;
  static bool _enabled = true;
  static bool _exactAllowed = false;

  static bool get isEnabled => _enabled;

  /// Whether exact alarms are currently allowed on this device.
  ///
  /// UZ: Ushbu qurilmada ayni paytda aniq signallarga ruxsat berilganligi.
  static bool get isExactAllowed => _exactAllowed;

  /// True when notifications are enabled on Android but exact alarms
  /// are not currently allowed.
  ///
  /// UZ: Android'da xabarnomalar yoqilgan, ammo aniq signallarga hozirda ruxsat berilmagan bo'lsa, true bo'ladi.
  static bool get needsExactAlarmPermission =>
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.android &&
      _enabled &&
      !_exactAllowed;

  /// Refreshes the cached exact alarm permission flag using
  /// [AndroidFlutterLocalNotificationsPlugin.canScheduleExactNotifications].
  /// Returns `true` on non-Android platforms, and `false` on error.
  ///
  /// UZ: [AndroidFlutterLocalNotificationsPlugin.canScheduleExactNotifications] yordamida
  /// keshdagi aniq signal ruxsati bayrog'ini yangilaydi. Android bo'lmagan platformalarda `true`,
  /// xatolik yuz berganda `false` qaytaradi.
  static Future<bool> refreshExactAlarmPermission() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      _exactAllowed = true;
      return true;
    }
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      final allowed = await android?.canScheduleExactNotifications() ?? false;
      _exactAllowed = allowed;
      return allowed;
    } catch (e) {
      debugPrint('Exact alarm permission check error: $e');
      _exactAllowed = false;
      return false;
    }
  }

  /// Requests the permission to schedule exact alarms (opens the system
  /// "Alarms & reminders" screen), then refreshes the flag.
  ///
  /// UZ: Aniq signallarni rejalashtirish uchun ruxsat so'raydi (tizimning
  /// "Signallar va eslatmalar" ekranini ochadi), so'ngra bayroqni yangilaydi.
  static Future<bool> requestExactAlarmPermission() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      _exactAllowed = true;
      return true;
    }
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await android?.requestExactAlarmsPermission();
    } catch (e) {
      debugPrint('Request exact alarm permission error: $e');
    }
    return refreshExactAlarmPermission();
  }

  /// Pure helper: returns [AndroidScheduleMode.exactAllowWhileIdle] when
  /// [exactAllowed] is true, else [AndroidScheduleMode.inexactAllowWhileIdle].
  ///
  /// UZ: Sof yordamchi: [exactAllowed] true bo'lsa [AndroidScheduleMode.exactAllowWhileIdle],
  /// aks holda [AndroidScheduleMode.inexactAllowWhileIdle] qaytaradi.
  @visibleForTesting
  static AndroidScheduleMode scheduleModeFor({required bool exactAllowed}) {
    return exactAllowed
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle;
  }

  /// Whitelisted navigation routes that can be opened via notifications.
  ///
  /// UZ: Xabarnomalar orqali ochilishi mumkin bo'lgan oq ro'yxatga kiritilgan navigatsiya marshrutlari.
  static const Set<String> allowedRoutes = {
    '/home',
    '/timetable',
    '/assignments',
  };

  /// Returns true if [route] is non-null and present in [allowedRoutes].
  ///
  /// UZ: Agar [route] null bo'lmasa va [allowedRoutes] ichida mavjud bo'lsa, true qaytaradi.
  static bool isAllowedRoute(String? route) =>
      route != null && allowedRoutes.contains(route);

  /// Validates [route] against [allowedRoutes], returning the route if valid
  /// or null if invalid/null.
  ///
  /// UZ: [route] ni [allowedRoutes] bo'yicha tekshiradi, to'g'ri bo'lsa marshrutni,
  /// noto'g'ri/null bo'lsa null qaytaradi.
  static String? sanitizeRoute(String? route) =>
      isAllowedRoute(route) ? route : null;

  /// Holds a pending route requested by tapping a notification or handling an
  /// FCM intent / cold-start launch. Observed in `lib/app.dart`.
  ///
  /// UZ: Xabarnomani bosish yoki FCM intent / sovuq ishga tushirish (cold-start) orqali so'ralgan
  /// kutilayotgan marshrutni saqlaydi. `lib/app.dart` da kuzatiladi.
  static final ValueNotifier<String?> pendingRoute = ValueNotifier<String?>(null);

  static void _handleRoutePayload(String? route) {
    final validRoute = sanitizeRoute(route);
    if (validRoute != null) {
      pendingRoute.value = validRoute;
    }
  }

  // Must match default_notification_channel_id in AndroidManifest.xml and the
  // channelId in functions/index.js.
  // UZ: AndroidManifest.xml dagi default_notification_channel_id va functions/index.js
  // dagi channelId bilan mos kelishi kerak.
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
    // UZ: Ishga tushirishda ruxsat so'rovi bo'lmaydi: foydalanuvchi xabarnomalar nima uchun
    // ekanligini ko'rishi bilanoq asosiy ekran so'raydi (NotificationPromptCard).
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
    // UZ: FCM push'lari ushbu kanal nomini ko'rsatadi; u birinchisi kelishidan oldin mavjud
    // bo'lishi kerak, aks holda Android ularni "Miscellaneous" zaxira kanaliga joylashtiradi.
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(AndroidNotificationChannel(
          _channelId,
          AppStrings.t('notif_channel_name'),
          description: AppStrings.t('notif_channel_desc'),
          importance: Importance.high,
        ));
    await refreshExactAlarmPermission();

    // Check cold start from local notification launch details.
    // UZ: Mahalliy xabarnomani ishga tushirish tafsilotlaridan sovuq ishga tushirishni (cold start) tekshirish.
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
    // UZ: Web push sayt ildizida `firebase-messaging-sw.js` service worker faylini talab qiladi
    // (VAPID kalitini sozlash, faqat HTTPS orqali ro'yxatdan o'tish va h.k.), bu loyihada u mavjud
    // emas — usiz `getToken()` 404 beradigan skript uchun service worker'ni ro'yxatdan o'tkazishda
    // cheksiz osilib qoladi. Brauzerni butunlay tiqilib qolgan SW ro'yxati bilan qoldirishdan ko'ra,
    // vebda butunlay o'tkazib yuboring; dars/topshiriq eslatmalari har bir platformada yuqoridagi
    // mahalliy xabarnomalar plagini orqali ishlashda davom etadi.
    if (!_pushSupported) return;

    try {
      FirebaseMessaging.onMessage.listen(_onForegroundMessage);
      FirebaseMessaging.onMessageOpenedApp.listen(_onMessageOpenedApp);
      // Store the token for whoever is signed in *now or later*: at app
      // start on a fresh install nobody is signed in yet, so a one-shot
      // write here would never happen. Also re-store on token rotation.
      // UZ: *Hozir yoki keyinroq* tizimga kirgan har bir kishi uchun tokenni saqlang: yangi o'rnatilganda
      // ilova ishga tushganda hali hech kim kirmagan bo'ladi, shuning uchun bu yerda bir martalik
      // yozish hech qachon amalga oshmaydi. Token almashganda (rotation) ham qayta saqlang.
      FirebaseAuth.instance.authStateChanges().listen((user) {
        if (user != null && _enabled) unawaited(_storeToken(user.uid));
      });
      FirebaseMessaging.instance.onTokenRefresh.listen((token) {
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid != null && _enabled) unawaited(_storeToken(uid, token));
      });

      // Check cold start from FCM initial message.
      // UZ: FCM dastlabki xabaridan sovuq ishga tushirishni (cold start) tekshirish.
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
  ///
  /// UZ: Web ushbu loyiha bilan kelmaydigan `firebase-messaging-sw.js` service worker'ga muhtoj
  /// (usis `getToken()` butunlay osilib qoladi) va Windows/Linux da mahalliy push transporti yo'q
  /// (`requestPermission()`/`getToken()` u yerda ham osilib qolishi mumkin). Mahalliy eslatmalar bunga bog'liq emas.
  static bool get _pushSupported =>
      !kIsWeb &&
      defaultTargetPlatform != TargetPlatform.windows &&
      defaultTargetPlatform != TargetPlatform.linux;

  static const _promptDoneKey = 'notif_prompt_done';

  /// Android/iOS only: the platforms with a runtime notification permission.
  ///
  /// UZ: Faqat Android/iOS: ish vaqtidagi (runtime) xabarnoma ruxsatiga ega platformalar.
  static bool get _hasRuntimePermission =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// True when the home screen should offer to turn notifications on: a
  /// runtime-permission platform, not yet granted, and not answered before.
  ///
  /// UZ: Asosiy ekran xabarnomalarni yoqishni taklif qilishi kerak bo'lganda true bo'ladi:
  /// ish vaqti ruxsatiga ega platforma, hali berilmagan va ilgari javob berilmagan.
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
  ///
  /// UZ: Operatsion tizimning ruxsat so'rovi dialogini ko'rsatadi; ruxsat berilganligini qaytaradi.
  /// Har ikkala javob ham asosiy ekran so'rovini tugatadi (Sozlamalar orqali baribir yoqish mumkin).
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
      // UZ: `language` serverga push xabarnomalarini ilova tilida yozish imkonini beradi.
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
  ///
  /// UZ: Foydalanuvchining xabarnoma sozlamasini yangilaydi, uni [SharedPreferences] ga saqlaydi
  /// va barcha faol eslatmalarni tozalaydi + FCM ni uzadi (o'chirilganda) yoki FCM ni qayta
  /// ro'yxatdan o'tkazadi + eslatmalarni qayta rejalashtiradi (yoqilganda).
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
  ///
  /// UZ: Xabarnomalar ishga tushirilgan va yoqilgan bo'lsa, [classes] va tugallanmagan [assignments]
  /// uchun mahalliy eslatmalarni rejalashtiradi. Unit testlarda ([initialize] chaqirilmagan) yoki
  /// xabarnomalar o'chirilgan bo'lsa xavfsiz no-op.
  static Future<void> syncAllReminders({
    Iterable<ClassModel> classes = const [],
    Iterable<AssignmentModel> assignments = const [],
  }) async {
    if (!_initialized || !_enabled) return;
    await refreshExactAlarmPermission();
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
  ///
  /// UZ: Hafta kunlari bo'yicha (1..7) ertalabki xulosa xabarnomalari uchun barqaror xabarnoma id si.
  @visibleForTesting
  static int morningReminderId(int weekday) => 7000 + weekday;

  /// Morning digest title key `notif_morning_title` ("今日の授業は{n}コマ").
  ///
  /// UZ: Ertalabki xulosa sarlavhasi kaliti `notif_morning_title` ("今日の授業は{n}コマ").
  @visibleForTesting
  static String morningDigestTitle(int count) {
    return AppStrings.t('notif_morning_title', {'n': count});
  }

  /// Builds the morning summary body: classes sorted by period joined like
  /// "1限 数学 · 2限 英語", truncated to ~120 characters.
  ///
  /// UZ: Ertalabki xulosa matnini tuzadi: juftliklar bo'yicha saralangan darslar "1限 数学 · 2限 英語"
  /// kabi birlashtiriladi va ~120 belgiga qisqartiriladi.
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
  ///
  /// UZ: Hafta kunlari uchun soat 7:00 da o'sha kungi darslarni umumlashtiruvchi bitta xabarnoma
  /// rejalashtiradi. Darslari bo'lmagan kunlar uchun hafta kunlari eslatmalarini bekor qiladi.
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
  ///
  /// UZ: [key] uchun dars eslatmasi matni; (ixtiyoriy) xona bo'sh bo'lganda " ({room})" qismini
  /// tashlab yuboradi, shunda u hech qachon "Math ()" deb ko'rinmaydi.
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
    // UZ: ponytail: evristik tozalash; fanning o'zi "()" bilan tugasa, u buni yo'qotadi.
    return c.room.trim().isEmpty ? text.replaceAll(' ()', '').replaceAll('()', '') : text;
  }

  /// School lesson reminder body using [notif_class_rem_soon]; drops the
  /// " ({room})" part when the room is blank, matching [classReminderText].
  ///
  /// UZ: [notif_class_rem_soon] yordamida maktab darsi eslatmasi matni; [classReminderText] ga mos
  /// ravishda xona bo'sh bo'lganda " ({room})" qismini tashlab yuboradi.
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
  ///
  /// UZ: [period] boshlanish vaqti — dars jadvali/asosiy ekran kartalari ko'rsatadigan bir xil jadval.
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
  ///
  /// UZ: Quyidagi har bir eslatma tomonidan ishlatiladigan umumiy `zonedSchedule` chaqiruv shakli.
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
      androidScheduleMode: scheduleModeFor(exactAllowed: _exactAllowed),
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
    // UZ: Oldingi rejalarni tozalash: cancelClassReminders har bir dars uchun eski ertalabki eslatma
    // id sini (c.id.hashCode) ham, darsdan oldingi eslatma id sini ham bekor qiladi.
    await cancelClassReminders(c.id);
    if (!_enabled) return;

    final classStart = _nextWeekdayTime(weekday: weekday, hour: start.$1, minute: start.$2);
    var beforeClass = classStart.subtract(const Duration(minutes: 30));
    // Added less than 30 min before the class: start the weekly repeat next
    // week instead of never scheduling it at all.
    // UZ: Darsdan 30 daqiqadan kamroq vaqt oldin qo'shilgan: uni umuman rejalashtirmaslik o'rniga,
    // haftalik takrorlashni keyingi haftadan boshlang.
    if (!beforeClass.isAfter(tz.TZDateTime.now(tz.local))) {
      beforeClass = beforeClass.add(const Duration(days: 7));
    }

    // Keep pre-class reminder unchanged (id: c.id.hashCode + 1) with payload '/timetable'.
    // UZ: Darsdan oldingi eslatmani '/timetable' payload'i bilan o'zgarishsiz qoldiring (id: c.id.hashCode + 1).
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
  ///
  /// UZ: Maktab [week] va [periods] uchun dars boshlanishidan 30 daqiqa oldin normal yoki
  /// elective holatidagi slotlar uchun bir martalik mahalliy eslatmalarni rejalashtiradi.
  /// Rejalashtirishdan oldin 5 kun uchun mavjud bo'lgan har qanday eslatmalarni bekor qiladi.
  static Future<void> scheduleSchoolReminders(
    Map<String, SchoolDay> week,
    List<SchoolPeriod> periods,
  ) async {
    if (!_initialized || !_enabled) return;

    // Determine the 5 days to cancel.
    // UZ: Bekor qilinadigan 5 kunni aniqlash.
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
  ///
  /// UZ: Har bir kutilayotgan mahalliy eslatmani olib tashlaydi — hisobdan chiqishda foydalaniladi,
  /// shunda ushbu qurilmadagi keyingi hisob oldingi foydalanuvchining jadvalini meros qilib olmaydi.
  static Future<void> cancelAll() => _plugin.cancelAll();

  /// Unlinks this device from [uid]'s push notifications (sign-out): clears
  /// the stored token so `onClassStatusChanged` stops targeting it, then
  /// invalidates the token itself.
  ///
  /// UZ: Ushbu qurilmani [uid] ning push xabarnomalaridan uzadi (chiqish): saqlangan tokenni
  /// tozalaydi, shunda `onClassStatusChanged` uni nishonga olishni to'xtatadi, keyin tokenni o'zini bekor qiladi.
  static Future<void> unregisterPushToken(String uid) async {
    if (!_pushSupported) return;
    // `update`, not `set(merge)`: right after deleteAccount the doc is gone,
    // and a merge-set would recreate it as an empty orphan.
    // UZ: `set(merge)` emas, `update`: deleteAccount'dan so'ng darhol hujjat yo'qoladi,
    // va merge-set uni bo'sh yetim hujjat sifatida qayta yaratadi.
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
    // UZ: Uchta eslatma mustaqil xabarnomalardir — hali kelajakda bo'lganlarini
    // birma-bir emas, parallel ravishda rejalashtiring.
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

/// Pure helper matching [NotificationService.scheduleModeFor].
///
/// UZ: [NotificationService.scheduleModeFor] ga mos keladigan sof yordamchi.
AndroidScheduleMode scheduleModeFor({required bool exactAllowed}) =>
    NotificationService.scheduleModeFor(exactAllowed: exactAllowed);
