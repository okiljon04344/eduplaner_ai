import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

/// Lottie animation helpers. Asset paths live here so a rename touches one place.
abstract class AppLottie {
  static const _loading = 'assets/animations/loading.json';

  /// Looping spinner; falls back to a [CircularProgressIndicator] if the asset
  /// cannot be rendered.
  static Widget loading({double size = 64}) => Lottie.asset(
        _loading,
        width: size,
        height: size,
        fit: BoxFit.contain,
        repeat: true,
        errorBuilder: (_, __, ___) => SizedBox(
          width: size,
          height: size,
          child: const CircularProgressIndicator(strokeWidth: 2),
        ),
      );
}
