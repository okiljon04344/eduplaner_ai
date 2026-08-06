import 'package:flutter/material.dart';

/// Material 3 window size-class breakpoints (dp).
abstract class Breakpoints {
  static const compact = 600.0;
  static const medium = 840.0;
  static const expanded = 1200.0;
}

enum ScreenSize { compact, medium, expanded }

extension ResponsiveContext on BuildContext {
  double get screenWidth => MediaQuery.sizeOf(this).width;

  /// True at tablet width and above (>=600dp) — the point where a side
  /// nav rail replaces the bottom nav bar.
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
