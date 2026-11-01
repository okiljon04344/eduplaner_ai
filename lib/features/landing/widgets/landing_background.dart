import 'dart:math' as math;
import 'package:flutter/material.dart';

// ─── Animated background ─────────────────────────────────────────────────────

class AnimatedBg extends StatelessWidget {
  final AnimationController ctrl;
  const AnimatedBg({super.key, required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ctrl,
      builder: (_, __) => CustomPaint(
        painter: _OrbPainter(ctrl.value),
        size: Size.infinite,
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _OrbPainter extends CustomPainter {
  final double t;
  const _OrbPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    void orb(double cx, double cy, double r, Color c, double phase) {
      final dx = math.sin((t + phase) * math.pi * 2) * size.width * 0.08;
      final dy = math.cos((t * 0.7 + phase) * math.pi * 2) * size.height * 0.06;
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [c.withValues(alpha: 0.28), c.withValues(alpha: 0)],
        ).createShader(Rect.fromCircle(
          center: Offset(size.width * cx + dx, size.height * cy + dy),
          radius: r,
        ));
      canvas.drawCircle(
        Offset(size.width * cx + dx, size.height * cy + dy),
        r,
        paint,
      );
    }

    orb(0.15, 0.2,  size.width * 0.38, const Color(0xFF06D6A0), 0.0);
    orb(0.85, 0.15, size.width * 0.32, const Color(0xFF34D399), 0.33);
    orb(0.7,  0.7,  size.width * 0.28, const Color(0xFF5EEAD4), 0.66);
    orb(0.1,  0.75, size.width * 0.22, const Color(0xFF059669), 0.15);
  }

  @override
  bool shouldRepaint(_OrbPainter old) => old.t != t;
}
