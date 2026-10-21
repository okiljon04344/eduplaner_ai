import 'package:cloud_functions/cloud_functions.dart';
import '../l10n/app_strings.dart';

/// Centralized entry point for every Cloud Functions call in the app.
///
/// All callables are deployed in `asia-northeast1` (see `functions/index.js`)
/// — this must match, or every call fails with `not-found`. `timeout` is
/// shared across all calls (AI analysis / quiz generation are the slowest,
/// so the whole surface uses the same generous budget rather than tuning
/// each call site separately).
abstract class FunctionsService {
  static final FirebaseFunctions _instance = () {
    final f = FirebaseFunctions.instanceFor(region: 'asia-northeast1');
    // Emulator-auth tokens are rejected by production functions anyway;
    // route to a (possibly absent) local functions emulator instead.
    if (const bool.fromEnvironment('USE_EMULATOR')) f.useFunctionsEmulator('localhost', 5001);
    return f;
  }();
  static const Duration timeout = Duration(seconds: 120);

  static HttpsCallable callable(String name) =>
      _instance.httpsCallable(name, options: HttpsCallableOptions(timeout: timeout));

  /// Maps the error codes any callable can raise (auth/timeout/offline/server)
  /// to a localized message. Call sites should check their own
  /// function-specific codes first and fall back to this for the rest.
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
