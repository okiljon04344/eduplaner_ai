import 'package:cloud_functions/cloud_functions.dart';
import '../l10n/app_strings.dart';

/// Entry point for every Cloud Functions call. Callables are deployed in
/// `asia-northeast1` (see `functions/index.js`); the region must match or calls
/// fail with `not-found`. One generous timeout is shared by all calls because
/// AI analysis and quiz generation are the slowest.
abstract class FunctionsService {
  static final FirebaseFunctions _instance = () {
    final f = FirebaseFunctions.instanceFor(region: 'asia-northeast1');
    // Emulator auth tokens are rejected by production, so use the local emulator.
    if (const bool.fromEnvironment('USE_EMULATOR')) {
      f.useFunctionsEmulator('localhost', 5001);
    }
    return f;
  }();
  static const Duration timeout = Duration(seconds: 120);

  static HttpsCallable callable(String name) => _instance.httpsCallable(name,
      options: HttpsCallableOptions(timeout: timeout));

  /// Localized message for the error codes any callable can raise
  /// (auth/timeout/offline/server). Call sites check their own codes first.
  static String describeError(FirebaseFunctionsException e) {
    switch (e.code) {
      case 'unauthenticated':
        return AppStrings.t('err_login_required');
      case 'deadline-exceeded':
        return AppStrings.t('err_timeout');
      case 'resource-exhausted':
        return AppStrings.t('err_ai_limit_reached');
      case 'unavailable':
        return AppStrings.t('err_network');
      default:
        return AppStrings.t('err_server');
    }
  }
}
