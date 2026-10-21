import 'package:flutter/material.dart';

/// Thin animated progress bar used inside [AssignmentCard].
/// Height 5, radius 3, width animates via [AnimatedFractionallySizedBox] whenever
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
          // Implicit animation: animates only on value change, not from 0 on first build.
          AnimatedFractionallySizedBox(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            alignment: AlignmentDirectional.centerStart,
            widthFactor: progress.clamp(0.0, 1.0),
            child: Container(height: 5, color: color),
          ),
        ],
      ),
    );
  }
}
