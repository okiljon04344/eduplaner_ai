import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../core/theme/app_colors.dart';

/// A handful of soft, slowly-pulsing radial-gradient blobs behind the brand
/// panel — a livelier, more youthful alternative to a single static glow.
class FloatingOrbs extends StatelessWidget {
  const FloatingOrbs({super.key});

  @override
  Widget build(BuildContext context) {
    Widget orb({required double top, required double left, required double size, required Color color, required int delayMs}) {
      return Positioned(
        top: top,
        left: left,
        child: IgnorePointer(
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [color.withValues(alpha: 0.32), color.withValues(alpha: 0)]),
            ),
          )
              .animate(delay: delayMs.ms)
              .scale(begin: const Offset(0.9, 0.9), end: const Offset(1, 1), duration: 1600.ms, curve: Curves.easeOut)
              .fadeIn(duration: 1000.ms),
        ),
      );
    }

    return Stack(
      children: [
        orb(top: -60, left: -40, size: 220, color: AppColors.primary, delayMs: 0),
        orb(top: 120, left: 260, size: 160, color: AppColors.primaryLight, delayMs: 400),
        orb(top: 320, left: -20, size: 180, color: AppColors.primaryMid, delayMs: 800),
      ],
    );
  }
}

class DotPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = AppColors.primaryLight.withValues(alpha: 0.08);
    const spacing = 24.0;
    const radius = 3.0;
    for (double y = 0; y < size.height; y += spacing) {
      for (double x = 0; x < size.width; x += spacing) {
        canvas.drawCircle(Offset(x, y), radius, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
