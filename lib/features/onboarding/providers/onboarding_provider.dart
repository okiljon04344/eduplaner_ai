import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Manages the completion flag for introductory onboarding, persisting state in local preferences.
///
/// UZ: Kirish onboarding yakunlanganlik bayrog'ini boshqaradi va holatni mahalliy sozlamalarda (preferences) saqlaydi.
class OnboardingNotifier extends AsyncNotifier<bool> {
  static const _key = 'onboarding_done';

  @override
  Future<bool> build() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key) ?? false;
  }

  Future<void> markDone() async {
    state = const AsyncData(true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, true);
  }
}

/// Riverpod provider exposing whether onboarding has been completed by the current device user.
///
/// UZ: Joriy qurilma foydalanuvchisi tomonidan onboarding yakunlanganligini taqdim etuvchi Riverpod provideri.
final onboardingProvider =
    AsyncNotifierProvider<OnboardingNotifier, bool>(OnboardingNotifier.new);
