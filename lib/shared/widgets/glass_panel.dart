import 'dart:ui';
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// Reusable glassmorphic panel.
///
/// Wraps [child] in a rounded container with a translucent [tint] fill and
/// [borderColor]. When [blurSigma] is provided (and > 0) and animations/effects
/// are enabled, it applies a real [BackdropFilter] with [ImageFilter.blur].
///
/// When [MediaQuery.disableAnimationsOf] is true, [BackdropFilter] is skipped
/// and an opaque-enough fill ([AppColors.cardSurface]) is painted instead,
/// ensuring high contrast and smooth performance.
class GlassPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double radius;
  final Color? tint;
  final Color? borderColor;
  final List<BoxShadow>? shadows;
  final double? blurSigma;

  const GlassPanel({
    super.key,
    required this.child,
    this.padding,
    this.radius = 24,
    this.tint,
    this.borderColor,
    this.shadows,
    this.blurSigma,
  });

  @override
  Widget build(BuildContext context) {
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    final wantsBlur = blurSigma != null && blurSigma! > 0;
    final useBlur = wantsBlur && !disableAnimations;

    final effectiveFill = disableAnimations
        ? AppColors.cardSurface
        : (tint ?? AppColors.glassFill);

    final effectiveBorder = borderColor != null
        ? Border.all(color: borderColor!)
        : Border.all(color: AppColors.glassBorder);

    final br = BorderRadius.circular(radius);

    Widget inner = DecoratedBox(
      decoration: BoxDecoration(
        color: effectiveFill,
        borderRadius: br,
        border: effectiveBorder,
      ),
      child: padding != null ? Padding(padding: padding!, child: child) : child,
    );

    if (useBlur) {
      inner = ClipRRect(
        borderRadius: br,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blurSigma!, sigmaY: blurSigma!),
          child: inner,
        ),
      );
    } else {
      inner = ClipRRect(
        borderRadius: br,
        child: inner,
      );
    }

    if (shadows != null && shadows!.isNotEmpty) {
      return DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: br,
          // The fill is translucent, so a shadow painted under the panel shows
          // through as a hard band (CSS never paints under the box): outer
          // blur only, centred (an offset outer shadow still leaves a band).
          boxShadow: [for (final s in shadows!) BoxShadow(color: s.color, offset: Offset.zero, blurRadius: s.blurRadius, spreadRadius: s.spreadRadius, blurStyle: BlurStyle.outer)],
        ),
        child: inner,
      );
    }

    return inner;
  }
}
