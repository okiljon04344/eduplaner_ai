import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

/// Three purple dots that pulse in a staggered wave, mirroring the
/// AI-chat prototype's `dot1`/`dot2`/`dot3` CSS keyframes
/// (scale 0→1→0, opacity .3→1→.3, 1.2s cycle, 200ms stagger).
class TypingIndicator extends StatefulWidget {
  const TypingIndicator({super.key});

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  static const _period = Duration(milliseconds: 1200);
  static const _delays = [0.0, 1 / 6, 2 / 6]; // 0ms, 200ms, 400ms of a 1200ms cycle

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _period)..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _pulse(double t, double delay) {
    // Shift the timeline for this dot, then map through a 0→1→0 triangle
    // eased with easeInOut for a smooth scale/opacity pulse.
    final local = (t - delay) % 1.0;
    final triangle = local < 0.5 ? local * 2 : (1 - local) * 2;
    return Curves.easeInOut.transform(triangle.clamp(0.0, 1.0));
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 12,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(3, (i) {
              final v = _pulse(_controller.value, _delays[i]);
              final scale = 0.3 + v * 0.7; // stays visible at rest, still reads as a pulse
              final opacity = 0.3 + v * 0.7;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Opacity(
                  opacity: opacity,
                  child: Transform.scale(
                    scale: scale,
                    child: Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: AppColors.primaryMid,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(color: AppColors.primaryMid.withValues(alpha: 0.6), blurRadius: 6),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}
