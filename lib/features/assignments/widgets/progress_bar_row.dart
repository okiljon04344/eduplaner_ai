import 'package:flutter/material.dart';

/// Thin animated progress bar used inside [AssignmentCard].
/// Height 5, radius 3, width animates via [TweenAnimationBuilder] whenever
/// [progress] changes (e.g. after a status/progress update).
class ProgressBarRow extends StatelessWidget {
  final double progress;
  final Color color;
  const ProgressBarRow({super.key, required this.progress, required this.color});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: Stack(
        children: [
          Container(height: 5, decoration: const BoxDecoration(color: Color(0x0FFFFFFF))),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: progress.clamp(0.0, 1.0)),
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeOutExpo,
            builder: (context, value, child) => FractionallySizedBox(
              widthFactor: value,
              alignment: Alignment.centerLeft,
              child: Container(height: 5, color: color),
            ),
          ),
        ],
      ),
    );
  }
}
