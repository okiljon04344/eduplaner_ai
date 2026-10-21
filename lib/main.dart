import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show LicenseEntryWithLineBreaks, LicenseRegistry;
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
const kUseEmulator = bool.fromEnvironment('USE_EMULATOR');

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
      if (kUseEmulator) {
        await FirebaseAuth.instance.useAuthEmulator('localhost', 9099);
        FirebaseFirestore.instance.useFirestoreEmulator('localhost', 8085);
      }
    } catch (e) {
      debugPrint('Firebase init error: $e');
    }
  }

  // intl date symbols and Firebase are independent subsystems — initialise
  // them concurrently instead of one after another.
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
