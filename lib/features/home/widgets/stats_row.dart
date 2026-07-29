import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../assignments/providers/assignments_provider.dart';
import '../providers/home_provider.dart';

/// Hero stats grid: 3 equal glass pills (streak / weekly done-total / urgent
/// count), each a big Space Grotesk number + tiny uppercase emoji caption.
class StatsRow extends ConsumerWidget {
  const StatsRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final streak = ref.watch(dailyStreakProvider).valueOrNull ?? 0;
    final weekly = ref.watch(weeklyProgressProvider);
    final urgent = ref.watch(urgentAssignmentsCountProvider);

    return Row(
      children: [
        Expanded(child: _StatPill(value: '$streak', label: '🔥 STREAK', color: AppColors.primaryLight, tint: AppColors.primaryMid)),
        const SizedBox(width: 10),
        Expanded(child: _StatPill(value: '${weekly.completed}/${weekly.total}', label: '✅ DONE', color: AppColors.cyan, tint: AppColors.cyan)),
        const SizedBox(width: 10),
        Expanded(child: _StatPill(value: '$urgent', label: '⏰ URGENT', color: AppColors.amber, tint: AppColors.amber)),
      ],
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
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [tint.withValues(alpha: 0.18), tint.withValues(alpha: 0.05)],
        ),
        border: Border.all(color: tint.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          Text(value, textAlign: TextAlign.center, style: AppTextStyles.statNumber.copyWith(color: color)),
          const SizedBox(height: 3),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.5,
              color: color.withValues(alpha: 0.6),
              fontFamily: 'Plus Jakarta Sans', fontFamilyFallback: const ['NotoSansJP'],
            ),
          ),
        ],
      ),
    );
  }
}
