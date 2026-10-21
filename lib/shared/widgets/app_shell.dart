import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers/app_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/responsive.dart';
import 'app_bottom_nav.dart';
import 'app_nav_rail.dart';

/// Wraps every routed screen with a directional slide when switching tabs.
class AppShell extends StatelessWidget {
  final Widget child;
  const AppShell({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final isTablet = context.isTablet;
    return Scaffold(
      backgroundColor: AppColors.background,
      extendBody: !isTablet,
      body: isTablet
          ? Row(
              children: [
                const AppNavRail(),
                Expanded(
                  child: ResponsiveBody(
                    child: _DirectionalTab(child: child),
                  ),
                ),
              ],
            )
          : _DirectionalTab(child: child),
      bottomNavigationBar: isTablet ? null : const AppBottomNav(),
    );
  }
}

class _DirectionalTab extends ConsumerStatefulWidget {
  final Widget child;
  const _DirectionalTab({required this.child});

  @override
  ConsumerState<_DirectionalTab> createState() => _DirectionalTabState();
}

class _DirectionalTabState extends ConsumerState<_DirectionalTab> {
  bool _goingRight = true;
  // Bumped on every tab switch (even back to a previously-visited index) so
  // the KeyedSubtree below is never reused across visits — AppColors' mutable
  // statics don't flow through InheritedWidget, so a reused Element can paint
  // stale colors picked up from before this tab was last hidden.
  int _visitNonce = 0;

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(shellTabIndexProvider, (prev, next) {
      if (prev != null && prev != next) {
        setState(() {
          _goingRight = next > prev;
          _visitNonce++;
        });
      }
    });

    final index = ref.watch(shellTabIndexProvider);

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      transitionBuilder: (child, animation) {
        final dx = _goingRight ? 0.05 : -0.05;
        final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
        return SlideTransition(
          position: Tween(begin: Offset(dx, 0), end: Offset.zero).animate(curved),
          child: FadeTransition(
            opacity: curved,
            child: child,
          ),
        );
      },
      child: KeyedSubtree(key: ValueKey('${index}_$_visitNonce'), child: widget.child),
    );
  }
}
