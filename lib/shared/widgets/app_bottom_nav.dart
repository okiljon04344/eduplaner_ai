import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/theme/app_colors.dart';
import 'nav_destinations.dart';

/// Mobile bottom navigation for the four main destinations. Solid background
/// (no BackdropFilter) to keep compositing cheap.
class AppBottomNav extends StatelessWidget {
  const AppBottomNav({super.key});

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.navBg,
        border: Border(top: BorderSide(color: AppColors.navBorder, width: 0.5)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Gradient fade into the bar instead of a blur.
          if (AppColors.isDark)
            Container(
              height: 1,
              decoration: const BoxDecoration(
                gradient: LinearGradient(colors: [
                  Colors.transparent,
                  Color(0x6006D6A0),
                  Color(0x3534D399),
                  Colors.transparent,
                ]),
              ),
            ),
          Padding(
            padding: EdgeInsets.only(top: 10, bottom: bottom + 10),
            child: RepaintBoundary(
              child: Row(
                children: [
                  _NavItem(icon: Icons.home_outlined, activeIcon: Icons.home_rounded, label: AppStrings.t('nav_home'), route: '/home'),
                  _NavItem(icon: Icons.calendar_month_outlined, activeIcon: Icons.calendar_month_rounded, label: AppStrings.t('nav_timetable'), route: '/timetable'),
                  _NavItem(icon: Icons.task_alt_outlined, activeIcon: Icons.task_alt_rounded, label: AppStrings.t('nav_assignments'), route: '/assignments'),
                  _NavItem(icon: Icons.smart_toy_outlined, activeIcon: Icons.smart_toy_rounded, label: AppStrings.t('nav_ai'), route: '/ai'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends ConsumerWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final String route;
  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.route,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = isNavRouteActive(context, route);
    final activeColor = AppColors.isDark ? AppColors.primaryLight : AppColors.primaryDark;
    final inactiveColor = AppColors.textMuted;

    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => navigateToNavRoute(ref, context, route),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutExpo,
              width: active ? 32 : 0,
              height: 3,
              margin: const EdgeInsets.only(bottom: 4),
              decoration: BoxDecoration(
                color: active ? activeColor : Colors.transparent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            AnimatedScale(
              scale: active ? 1.18 : 1.0,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutExpo,
              child: Icon(
                active ? activeIcon : icon,
                size: 24,
                color: active ? activeColor : inactiveColor,
                shadows: active
                    ? [Shadow(color: activeColor.withValues(alpha: 0.7), blurRadius: 8)]
                    : null,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
                color: active ? activeColor : inactiveColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
