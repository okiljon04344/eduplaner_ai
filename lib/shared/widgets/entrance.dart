import 'dart:async';
import 'package:flutter/widgets.dart';
import '../../core/theme/app_motion.dart';

/// Entrance animation for top-level sections (Home).
///
/// Fades in and moves up 10px over 280ms with stagger delay `index * 50ms`.
/// Plays ONCE per app run. Later visits or tab switches render the final state
/// immediately without ticking animations or wrapping layers.
///
/// When [reduceMotion] is true:
/// - No movement (no Transform offset), only a 150ms opacity fade.
///
/// UZ: Yuqori darajadagi bo'limlar (Home) uchun kirish animatsiyasi.
///
/// `index * 50ms` pog'onali kechikish bilan 280ms davomida asta paydo bo'ladi (fade in) va 10px yuqoriga siljiydi.
/// Ilova har bir ishga tushirilganda BIR MARTA ijro etiladi. Keyingi tashriflar yoki tab almashishlar yakuniy
/// holatni chiquvchi animatsiyalarsiz yoki o'rab turuvchi qatlamlarsiz darhol ko'rsatadi.
///
/// [reduceMotion] rost (true) bo'lganda:
/// - Harakat yo'q (Transform ofseti yo'q), faqat 150ms xiralik o'zgarishi (fade).
class Entrance extends StatefulWidget {
  final Widget child;
  final int index;

  /// Global flag: whether the home entrance has already played.
  ///
  /// UZ: Global bayroq: asosiy kirish animatsiyasi allaqachon ijro etilganmi yoki yo'qmi.
  static bool hasPlayed = false;

  /// Resets the flag (useful for testing or replay).
  ///
  /// UZ: Bayroqni qayta tiklaydi (testlash yoki qayta ijro etish uchun foydali).
  static void reset() {
    hasPlayed = false;
  }

  const Entrance({
    super.key,
    required this.child,
    required this.index,
  });

  @override
  State<Entrance> createState() => _EntranceState();
}

class _EntranceState extends State<Entrance> with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  Timer? _delayTimer;
  bool _isFinished = false;

  @override
  void initState() {
    super.initState();
    if (Entrance.hasPlayed) {
      _isFinished = true;
      return;
    }

    final controller = AnimationController(
      vsync: this,
      duration: AppMotion.enterDuration,
    );
    _controller = controller;

    controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        Entrance.hasPlayed = true;
        if (mounted) {
          setState(() => _isFinished = true);
        }
      }
    });

    final delay = AppMotion.enterStagger * widget.index;
    if (delay == Duration.zero) {
      controller.forward();
    } else {
      _delayTimer = Timer(delay, () {
        if (mounted) controller.forward();
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null && reduceMotion(context)) {
      _controller!.duration = AppMotion.fadeDuration;
    }
  }

  @override
  void dispose() {
    _delayTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Not `Entrance.hasPlayed` here: it flips when the first section lands,
    // and a parent rebuild would snap the later, still-staggering sections.
    // UZ: Bu yerda `Entrance.hasPlayed` emas: birinchi bo'lim tushganda u qiymatini o'zgartiradi
    // va ota vidjet qayta qurilishi keyingi, hali ham kechikayotgan bo'limlarni birdaniga uzib qo'yishi mumkin.
    if (_isFinished || _controller == null) {
      return widget.child;
    }

    final isReduced = reduceMotion(context);
    final curved = CurvedAnimation(
      parent: _controller!,
      curve: AppMotion.strongEaseOut,
    );

    if (isReduced) {
      // With disableAnimations there is no Transform offset, only a fade.
      // UZ: disableAnimations bilan Transform ofseti bo'lmaydi, faqat fade bo'ladi.
      return FadeTransition(
        opacity: curved,
        child: widget.child,
      );
    }

    return FadeTransition(
      opacity: curved,
      child: AnimatedBuilder(
        animation: curved,
        builder: (context, child) {
          return Transform.translate(
            offset: Offset(0, 10.0 * (1.0 - curved.value)),
            child: child,
          );
        },
        child: widget.child,
      ),
    );
  }
}
