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

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.primaryLight,
          backgroundColor: AppColors.bgLayer,
          onRefresh: () async {
            ref.invalidate(aiStudyTipProvider);
          },
          child: CustomScrollView(
            slivers: [
              const SliverToBoxAdapter(child: _HeroHeader()),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
                  child: _SectionLabel(
                    text: "TODAY'S CLASSES",
                    tint: AppColors.primaryMid,
                    trailingLabel: '全部見る →',
                    onTap: () => context.go('/timetable'),
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: TodayClassesRow()),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                  child: _SectionLabel(
                    text: 'UPCOMING TASKS',
                    tint: AppColors.cyan,
                    trailingLabel: '全部見る →',
                    onTap: () => context.go('/assignments'),
                  ),
                ),
              ),
              const SliverToBoxAdapter(
                child: Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: UpcomingAssignmentsList()),
              ),
              const SliverToBoxAdapter(
                child: Padding(padding: EdgeInsets.fromLTRB(16, 16, 16, 110), child: AiStudyTipCard()),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: -80,
            right: -60,
            child: IgnorePointer(
              child: Container(
                width: 260,
                height: 260,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [AppColors.primaryMid.withValues(alpha: 0.28), Colors.transparent]),
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
                  gradient: RadialGradient(colors: [AppColors.cyan.withValues(alpha: 0.15), Colors.transparent]),
                ),
              ),
            ),
          ),
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
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          text,
          style: TextStyle(
            fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.5,
            color: tint.withValues(alpha: 0.6),
            fontFamily: 'Plus Jakarta Sans', fontFamilyFallback: const ['NotoSansJP'],
          ),
        ),
        GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.12),
              border: Border.all(color: tint.withValues(alpha: 0.22)),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              trailingLabel,
              style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700, color: tint,
                fontFamily: 'Plus Jakarta Sans', fontFamilyFallback: const ['NotoSansJP'],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
