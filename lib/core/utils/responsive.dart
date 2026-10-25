import 'package:flutter/material.dart';

/// Material 3 window size-class breakpoints (dp).
abstract class Breakpoints {
  static const compact = 600.0;
  static const medium = 840.0;
}

enum ScreenSize { compact, medium, expanded }

extension ResponsiveContext on BuildContext {
  double get screenWidth => MediaQuery.sizeOf(this).width;

  /// True from 600dp up, where the side nav rail replaces the bottom bar.
  bool get isTablet => screenWidth >= Breakpoints.compact;

  ScreenSize get screenSize {
    final w = screenWidth;
    if (w >= Breakpoints.medium) return ScreenSize.expanded;
    if (w >= Breakpoints.compact) return ScreenSize.medium;
    return ScreenSize.compact;
  }
}

/// Centers [child] and clamps it to [maxWidth] so phone-tuned layouts don't
/// stretch into unreadably long lines on tablets and desktop. On
/// [ScreenSize.expanded] screens [expandedMaxWidth] applies instead (default
/// 1.3x [maxWidth]) so wide windows aren't left with huge empty margins.
class ResponsiveBody extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  final double? expandedMaxWidth;
  const ResponsiveBody(
      {super.key,
      required this.child,
      this.maxWidth = 900,
      this.expandedMaxWidth});

  @override
  Widget build(BuildContext context) {
    final effectiveMaxWidth = context.screenSize == ScreenSize.expanded
        ? (expandedMaxWidth ?? maxWidth * 1.3)
        : maxWidth;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: effectiveMaxWidth),
        child: child,
      ),
    );
  }
}
