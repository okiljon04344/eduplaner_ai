import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../assignments/providers/assignments_provider.dart';
import '../providers/home_provider.dart';
import '../../../core/l10n/app_strings.dart';

/// Three stat pills (streak / weekly done / urgent count), each in its own
/// [Consumer] so a change in one provider rebuilds only that pill.
class StatsRow extends StatelessWidget {
  const StatsRow({super.key});

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Expanded(child: _StreakPill()),
        SizedBox(width: 10),
        Expanded(child: _WeeklyPill()),
        SizedBox(width: 10),
        Expanded(child: _UrgentPill()),
      ],
    );
  }
}

class _StreakPill extends ConsumerWidget {
  const _StreakPill();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final streak = ref.watch(dailyStreakProvider).valueOrNull ?? 0;
    return _StatPill(
      value: '$streak',
      label: AppStrings.t('home_streak'),
      color: AppColors.isDark ? AppColors.primaryLight : AppColors.primaryDark,
      tint: AppColors.primaryMid,
    );
  }
}

class _WeeklyPill extends ConsumerWidget {
  const _WeeklyPill();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final weekly = ref.watch(weeklyProgressProvider);
    return _StatPill(
      value: '${weekly.completed}/${weekly.total}',
      label: AppStrings.t('home_completed'),
      color: AppColors.isDark ? AppColors.primaryMid : AppColors.primaryDark,
      tint: AppColors.primaryMid,
    );
  }
}

class _UrgentPill extends ConsumerWidget {
  const _UrgentPill();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final weekly = ref.watch(weeklyProgressProvider);
    final percent = weekly.total == 0 ? 0 : ((weekly.completed / weekly.total) * 100).round();
    return _StatPill(
      value: '$percent%',
      label: AppStrings.t('home_weekly_percent'),
      color: AppColors.isDark ? AppColors.primaryLight : AppColors.primaryDark,
      tint: AppColors.primaryLight,
    );
  }
}

class _StatPill extends StatelessWidget {
  final String value;
  final String label;
  final Color color;
  final Color tint;
  const _StatPill({required this.value, required this.label, required this.color, required this.tint});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        gradient: AppColors.isDark
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [tint.withValues(alpha: 0.18), tint.withValues(alpha: 0.05)],
              )
            : null,
        color: AppColors.isDark ? null : AppColors.glassBg,
        border: Border.all(
          color: AppColors.isDark ? tint.withValues(alpha: 0.3) : AppColors.glassBorder,
        ),
        borderRadius: BorderRadius.circular(AppColors.isDark ? 18 : 14),
      ),
      child: Column(
        children: [
          Text(
            value,
            textAlign: TextAlign.center,
            style: AppTextStyles.statNumber.copyWith(color: color),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              color: color.withValues(alpha: 0.6),
              fontFamily: 'Plus Jakarta Sans',
              fontFamilyFallback: const ['NotoSansJP'],
            ),
          ),
        ],
      ),
    );
  }
}
