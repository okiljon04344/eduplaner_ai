import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'
    show LicenseEntryWithLineBreaks, LicenseRegistry, TargetPlatform, defaultTargetPlatform, kDebugMode, kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'app.dart';
import 'core/l10n/app_strings.dart';
import 'core/services/notification_service.dart';
import 'firebase_options.dart';

/// App entry point.
///
/// Runs all one-time initialisation in order before handing control to
/// [EduPlannerApp]:
///   1. Flutter engine binding
///   2. Portrait-only orientation lock
///   3. System UI overlay colours (dark-mode safe transparent status bar)
///   4. Timezone data + Asia/Tokyo default (school schedule context)
///   5. Japanese date symbols for [intl] formatting, and Firebase (failures
///      are logged and swallowed — app still boots offline) — run concurrently,
///      neither depends on the other
///   7. Local push-notification channels
///   8. Pre-load saved locale into [AppStrings] so the first frame is never
///      rendered with untranslated strings
/// See the emulator block in `initFirebase` below.
///
/// UZ: Ilovaning kirish nuqtasi.
///
/// Boshqaruvni [EduPlannerApp] ga topshirishdan oldin barcha bir martalik sozlashlarni tartib bilan
/// amalga oshiradi:
///   1. Flutter engine bog'lanishi
///   2. Faqat portret orientatsiyasini qulflash
///   3. Tizim UI overlay ranglari (tungi rejim uchun xavfsiz shaffof status bar)
///   4. Vaqt mintaqasi ma'lumotlari + standart Asia/Tokyo (maktab jadvali konteksti)
///   5. [intl] formatlash uchun yaponcha sana belgilari va Firebase (xatoliklar qayd etiladi
///      va yutiladi — ilova oflayn holatda ham ishga tushadi) — parallel ishga tushadi, hech biri
///      boshqasiga bog'liq emas
///   7. Mahalliy push-bildirishnoma kanallari
///   8. Birinchi kadr hech qachon tarjima qilinmagan satrlar bilan chizilmasligi uchun saqlangan
///      lokalni [AppStrings] ga oldindan yuklash
/// Quyidagi `initFirebase` dagi emulyator blokiga qarang.
const kUseEmulator = bool.fromEnvironment('USE_EMULATOR');

/// reCAPTCHA v3 site key for App Check on web (public, not a secret):
/// `flutter build web --dart-define=RECAPTCHA_SITE_KEY=...`. Empty = web
/// runs without App Check, so a build without the key still works.
///
/// UZ: Vebda App Check uchun reCAPTCHA v3 sayt kaliti (ommaviy, sir emas):
/// `flutter build web --dart-define=RECAPTCHA_SITE_KEY=...`. Bo'sh = veb App Check'siz ishlaydi,
/// shuning uchun kalitsiz tuzilma ham ishlayveradi.
const kRecaptchaSiteKey = String.fromEnvironment('RECAPTCHA_SITE_KEY');

/// App Check proves requests come from this app, not a script reusing the
/// API key. Debug builds use the debug provider (its token is printed to the
/// log once; register it in the console). Enforcement is switched on in the
/// console / Cloud Functions only after the metrics show verified traffic.
///
/// UZ: App Check so'rovlar API kalitidan qayta foydalanayotgan skriptdan emas, aynan shu
/// ilovadan kelayotganini tasdiqlaydi. Debug tuzilmalari debug provayderidan foydalanadi
/// (uning tokeni jurnalga bir marta chop etiladi; uni konsolda ro'yxatdan o'tkazing).
/// Majburiy tekshirish faqat metrikalar tasdiqlangan trafikni ko'rsatgandan keyin konsolda /
/// Cloud Functions da yoqiladi.
Future<void> activateAppCheck() async {
  final mobile = defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS;
  if (kIsWeb ? kRecaptchaSiteKey.isEmpty : !mobile) return;
  try {
    await FirebaseAppCheck.instance.activate(
      providerWeb: kIsWeb ? ReCaptchaV3Provider(kRecaptchaSiteKey) : null,
      providerAndroid: kDebugMode ? const AndroidDebugProvider() : const AndroidPlayIntegrityProvider(),
      providerApple: kDebugMode ? const AppleDebugProvider() : const AppleAppAttestWithDeviceCheckFallbackProvider(),
    );
  } catch (e) {
    debugPrint('App Check init error: $e');
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(['Plus Jakarta Sans'], await rootBundle.loadString('assets/fonts/OFL-PlusJakartaSans.txt'));
    yield LicenseEntryWithLineBreaks(['Noto Sans CJK JP'], await rootBundle.loadString('assets/fonts/OFL-NotoSansCJK.txt'));
  });
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  tzdata.initializeTimeZones();
  tz.setLocalLocation(tz.getLocation('Asia/Tokyo'));

  Future<void> initFirebase() async {
    try {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
      // Local UI testing only: `--dart-define=USE_EMULATOR=true` points Auth
      // and Firestore at `firebase emulators:start` so test accounts never
      // touch production. Off in every normal build.
      // UZ: Faqat lokal UI testlash uchun: `--dart-define=USE_EMULATOR=true` Auth va Firestore ni
      // `firebase emulators:start` ga yo'naltiradi, shunda test hisoblari hech qachon production ga
      // tegmaydi. Barcha odatiy build larda o'chiq bo'ladi.
      if (kUseEmulator) {
        const host = String.fromEnvironment('EMULATOR_HOST', defaultValue: 'localhost');
        await FirebaseAuth.instance.useAuthEmulator(host, 9099);
        FirebaseFirestore.instance.useFirestoreEmulator(host, 8085);
      } else {
        await activateAppCheck();
      }
    } catch (e) {
      debugPrint('Firebase init error: $e');
    }
  }

  // intl date symbols and Firebase are independent subsystems — initialise
  // them concurrently instead of one after another.
  // UZ: intl sana belgilari va Firebase mustaqil quyi tizimlardir — ularni ketma-ket emas,
  // bir vaqtning o'zida parallel ishga tushiring.
  await Future.wait([initializeDateFormatting(null), initFirebase()]);
  try {
    await NotificationService.initialize();
  } catch (e) {
    debugPrint('Notification init error: $e');
  }
  final prefs = await SharedPreferences.getInstance();
  final savedLocale = prefs.getString('app_locale') ?? 'ja';
  await AppStrings.load(savedLocale);
  runApp(const ProviderScope(child: EduPlannerApp()));
}
