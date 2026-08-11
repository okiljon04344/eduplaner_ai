import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
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
///   4. Japanese date symbols for [intl] formatting
///   5. Timezone data + Asia/Tokyo default (school schedule context)
///   6. Firebase (failures are logged and swallowed — app still boots offline)
///   7. Local push-notification channels
///   8. Pre-load saved locale into [AppStrings] so the first frame is never
///      rendered with untranslated strings
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await initializeDateFormatting(null);
  tzdata.initializeTimeZones();
  tz.setLocalLocation(tz.getLocation('Asia/Tokyo'));
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  } catch (e) {
    debugPrint('Firebase init error: $e');
  }
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
