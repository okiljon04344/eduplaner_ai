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

/// Set with `--dart-define=USE_EMULATOR=true` to run against the local
/// Firebase emulators.
const kUseEmulator = bool.fromEnvironment('USE_EMULATOR');

/// Runs one-time initialisation, then starts [EduPlannerApp]. Firebase and
/// notification failures are logged and swallowed so the app still boots offline.
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
      // Local testing only: points Auth/Firestore at the emulators so test
      // accounts never touch production.
      if (kUseEmulator) {
        await FirebaseAuth.instance.useAuthEmulator('localhost', 9099);
        FirebaseFirestore.instance.useFirestoreEmulator('localhost', 8085);
      }
    } catch (e) {
      debugPrint('Firebase init error: $e');
    }
  }

  // Independent of each other, so run concurrently.
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
