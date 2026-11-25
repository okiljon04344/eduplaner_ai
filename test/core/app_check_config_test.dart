import 'package:edu_planner_ai/core/services/app_check_config.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resolveAppCheckPlan', () {
    test('disables App Check when USE_EMULATOR is true', () {
      final plan = resolveAppCheckPlan(
        useEmulator: true,
        isWeb: false,
        platform: TargetPlatform.android,
        isDebugMode: true,
        isReleaseMode: false,
      );
      expect(plan.shouldActivate, isFalse);
      expect(plan.reason, 'emulator_disabled');
    });

    group('Android', () {
      test('uses AndroidDebugProvider (auto) in debug mode without token', () {
        final plan = resolveAppCheckPlan(
          isWeb: false,
          platform: TargetPlatform.android,
          isDebugMode: true,
          isReleaseMode: false,
        );
        expect(plan.shouldActivate, isTrue);
        expect(plan.reason, 'android:debug_auto');
        expect(plan.providerAndroid, isA<AndroidDebugProvider>());
        expect((plan.providerAndroid as AndroidDebugProvider).debugToken, isNull);
      });

      test('uses explicit debugToken in debug and profile modes', () {
        for (final isDebug in [true, false]) {
          final plan = resolveAppCheckPlan(
            isWeb: false,
            platform: TargetPlatform.android,
            isDebugMode: isDebug,
            isReleaseMode: false,
            debugToken: ' 11111111-2222-3333-4444-555555555555 ',
          );
          expect(plan.shouldActivate, isTrue);
          expect(plan.reason, 'android:debug_token');
          expect(plan.providerAndroid, isA<AndroidDebugProvider>());
          expect(
            (plan.providerAndroid as AndroidDebugProvider).debugToken,
            '11111111-2222-3333-4444-555555555555',
          );
        }
      });

      test('never uses debug provider in release mode even if debugToken is passed', () {
        final plan = resolveAppCheckPlan(
          isWeb: false,
          platform: TargetPlatform.android,
          isDebugMode: false,
          isReleaseMode: true,
          debugToken: '11111111-2222-3333-4444-555555555555',
        );
        expect(plan.shouldActivate, isTrue);
        expect(plan.reason, 'android:play_integrity');
        expect(plan.providerAndroid, isA<AndroidPlayIntegrityProvider>());
      });
    });

    group('iOS & macOS', () {
      test('uses AppleDebugProvider on both iOS and macOS in debug mode', () {
        for (final p in [TargetPlatform.iOS, TargetPlatform.macOS]) {
          final plan = resolveAppCheckPlan(
            isWeb: false,
            platform: p,
            isDebugMode: true,
            isReleaseMode: false,
          );
          expect(plan.shouldActivate, isTrue);
          expect(plan.reason, 'apple:debug_auto');
          expect(plan.providerApple, isA<AppleDebugProvider>());
        }
      });

      test('uses AppleAppAttestWithDeviceCheckFallbackProvider in release mode', () {
        for (final p in [TargetPlatform.iOS, TargetPlatform.macOS]) {
          final plan = resolveAppCheckPlan(
            isWeb: false,
            platform: p,
            isDebugMode: false,
            isReleaseMode: true,
            debugToken: '11111111-2222-3333-4444-555555555555',
          );
          expect(plan.shouldActivate, isTrue);
          expect(plan.reason, 'apple:app_attest_with_device_check_fallback');
          expect(
            plan.providerApple,
            isA<AppleAppAttestWithDeviceCheckFallbackProvider>(),
          );
        }
      });
    });

    group('Web', () {
      test('uses WebDebugProvider in debug mode when RECAPTCHA_SITE_KEY is empty', () {
        final plan = resolveAppCheckPlan(
          isWeb: true,
          platform: TargetPlatform.linux,
          isDebugMode: true,
          isReleaseMode: false,
          recaptchaSiteKey: '',
        );
        expect(plan.shouldActivate, isTrue);
        expect(plan.reason, 'web:debug_auto');
        expect(plan.providerWeb, isA<WebDebugProvider>());
        expect((plan.providerWeb as WebDebugProvider).debugToken, isNull);
      });

      test('uses explicit WebDebugProvider in non-release when debugToken is set', () {
        final plan = resolveAppCheckPlan(
          isWeb: true,
          platform: TargetPlatform.macOS,
          isDebugMode: true,
          isReleaseMode: false,
          recaptchaSiteKey: '6LcSiteKey',
          debugToken: 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
        );
        expect(plan.shouldActivate, isTrue);
        expect(plan.reason, 'web:debug_token');
        expect(plan.providerWeb, isA<WebDebugProvider>());
        expect(
          (plan.providerWeb as WebDebugProvider).debugToken,
          'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
        );
      });

      test('uses ReCaptchaV3Provider in release mode and ignores debugToken', () {
        final plan = resolveAppCheckPlan(
          isWeb: true,
          platform: TargetPlatform.android,
          isDebugMode: false,
          isReleaseMode: true,
          recaptchaSiteKey: ' 6LcSiteKey ',
          debugToken: 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
        );
        expect(plan.shouldActivate, isTrue);
        expect(plan.reason, 'web:recaptcha_v3');
        expect(plan.providerWeb, isA<ReCaptchaV3Provider>());
        expect((plan.providerWeb as ReCaptchaV3Provider).siteKey, '6LcSiteKey');
      });

      test('skips activation in release mode when RECAPTCHA_SITE_KEY is empty', () {
        final plan = resolveAppCheckPlan(
          isWeb: true,
          platform: TargetPlatform.android,
          isDebugMode: false,
          isReleaseMode: true,
          recaptchaSiteKey: '',
          debugToken: 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
        );
        expect(plan.shouldActivate, isFalse);
        expect(plan.reason, 'web_missing_site_key');
      });
    });

    group('Desktop (Windows / Linux)', () {
      test('Windows activates WindowsDebugProvider only when non-release debugToken is set', () {
        final withToken = resolveAppCheckPlan(
          isWeb: false,
          platform: TargetPlatform.windows,
          isDebugMode: true,
          isReleaseMode: false,
          debugToken: '11111111-2222-3333-4444-555555555555',
        );
        expect(withToken.shouldActivate, isTrue);
        expect(withToken.reason, 'windows:debug_token');
        expect(withToken.providerWindows, isA<WindowsDebugProvider>());
        expect(
          (withToken.providerWindows as WindowsDebugProvider).debugToken,
          '11111111-2222-3333-4444-555555555555',
        );

        final withoutToken = resolveAppCheckPlan(
          isWeb: false,
          platform: TargetPlatform.windows,
          isDebugMode: true,
          isReleaseMode: false,
        );
        expect(withoutToken.shouldActivate, isFalse);
        expect(withoutToken.reason, 'windows_no_debug_token');

        final releaseWithToken = resolveAppCheckPlan(
          isWeb: false,
          platform: TargetPlatform.windows,
          isDebugMode: false,
          isReleaseMode: true,
          debugToken: '11111111-2222-3333-4444-555555555555',
        );
        expect(releaseWithToken.shouldActivate, isFalse);
        expect(releaseWithToken.reason, 'windows_no_debug_token');
      });

      test('Linux is skipped cleanly', () {
        final plan = resolveAppCheckPlan(
          isWeb: false,
          platform: TargetPlatform.linux,
          isDebugMode: true,
          isReleaseMode: false,
          debugToken: '11111111-2222-3333-4444-555555555555',
        );
        expect(plan.shouldActivate, isFalse);
        expect(plan.reason, 'unsupported_platform');
      });
    });
  });
}
