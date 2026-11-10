import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

/// Static ambient glow background for the Home screen: 3 large blurred circles
/// (green, blue, green) matching the mockup positions.
///
/// Drawn once in a [Stack] behind the scroll view and isolated with
/// [RepaintBoundary] so it never repaints during scrolling.
class HomeAmbientGlow extends StatelessWidget {
  const HomeAmbientGlow({super.key});

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: IgnorePointer(
        child: OverflowBox(
          alignment: Alignment.topCenter,
          minWidth: 0,
          minHeight: 0,
          maxWidth: double.infinity,
          maxHeight: double.infinity,
          child: SizedBox(
            width: MediaQuery.sizeOf(context).width,
            height: MediaQuery.sizeOf(context).height,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: -120,
                  top: -140,
                  width: 420,
                  height: 420,
                  child: _GlowCircle(color: AppColors.glowGreen),
                ),
                Positioned(
                  right: -160,
                  top: 220,
                  width: 380,
                  height: 380,
                  child: _GlowCircle(color: AppColors.glowBlue),
                ),
                Positioned(
                  left: -100,
                  top: 760,
                  width: 360,
                  height: 360,
                  child: _GlowCircle(color: AppColors.glowGreenSubtle),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GlowCircle extends StatelessWidget {
  final Color color;
  const _GlowCircle({required this.color});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            color,
            color.withValues(alpha: 0),
          ],
        ),
      ),
    );
  }
}
