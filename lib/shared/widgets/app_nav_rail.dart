import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/theme/app_colors.dart';
import 'nav_destinations.dart';

/// Tablet/desktop side navigation rail — same four destinations as
/// [AppBottomNav] but laid out vertically to make use of extra width.
///
/// Solid background (no BackdropFilter) for lower compositing cost on
/// the web and mid-range Android devices.
class AppNavRail extends StatelessWidget {
  const AppNavRail({super.key});

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Container(
      width: 96,
      padding: EdgeInsets.only(top: top + 24, bottom: 24),
      decoration: BoxDecoration(
        color: AppColors.background,
        border: Border(right: BorderSide(color: AppColors.navBorder, width: 0.5)),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Decorative vertical gradient line — cheap, no blur required.
          Positioned(
            top: 0,
            bottom: 0,
            right: -10,
            child: Container(
              width: 1,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Color(0x8006D6A0), Color(0x4D34D399), Colors.transparent],
                ),
              ),
            ),
          ),
          Column(
            children: [
              const SizedBox(height: 8),
              _RailItem(emoji: '🏠', label: AppStrings.t('nav_home'), route: '/home'),
              const SizedBox(height: 28),
              _RailItem(emoji: '📅', label: AppStrings.t('nav_timetable'), route: '/timetable'),
              const SizedBox(height: 28),
              _RailItem(emoji: '📝', label: AppStrings.t('nav_assignments'), route: '/assignments'),
              const SizedBox(height: 28),
              _RailItem(emoji: '🤖', label: AppStrings.t('nav_ai'), route: '/ai'),
            ],
          ),
        ],
      ),
    );
  }
}

class _RailItem extends ConsumerWidget {
  final String emoji;
  final String label;
  final String route;
  const _RailItem({required this.emoji, required this.label, required this.route});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = isNavRouteActive(context, route);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => navigateToNavRoute(ref, context, route),
      child: SizedBox(
        width: 96,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutExpo,
              width: 52,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: active ? AppColors.primary.withValues(alpha: 0.16) : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
                border: active ? Border.all(color: AppColors.borderPrimary) : null,
              ),
              child: AnimatedScale(
                scale: active ? 1.15 : 1.0,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutExpo,
                child: Text(emoji, style: const TextStyle(fontSize: 22, height: 1)),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
                color: active ? AppColors.accentText : AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
