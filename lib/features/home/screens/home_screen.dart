import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../providers/home_provider.dart';
import '../widgets/ai_study_tip_card.dart';
import '../widgets/greeting_header.dart';
import '../widgets/stats_row.dart';
import '../widgets/today_classes_row.dart';
import '../widgets/upcoming_assignments_list.dart';
import '../widgets/weak_area_card.dart';
import '../../../core/l10n/app_strings.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: AppColors.primaryLight,
          backgroundColor: AppColors.bgLayer,
          onRefresh: () async {
            ref.invalidate(aiStudyTipProvider);
            ref.invalidate(weakAreaProvider);
          },
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    clipBehavior: Clip.antiAlias,
                    child: Ink(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF6D28D9), Color(0xFF1D4ED8)],
                        ),
                      ),
                      child: InkWell(
                        onTap: () => context.push('/landing-preview'),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.play_circle_outline, size: 16, color: Colors.white),
                              const SizedBox(width: 8),
                              Text(
                                AppStrings.t('home_landing_banner'),
                                style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white,
                                  fontFamily: 'Plus Jakarta Sans',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: _HeroHeader()),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
                  child: _SectionLabel(
                    text: AppStrings.t('home_today_classes'),
                    tint: AppColors.isDark ? AppColors.primaryMid : AppColors.primaryIndigo,
                    trailingLabel: AppStrings.t('home_view_all'),
                    onTap: () => context.go('/timetable'),
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: TodayClassesRow()),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                  child: _SectionLabel(
                    text: AppStrings.t('home_upcoming'),
                    tint: AppColors.isDark ? AppColors.cyan : AppColors.primaryIndigo,
                    trailingLabel: AppStrings.t('home_view_all'),
                    onTap: () => context.go('/assignments'),
                  ),
                ),
              ),
              const SliverToBoxAdapter(
                child: Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: UpcomingAssignmentsList()),
              ),
              const SliverToBoxAdapter(
                child: Padding(padding: EdgeInsets.fromLTRB(16, 16, 16, 14), child: AiStudyTipCard()),
              ),
              const SliverToBoxAdapter(
                child: Padding(padding: EdgeInsets.fromLTRB(16, 0, 16, 110), child: WeakAreaCard()),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroHeader extends StatelessWidget {
  const _HeroHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: AppColors.heroHomeGradient,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(32),
          bottomRight: Radius.circular(32),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            if (AppColors.isDark) ...[
              Positioned(
                top: -80,
                right: -60,
                child: IgnorePointer(
                  child: Container(
                    width: 260,
                    height: 260,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [AppColors.primaryMid.withValues(alpha: 0.28), Colors.transparent],
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: -40,
                left: -30,
                child: IgnorePointer(
                  child: Container(
                    width: 180,
                    height: 180,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [AppColors.cyan.withValues(alpha: 0.15), Colors.transparent],
                      ),
                    ),
                  ),
                ),
              ),
            ] else ...[
              Positioned(
                top: -40,
                right: -30,
                child: IgnorePointer(
                  child: Container(
                    width: 160,
                    height: 160,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.06),
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: -20,
                left: -20,
                child: IgnorePointer(
                  child: Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.06),
                    ),
                  ),
                ),
              ),
            ],
            const Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                GreetingHeader(),
                SizedBox(height: 20),
                StatsRow(),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  final Color tint;
  final String trailingLabel;
  final VoidCallback onTap;
  const _SectionLabel({required this.text, required this.tint, required this.trailingLabel, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final labelColor = AppColors.isDark ? tint.withValues(alpha: 0.6) : AppColors.textPrimary;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          text,
          style: TextStyle(
            fontSize: AppColors.isDark ? 11 : 15,
            fontWeight: FontWeight.w700,
            letterSpacing: AppColors.isDark ? 0.5 : 0,
            color: labelColor,
            fontFamily: 'Plus Jakarta Sans',
            fontFamilyFallback: const ['NotoSansJP'],
          ),
        ),
        GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: tint.withValues(alpha: AppColors.isDark ? 0.12 : 0.08),
              border: Border.all(color: tint.withValues(alpha: AppColors.isDark ? 0.22 : 0.15)),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              trailingLabel,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: tint,
                fontFamily: 'Plus Jakarta Sans',
                fontFamilyFallback: const ['NotoSansJP'],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
