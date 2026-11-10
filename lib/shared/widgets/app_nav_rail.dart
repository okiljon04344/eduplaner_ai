import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import 'nav_destinations.dart';

/// Tablet/desktop side navigation rail — same five destinations as
/// [AppBottomNav], laid out vertically.
class AppNavRail extends StatelessWidget {
  const AppNavRail({super.key});

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Container(
      width: 88,
      padding: EdgeInsets.only(top: top + 24, bottom: 24),
      decoration: BoxDecoration(
        color: AppColors.navBg,
        border: Border(right: BorderSide(color: AppColors.navBorder)),
      ),
      child: Column(
        children: [
          for (var i = 0; i < kNavRoutes.length; i++) ...[
            if (i > 0) const SizedBox(height: 20),
            NavDestination(i),
          ],
        ],
      ),
    );
  }
}
