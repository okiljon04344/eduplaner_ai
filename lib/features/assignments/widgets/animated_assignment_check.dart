import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion.dart';

/// Animated assignment completion checkbox circle.
///
/// When marked completed:
/// - The check icon pops (scale 0.6 -> 1.12 -> 1.0 in 260ms).
/// - The fill and border color transition over 160ms.
/// - When [reduceMotion] is true, no scale pop occurs.
///
/// UZ: Animatsiyali topshiriq bajarilganligini belgilash katagi aylanasi.
///
/// Bajarildi deb belgilanganda:
/// - Belgilash belgisi sakraydi (scale 0.6 -> 1.12 -> 1.0 260ms ichida).
/// - To'ldirish va chegara rangi 160ms davomida o'tadi.
/// - [reduceMotion] true bo'lsa, masshtab sakrashi yuz bermaydi.
class AnimatedAssignmentCheck extends StatefulWidget {
  final bool isCompleted;
  final double size;
  final BoxDecoration? decoration;

  const AnimatedAssignmentCheck({
    super.key,
    required this.isCompleted,
    this.size = 24,
    this.decoration,
  });

  @override
  State<AnimatedAssignmentCheck> createState() => _AnimatedAssignmentCheckState();
}

class _AnimatedAssignmentCheckState extends State<AnimatedAssignmentCheck>
    with SingleTickerProviderStateMixin {
  late final AnimationController _popController;
  late final Animation<double> _popAnimation;

  @override
  void initState() {
    super.initState();
    _popController = AnimationController(
      vsync: this,
      duration: AppMotion.checkPopDuration,
    );
    _popAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.6, end: 1.12)
            .chain(CurveTween(curve: AppMotion.strongEaseOut)),
        weight: 60,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.12, end: 1.0)
            .chain(CurveTween(curve: AppMotion.strongEaseOut)),
        weight: 40,
      ),
    ]).animate(_popController);

    if (widget.isCompleted) {
      _popController.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(AnimatedAssignmentCheck oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isCompleted && widget.isCompleted) {
      if (reduceMotion(context)) {
        _popController.value = 1.0;
      } else {
        _popController.forward(from: 0.0);
      }
    } else if (!widget.isCompleted) {
      _popController.value = 0.0;
    }
  }

  @override
  void dispose() {
    _popController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isReduced = reduceMotion(context);
    final isCompleted = widget.isCompleted;

    final defaultDecoration = BoxDecoration(
      shape: BoxShape.circle,
      color: isCompleted ? AppColors.primary : Colors.transparent,
      border: isCompleted
          ? null
          : Border.all(
              color: AppColors.checkboxUnchecked,
              width: 2,
            ),
    );

    return AnimatedContainer(
      duration: AppMotion.checkColorDuration,
      width: widget.size,
      height: widget.size,
      alignment: Alignment.center,
      decoration: widget.decoration ?? defaultDecoration,
      child: isCompleted
          ? AnimatedBuilder(
              animation: _popAnimation,
              builder: (context, child) => Transform.scale(
                scale: isReduced ? 1.0 : _popAnimation.value,
                child: child,
              ),
              child: const Icon(Icons.check, size: 14, color: AppColors.onPrimary),
            )
          : null,
    );
  }
}
