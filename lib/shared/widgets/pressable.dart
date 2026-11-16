import 'package:flutter/widgets.dart';
import '../../core/theme/app_motion.dart';

/// A widget that scales to [scale] (default 0.97) in 120ms on pointer down,
/// and bounces back on pointer up or cancel.
///
/// When [onTap] is provided:
/// - Provides `Semantics(button: true)` and enforces a 44px minimum hit target.
/// - Fires [onTap] on tap up.
///
/// When [onTap] is null (e.g. wrapping a child that contains an `InkWell`):
/// - Uses a transparent [Listener] to detect pointer down/up purely for the visual scale effect.
/// - Does not consume gesture arena events, allowing inner taps/ripples to function untouched.
///
/// If [reduceMotion] is true:
/// - No scale transformation is applied (stays at 1.0).
///
/// UZ: Ko'rsatkich bosilganda 120ms ichida [scale] ga (standart 0.97) qisqaradigan va ko'rsatkich
/// ko'tarilganda yoki bekor qilinganda orqaga qaytadigan vidjet.
///
/// [onTap] berilganda:
/// - `Semantics(button: true)` ni ta'minlaydi va 44px minimal bosish sohasini majburiy qiladi.
/// - Bosib qo'yib yuborilganda [onTap] ni chaqiradi.
///
/// [onTap] null bo'lganda (masalan, `InkWell` ni o'z ichiga olgan vidjetni o'rashda):
/// - Faqat vizual masshtab effekti uchun bosish/qo'yib yuborishni sezishda shaffof [Listener] ishlatadi.
/// - Imo-ishoralar (gesture arena) hodisalarini yutmaydi, ichki bosishlar/to'lqinlar o'zgarishsiz ishlashiga imkon beradi.
///
/// Agar [reduceMotion] true bo'lsa:
/// - Hech qanday masshtab transformatsiyasi qo'llanilmaydi (1.0 da qoladi).
class Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double scale;
  final Duration duration;
  final Curve curve;
  final HitTestBehavior behavior;

  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.scale = AppMotion.pressScale,
    this.duration = AppMotion.pressDuration,
    this.curve = AppMotion.strongEaseOut,
    this.behavior = HitTestBehavior.opaque,
  });

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value && mounted) {
      setState(() => _pressed = value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isReduced = reduceMotion(context);
    final targetScale = (isReduced || !_pressed) ? 1.0 : widget.scale;

    final Widget content = AnimatedScale(
      scale: targetScale,
      duration: isReduced ? Duration.zero : widget.duration,
      curve: widget.curve,
      child: widget.child,
    );

    if (widget.onTap != null) {
      return Semantics(
        button: true,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          child: GestureDetector(
            behavior: widget.behavior,
            onTapDown: (_) => _setPressed(true),
            onTapUp: (_) => _setPressed(false),
            onTapCancel: () => _setPressed(false),
            onTap: widget.onTap,
            child: content,
          ),
        ),
      );
    }

    // Purely visual scaling for children that already handle their own tap (e.g. InkWell).
    // UZ: O'z bosilishini allaqachon boshqaradigan vidjetlar uchun faqat vizual masshtablash (masalan, InkWell).
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _setPressed(true),
      onPointerUp: (_) => _setPressed(false),
      onPointerCancel: (_) => _setPressed(false),
      child: content,
    );
  }
}
