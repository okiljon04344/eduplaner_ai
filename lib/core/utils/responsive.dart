import 'package:flutter/material.dart';

/// Material 3 window size-class breakpoints (dp).
///
/// UZ: Material 3 oyna o'lchami toifasi nuqtalari (breakpoints) (dp).
abstract class Breakpoints {
  static const compact = 600.0;
  static const medium = 840.0;
  static const expanded = 1200.0;
}

/// Screen width classification categories following Material 3 window size classes.
///
/// UZ: Material 3 oyna o'lchami toifalariga mos keladigan ekran kengligi tasniflari toifalari.
enum ScreenSize { compact, medium, expanded }

/// Convenient screen geometry and breakpoint inspection helpers on [BuildContext].
///
/// UZ: [BuildContext] uchun qulay ekran geometriyasi va breakpoint tekshirish yordamchilari.
extension ResponsiveContext on BuildContext {
  double get screenWidth => MediaQuery.sizeOf(this).width;

  /// True at tablet width and above (>=600dp) — the point where a side
  /// nav rail replaces the bottom nav bar.
  ///
  /// UZ: Planshet kengligi va undan yuqori (>=600dp) bo'lganda true — yon
  /// navigatsiya paneli (nav rail) pastki navigatsiya panelini almashtiradigan nuqta.
  bool get isTablet => screenWidth >= Breakpoints.compact;

  ScreenSize get screenSize {
    final w = screenWidth;
    if (w >= Breakpoints.medium) return ScreenSize.expanded;
    if (w >= Breakpoints.compact) return ScreenSize.medium;
    return ScreenSize.compact;
  }
}

/// Centers [child] and clamps it to [maxWidth] once the viewport is wider
/// than that, so phone-tuned layouts don't stretch into unreadably long
/// rows/lines on tablets and desktop. No-ops below [maxWidth].
///
/// On [ScreenSize.expanded] screens (>=1200dp — a real desktop window, not
/// just a tablet), [expandedMaxWidth] is used instead so wide monitors get a
/// noticeably wider column rather than the same tablet-tuned width with huge
/// empty margins on both sides. Defaults to 1.3x [maxWidth].
///
/// UZ: Viewport [maxWidth] dan kengroq bo'lganda [child] ni markazlashtiradi va [maxWidth]
/// bilan cheklaydi, shunda telefonga moslangan tartiblar planshet va kompyuterlarda o'qib
/// bo'lmaydigan darajada uzun qatorlarga cho'zilib ketmaydi. [maxWidth] dan kichik bo'lsa hech narsa qilmaydi.
///
/// [ScreenSize.expanded] ekranlarda (>=1200dp — shunchaki planshet emas, haqiqiy ish stoli oynasi),
/// buning o'rniga [expandedMaxWidth] ishlatiladi, shunda keng monitorlar ikkala tomonda ulkan
/// bo'sh hoshiyalarga ega bo'lgan planshet kengligi o'rniga sezilarli darajada kengroq ustun oladi.
/// Standart qiymat: 1.3x [maxWidth].
class ResponsiveBody extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  final double? expandedMaxWidth;
  const ResponsiveBody({super.key, required this.child, this.maxWidth = 900, this.expandedMaxWidth});

  @override
  Widget build(BuildContext context) {
    final effectiveMaxWidth = context.screenSize == ScreenSize.expanded ? (expandedMaxWidth ?? maxWidth * 1.3) : maxWidth;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: effectiveMaxWidth),
        child: child,
      ),
    );
  }
}
