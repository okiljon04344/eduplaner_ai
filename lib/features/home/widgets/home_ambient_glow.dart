import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

/// Static ambient glow background for the Home screen: 3 large blurred circles
/// (green, blue, green) matching the mockup positions.
///
/// Drawn once in a [Stack] behind the scroll view and isolated with
/// [RepaintBoundary] so it never repaints during scrolling.
///
/// UZ: Asosiy ekran uchun statik fon jilosi (ambient glow): maketdagi o'rinlarga mos
/// keladigan 3 ta katta xiralashtirilgan aylana (yashil, ko'k, yashil).
///
/// Aylantirish (scroll) ko'rinishi orqasida [Stack] da bir marta chiziladi va [RepaintBoundary]
/// bilan ajratiladi, shuning uchun aylantirish paytida hech qachon qayta chizilmaydi.
class HomeAmbientGlow extends StatelessWidget {
  const HomeAmbientGlow({super.key});

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: IgnorePointer(
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
