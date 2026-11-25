import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_motion.dart';

/// Standard app bottom sheet launcher with custom animation timing:
/// 320ms open, 200ms close (or 150ms when [reduceMotion] is true).
///
/// Uses [AppColors.bgLayer], top radius 24, and [isScrollControlled: true] by default.
/// Disposes the [AnimationController] when the sheet closes.
///
/// UZ: Maxsus animatsiya vaqtiga ega standart ilova pastki varag'i (bottom sheet) ishga tushirgichi:
/// 320ms ochilish, 200ms yopilish (yoki [reduceMotion] true bo'lsa 150ms).
///
/// Standart bo'yicha [AppColors.bgLayer], yuqori radiusi 24 va [isScrollControlled: true] dan foydalanadi.
/// Varaq yopilganda [AnimationController] ni bekor qiladi (dispose).
Future<T?> showAppSheet<T>(
  BuildContext context,
  WidgetBuilder builder, {
  bool isScrollControlled = true,
  bool useRootNavigator = true,
  Color? backgroundColor,
  ShapeBorder? shape,
}) async {
  final isReduced = reduceMotion(context);
  final navigator = Navigator.of(context, rootNavigator: useRootNavigator);
  final controller = AnimationController(
    duration: isReduced ? AppMotion.fadeDuration : AppMotion.sheetOpenDuration,
    reverseDuration: isReduced ? AppMotion.fadeDuration : AppMotion.sheetCloseDuration,
    vsync: navigator,
  );

  try {
    return await showModalBottomSheet<T>(
      context: context,
      builder: builder,
      isScrollControlled: isScrollControlled,
      useRootNavigator: useRootNavigator,
      backgroundColor: backgroundColor ?? AppColors.bgLayer,
      shape: shape ??
          const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
      transitionAnimationController: controller,
    );
  } finally {
    // The future completes at pop, while the 200ms exit transition is still
    // running: disposing now would freeze the sheet half closed.
    // UZ: Future pop paytida yakunlanadi, 200ms li chiqish o'tishi esa hali davom etmoqda:
    // hozir dispose qilish varaqni yarim yopiq holda qotirib qo'yadi.
    if (controller.isDismissed) {
      controller.dispose();
    } else {
      controller.addStatusListener((status) {
        if (status == AnimationStatus.dismissed) controller.dispose();
      });
    }
  }
}
