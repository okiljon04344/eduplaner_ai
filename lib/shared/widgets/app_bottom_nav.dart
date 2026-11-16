import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_motion.dart';
import 'glass_panel.dart';
import 'nav_destinations.dart';
import 'pressable.dart';

/// Mobile bottom navigation bar — floating glass bar over the content.
///
/// UZ: Mobil pastki navigatsiya paneli — kontent ustidagi suzuvchi shisha panel.
class AppBottomNav extends StatelessWidget {
  const AppBottomNav({super.key});

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    // Scrim: content scrolling under the floating bar fades out instead of
    // showing through the gap between the bar and the screen edge.
    // UZ: Xiralashtiruvchi parda (scrim): suzuvchi panel ostida aylanayotgan tarkib panel va ekran
    // cheti orasidagi bo'shliqdan ko'rinib qolish o'rniga asta yo'qoladi (fades out).
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.background.withValues(alpha: 0),
            AppColors.background
          ],
          stops: const [0, 0.55],
        ),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(12, 0, 12, 14 + bottom),
        child: GlassPanel(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
          radius: 26,
          tint: AppColors.navGlassFill,
          borderColor: AppColors.navGlassBorder,
          shadows: AppColors.navGlassShadow,
          blurSigma: 24,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final activeIndex =
                  kNavRoutes.indexWhere((r) => isNavRouteActive(context, r));
              final currentIndex = activeIndex >= 0 ? activeIndex : 0;
              final count = kNavRoutes.length;
              final isReduced = reduceMotion(context);
              final alignX =
                  count > 1 ? -1.0 + (currentIndex * (2.0 / (count - 1))) : 0.0;

              return Stack(
                children: [
                  Positioned.fill(
                    child: AnimatedAlign(
                      duration:
                          isReduced ? Duration.zero : AppMotion.pillDuration,
                      curve: AppMotion.strongEaseOut,
                      alignment: Alignment(alignX, 0.0),
                      child: FractionallySizedBox(
                        widthFactor: 1.0 / count,
                        heightFactor: 1.0,
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(
                              alpha: AppColors.isDark ? 0.18 : 0.16,
                            ),
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      for (var i = 0; i < count; i++)
                        Expanded(
                          child: Pressable(
                            child: NavDestination(i, showOwnPill: false),
                          ),
                        ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
