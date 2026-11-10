import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion.dart';
import '../../../shared/widgets/entrance.dart';
import '../../../shared/widgets/pressable.dart';
import '../../assignments/providers/assignments_provider.dart';
import '../providers/home_provider.dart';
import 'today_lessons.dart';

/// Today at a glance: lessons today · assignments due within 3 days · streak,
/// 3 translucent stat cards inside the top glass block.
class StatsRow extends ConsumerWidget {
  const StatsRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lessons = ref.watch(todayLessonsProvider).where((l) => !l.cancelled).length;
    final due = ref.watch(urgentAssignmentsCountProvider);
    final streak = ref.watch(dailyStreakProvider).valueOrNull ?? 0;
    final animate = !Entrance.hasPlayed && !reduceMotion(context);

    return Row(
      children: [
        Expanded(
          child: _StatCard(
            count: lessons,
            format: (n) => '$n',
            label: AppStrings.t('home_stat_classes'),
            animate: animate,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _StatCard(
            count: due,
            format: (n) => '$n',
            label: AppStrings.t('home_stat_due3'),
            color: due > 0 ? AppColors.warning : null,
            animate: animate,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _StatCard(
            count: streak,
            format: (n) => AppStrings.t('home_days', {'n': n}),
            label: AppStrings.t('home_stat_streak'),
            color: AppColors.accentText,
            animate: animate,
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final int count;
  final String Function(int) format;
  final String label;
  final Color? color;
  final bool animate;

  const _StatCard({
    required this.count,
    required this.format,
    required this.label,
    this.color,
    this.animate = false,
  });

  @override
  Widget build(BuildContext context) {
    Widget buildNumberText(String text) => Text(
          text,
          style: TextStyle(
            fontFamily: 'Space Grotesk',
            fontFamilyFallback: const ['Plus Jakarta Sans', 'NotoSansJP'],
            fontSize: 24,
            height: 1.25,
            fontWeight: FontWeight.w700,
            color: color ?? AppColors.textPrimary,
          ),
        );

    final numberWidget = animate
        ? TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0.0, end: 1.0),
            duration: AppMotion.countUpDuration,
            curve: AppMotion.strongEaseOut,
            builder: (context, value, _) => buildNumberText(format((count * value).round())),
          )
        : buildNumberText(format(count));

    return Pressable(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: AppColors.statGlassFill,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.statGlassBorder),
        ),
        child: Column(
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: numberWidget,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                height: 1.4,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
