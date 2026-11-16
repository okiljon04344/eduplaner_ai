import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

/// Centralized Lottie animation helper.
///
/// The asset path is defined here so a rename touches one place. The widget
/// falls back to a plain spinner when the asset is missing or the parser
/// cannot render the JSON.
///
/// UZ: Markazlashtirilgan Lottie animatsiyasi yordamchisi.
///
/// Aktiv yo'li bu yerda belgilangan, shuning uchun nomini o'zgartirish faqat bitta joyga ta'sir qiladi.
/// Vidjet aktiv yetishmayotganda yoki parser JSON'ni render qila olmaganda oddiy spinnerga qaytadi.
class AppLottie {
  AppLottie._();

  static const _loading = 'assets/animations/loading.json';

  /// Spinning ring loader — replaces [CircularProgressIndicator] in AI/auth
  /// screens for a more polished look.  Loops indefinitely.
  ///
  /// UZ: Aylanuvchi halqa yuklagichi — yanada sayqallangan ko'rinish uchun AI/auth ekranlarida
  /// [CircularProgressIndicator] o'rnini bosadi. Cheksiz aylanadi.
  static Widget loading({double size = 64}) => _LottieLoop(
        asset: _loading,
        size: size,
      );
}

// ── Internal implementation widgets ─────────────────────────────────────────

/// Plays a Lottie animation in a continuous loop.
///
/// UZ: Lottie animatsiyasini uzluksiz siklda o'ynaydi.
class _LottieLoop extends StatelessWidget {
  final String asset;
  final double size;
  const _LottieLoop({required this.asset, required this.size});

  @override
  Widget build(BuildContext context) {
    return Lottie.asset(
      asset,
      width: size,
      height: size,
      fit: BoxFit.contain,
      // Loops forever — correct for loading spinners.
      // UZ: Cheksiz aylanadi — yuklash spinnerlari uchun to'g'ri.
      repeat: true,
      errorBuilder: (_, __, ___) => SizedBox(
        width: size,
        height: size,
        child: const CircularProgressIndicator(strokeWidth: 2),
      ),
    );
  }
}
