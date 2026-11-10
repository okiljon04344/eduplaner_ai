import 'package:flutter/widgets.dart';

/// Centralized motion design tokens and curves for EduPlanner AI.
///
/// Motion rules:
/// - Only transform (translate/scale) and opacity animate. Never animate size,
///   padding, blur, or color washes on big surfaces.
/// - Everything UI is <= 300ms (except open once count-up & bar fill at 600ms, and the 2.4s breathing dot).
/// - Curves: strong ease-out = `Cubic(0.23, 1, 0.32, 1)`; sheet = `Cubic(0.32, 0.72, 0, 1)`. Never ease-in.
/// - When [reduceMotion] is true: no movement, only 150ms opacity fade or instant.
class AppMotion {
  AppMotion._();

  // Durations
  static const Duration pressDuration = Duration(milliseconds: 120);
  static const Duration enterDuration = Duration(milliseconds: 280);
  static const Duration enterStagger = Duration(milliseconds: 50);
  static const Duration screenDuration = Duration(milliseconds: 200);
  static const Duration fadeDuration = Duration(milliseconds: 150);
  static const Duration pillDuration = Duration(milliseconds: 260);
  static const Duration sheetOpenDuration = Duration(milliseconds: 320);
  static const Duration sheetCloseDuration = Duration(milliseconds: 200);
  static const Duration checkPopDuration = Duration(milliseconds: 260);
  static const Duration checkColorDuration = Duration(milliseconds: 160);
  static const Duration countUpDuration = Duration(milliseconds: 600);
  static const Duration barDuration = Duration(milliseconds: 600);
  static const Duration dotDuration = Duration(milliseconds: 2400);

  // Scales
  static const double pressScale = 0.97;

  // Curves
  static const Curve strongEaseOut = Cubic(0.23, 1.0, 0.32, 1.0);
  static const Curve sheetCurve = Cubic(0.32, 0.72, 0.0, 1.0);
  static const Curve dotCurve = Curves.easeInOut;

  /// Returns true if the user or test environment has requested reduced motion.
  static bool reduceMotion(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;
}

/// Helper function to check if reduced motion is requested.
bool reduceMotion(BuildContext context) => AppMotion.reduceMotion(context);
