import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import 'app_bottom_nav.dart';

class AppShell extends StatelessWidget {
  final Widget child;
  const AppShell({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      extendBody: true,
      body: child,
      bottomNavigationBar: const AppBottomNav(),
    );
  }
}
