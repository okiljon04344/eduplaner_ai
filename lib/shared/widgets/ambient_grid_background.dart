import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// A very faint 32×32px grid of 1px lines across the whole screen —
/// the design handoff's "ambient background grid" texture. Barely visible
/// by design (brand accent at ~3-5% opacity); only rendered in dark mode,
/// where the design intends it to actually show (per the handoff doc).
class AmbientGridBackground extends StatelessWidget {
  const AmbientGridBackground({super.key});

  @override
  Widget build(BuildContext context) {
    if (!AppColors.isDark) return const SizedBox.shrink();
    return Positioned.fill(
      child: IgnorePointer(
        child: CustomPaint(painter: _GridPainter()),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.primary.withValues(alpha: 0.035)
      ..strokeWidth = 1;
    const spacing = 32.0;
    for (double x = 0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
