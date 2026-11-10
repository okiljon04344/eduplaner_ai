import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/providers/app_providers.dart';
import '../../core/theme/app_colors.dart';

/// The five main app destinations — shared by [AppBottomNav] and
/// [AppNavRail] (mobile bottom nav vs. tablet/desktop side rail).
const kNavRoutes = ['/home', '/timetable', '/assignments', '/ai', '/settings'];

const _kNavIcons = <(IconData, IconData, String)>[
  (Icons.home_outlined, Icons.home_rounded, 'nav_home'),
  (Icons.calendar_month_outlined, Icons.calendar_month_rounded, 'nav_timetable'),
  (Icons.task_alt_outlined, Icons.task_alt_rounded, 'nav_assignments'),
  (Icons.auto_awesome_outlined, Icons.auto_awesome, 'nav_ai'),
  (Icons.tune_outlined, Icons.tune_rounded, 'nav_settings'),
];

/// Whether [route] is the currently active destination for [context].
bool isNavRouteActive(BuildContext context, String route) =>
    GoRouterState.of(context).matchedLocation.startsWith(route);

/// Updates [shellTabIndexProvider] to match [route] and navigates to it —
/// shared tap handler for both nav bar and nav rail items.
void navigateToNavRoute(WidgetRef ref, BuildContext context, String route) {
  final idx = kNavRoutes.indexOf(route);
  if (idx >= 0) ref.read(shellTabIndexProvider.notifier).state = idx;
  context.go(route);
}

/// One destination: icon in a pill (tinted when active) over its label.
class NavDestination extends ConsumerWidget {
  final int index;
  final bool showOwnPill;
  const NavDestination(this.index, {super.key, this.showOwnPill = true});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final route = kNavRoutes[index];
    final (icon, activeIcon, labelKey) = _kNavIcons[index];
    final active = isNavRouteActive(context, route);
    final iconColor = active ? AppColors.accentText : AppColors.textMuted;
    final textColor = active ? AppColors.textPrimary : AppColors.textMuted;

    return Semantics(
      button: true,
      selected: active,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => navigateToNavRoute(ref, context, route),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 60,
              height: 32,
              decoration: BoxDecoration(
                color: (showOwnPill && active)
                    ? AppColors.primary.withValues(alpha: AppColors.isDark ? 0.18 : 0.16)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
              ),
              child: TweenAnimationBuilder<Color?>(
                duration: const Duration(milliseconds: 200),
                tween: ColorTween(end: iconColor),
                builder: (context, color, _) => Icon(
                  active ? activeIcon : icon,
                  size: 22,
                  color: color,
                ),
              ),
            ),
            const SizedBox(height: 4),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: TextStyle(
                fontSize: 12,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                color: textColor,
              ),
              child: Text(
                AppStrings.t(labelKey),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
