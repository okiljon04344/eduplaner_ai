import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers/app_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_motion.dart';
import '../../core/utils/responsive.dart';
import '../../features/school/school_providers.dart';
import 'app_bottom_nav.dart';
import 'app_nav_rail.dart';

/// Wraps every routed screen with a directional slide when switching tabs.
class AppShell extends ConsumerWidget {
  final Widget child;
  const AppShell({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(schoolReminderSyncProvider);
    final isTablet = context.isTablet;
    return Scaffold(
      backgroundColor: AppColors.background,
      extendBody: !isTablet,
      body: isTablet
          ? Row(
              children: [
                const AppNavRail(),
                // Each tab clamps its own content column, so glows and
                // full-bleed headers can span the whole area.
                Expanded(child: _DirectionalTab(child: child)),
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
          _visitNonce++;
        });
      }
    });

    final index = ref.watch(shellTabIndexProvider);
    final isReduced = reduceMotion(context);

    return AnimatedSwitcher(
      duration: isReduced ? AppMotion.fadeDuration : AppMotion.screenDuration,
      transitionBuilder: (child, animation) {
        if (isReduced) {
          return FadeTransition(
            opacity: animation,
            child: child,
          );
        }
        final curved = CurvedAnimation(parent: animation, curve: AppMotion.strongEaseOut);
        return FadeTransition(
          opacity: curved,
          child: AnimatedBuilder(
            animation: curved,
            builder: (context, child) => Transform.translate(
              offset: Offset(0, 10.0 * (1.0 - curved.value)),
              child: child,
            ),
            child: child,
          ),
        );
      },
      child: KeyedSubtree(key: ValueKey('${index}_$_visitNonce'), child: widget.child),
    );
  }
}
