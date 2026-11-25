import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kDebugMode, kIsWeb, kReleaseMode;

/// reCAPTCHA v3 site key for App Check on web (public site key, not a secret):
/// `flutter build web --release --dart-define=RECAPTCHA_SITE_KEY=...`.
const kRecaptchaSiteKey = String.fromEnvironment('RECAPTCHA_SITE_KEY');

/// Optional pre-registered App Check debug token for dev/emulator/CI runs:
/// `flutter run --dart-define=APP_CHECK_DEBUG_TOKEN=<UUID>`.
/// Ignored in release builds (`kReleaseMode == true`).
const kAppCheckDebugToken = String.fromEnvironment('APP_CHECK_DEBUG_TOKEN');

/// Resolved App Check activation plan for the current platform and build mode.
class AppCheckPlan {
  const AppCheckPlan({
    required this.shouldActivate,
    required this.reason,
    this.providerWeb,
    this.providerAndroid = const AndroidPlayIntegrityProvider(),
    this.providerApple = const AppleAppAttestWithDeviceCheckFallbackProvider(),
    this.providerWindows = const WindowsDebugProvider(),
  });

  final bool shouldActivate;
  final String reason;
  final WebProvider? providerWeb;
  final AndroidAppCheckProvider providerAndroid;
  final AppleAppCheckProvider providerApple;
  final WindowsAppCheckProvider providerWindows;
}

/// Computes which Firebase App Check provider should be activated for the given
/// platform and build flags.
///
/// Debug providers are strictly gated on `!isReleaseMode` so a release build
/// can never ship a debug token even if `APP_CHECK_DEBUG_TOKEN` was set.
AppCheckPlan resolveAppCheckPlan({
  bool useEmulator = false,
  bool isWeb = kIsWeb,
  TargetPlatform? platform,
  bool isDebugMode = kDebugMode,
  bool isReleaseMode = kReleaseMode,
  String recaptchaSiteKey = kRecaptchaSiteKey,
  String debugToken = kAppCheckDebugToken,
}) {
  if (useEmulator) {
    return const AppCheckPlan(
      shouldActivate: false,
      reason: 'emulator_disabled',
    );
  }

  final effectivePlatform = platform ?? defaultTargetPlatform;
  final cleanDebugToken = debugToken.trim();
  final cleanSiteKey = recaptchaSiteKey.trim();
  final allowDebug = !isReleaseMode;
  final hasDebugToken = allowDebug && cleanDebugToken.isNotEmpty;

  if (isWeb) {
    if (hasDebugToken) {
      return AppCheckPlan(
        shouldActivate: true,
        reason: 'web:debug_token',
        providerWeb: WebDebugProvider(debugToken: cleanDebugToken),
      );
    }
    if (cleanSiteKey.isNotEmpty) {
      return AppCheckPlan(
        shouldActivate: true,
        reason: 'web:recaptcha_v3',
        providerWeb: ReCaptchaV3Provider(cleanSiteKey),
      );
    }
    if (allowDebug && isDebugMode) {
      return AppCheckPlan(
        shouldActivate: true,
        reason: 'web:debug_auto',
        providerWeb: WebDebugProvider(),
      );
    }
    return const AppCheckPlan(
      shouldActivate: false,
      reason: 'web_missing_site_key',
    );
  }

  switch (effectivePlatform) {
    case TargetPlatform.android:
      if (hasDebugToken) {
        return AppCheckPlan(
          shouldActivate: true,
          reason: 'android:debug_token',
          providerAndroid: AndroidDebugProvider(debugToken: cleanDebugToken),
        );
      }
      if (allowDebug && isDebugMode) {
        return const AppCheckPlan(
          shouldActivate: true,
          reason: 'android:debug_auto',
          providerAndroid: AndroidDebugProvider(),
        );
      }
      return const AppCheckPlan(
        shouldActivate: true,
        reason: 'android:play_integrity',
        providerAndroid: AndroidPlayIntegrityProvider(),
      );

    case TargetPlatform.iOS:
    case TargetPlatform.macOS:
      // macOS links FirebaseAppCheckPlugin, which defaults to DeviceCheck
      // before main() runs; explicitly activating AppleDebugProvider in debug
      // prevents unsigned macOS dev builds from sending invalid DeviceCheck
      // tokens.
      if (hasDebugToken) {
        return AppCheckPlan(
          shouldActivate: true,
          reason: 'apple:debug_token',
          providerApple: AppleDebugProvider(debugToken: cleanDebugToken),
        );
      }
      if (allowDebug && isDebugMode) {
        return const AppCheckPlan(
          shouldActivate: true,
          reason: 'apple:debug_auto',
          providerApple: AppleDebugProvider(),
        );
      }
      return const AppCheckPlan(
        shouldActivate: true,
        reason: 'apple:app_attest_with_device_check_fallback',
        providerApple: AppleAppAttestWithDeviceCheckFallbackProvider(),
      );

    case TargetPlatform.windows:
      // Firebase C++ SDK only supports the debug provider on Windows and does
      // not auto-generate a secret; require an explicit non-release token.
      if (hasDebugToken) {
        return AppCheckPlan(
          shouldActivate: true,
          reason: 'windows:debug_token',
          providerWindows: WindowsDebugProvider(debugToken: cleanDebugToken),
        );
      }
      return const AppCheckPlan(
        shouldActivate: false,
        reason: 'windows_no_debug_token',
      );

    case TargetPlatform.linux:
    case TargetPlatform.fuchsia:
      return const AppCheckPlan(
        shouldActivate: false,
        reason: 'unsupported_platform',
      );
  }
}
