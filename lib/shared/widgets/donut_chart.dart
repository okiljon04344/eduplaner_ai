import 'dart:math';
import 'package:flutter/material.dart';

class DonutChart extends StatelessWidget {
  final double progress;
  final double size;
  final double strokeWidth;
  final Color trackColor;
  final Color fillColor;
  final String? centerLabel;
  const DonutChart({
    super.key,
    required this.progress,
    this.size = 48,
    this.strokeWidth = 5,
    required this.trackColor,
    required this.fillColor,
    this.centerLabel,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size.square(size),
            painter: DonutPainter(
              progress: progress.clamp(0.0, 1.0),
              strokeWidth: strokeWidth,
              trackColor: trackColor,
              fillColor: fillColor,
            ),
          ),
          if (centerLabel != null)
            Text(centerLabel ?? '', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fillColor)),
        ],
      ),
    );
  }
}

class DonutPainter extends CustomPainter {
  final double progress;
  final double strokeWidth;
  final Color trackColor;
  final Color fillColor;
  DonutPainter({required this.progress, required this.strokeWidth, required this.trackColor, required this.fillColor});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - strokeWidth / 2;
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = trackColor;
    canvas.drawCircle(center, radius, track);
    final fill = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = fillColor;
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius), -pi / 2, 2 * pi * progress, false, fill);
  }

  @override
  bool shouldRepaint(covariant DonutPainter oldDelegate) => oldDelegate.progress != progress;
}
