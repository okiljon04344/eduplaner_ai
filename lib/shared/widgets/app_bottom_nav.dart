import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';

class AppBottomNav extends StatelessWidget {
  const AppBottomNav({super.key});

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          padding: EdgeInsets.only(top: 10, bottom: bottom + 10),
          decoration: BoxDecoration(
            color: AppColors.background.withValues(alpha: 0.96),
            border: const Border(top: BorderSide(color: Color(0x0FFFFFFF), width: 1)),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                top: -10,
                left: 0,
                right: 0,
                child: Container(
                  height: 1,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(colors: [
                      Colors.transparent, Color(0x807C3AED), Color(0x4D22D3EE), Colors.transparent,
                    ]),
                  ),
                ),
              ),
              const Row(
                children: [
                  _NavItem(emoji: '🏠', label: 'HOME', route: '/home'),
                  _NavItem(emoji: '📅', label: 'SCHEDULE', route: '/timetable'),
                  _NavItem(emoji: '📝', label: 'TASKS', route: '/assignments'),
                  _NavItem(emoji: '🤖', label: 'AI', route: '/ai'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final String emoji;
  final String label;
  final String route;
  const _NavItem({required this.emoji, required this.label, required this.route});

  @override
  Widget build(BuildContext context) {
    final active = GoRouterState.of(context).matchedLocation.startsWith(route);
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => context.go(route),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedScale(
              scale: active ? 1.2 : 1.0,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutExpo,
              child: Text(emoji, style: const TextStyle(fontSize: 23, height: 1)),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
                color: active ? AppColors.primaryLight : AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 3),
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutExpo,
              width: active ? 22 : 0,
              height: 3,
              decoration: BoxDecoration(
                gradient: active ? const LinearGradient(colors: [AppColors.primary, AppColors.primaryLight]) : null,
                borderRadius: BorderRadius.circular(2),
                boxShadow: active
                    ? [BoxShadow(color: AppColors.primaryMid.withValues(alpha: 0.8), blurRadius: 8)]
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
