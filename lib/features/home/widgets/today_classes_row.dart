import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/clock_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../timetable/providers/timetable_provider.dart';
import 'home_class_card.dart';
import '../../../core/l10n/app_strings.dart';

/// Vertical stack of today's classes; the live one is highlighted.
class TodayClassesRow extends ConsumerWidget {
  const TodayClassesRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final classes = ref.watch(todayClassesProvider);
    if (classes.isEmpty) {
      final isWeekend = (ref.watch(todayProvider).valueOrNull ?? DateTime.now()).weekday > 5;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Text(
          AppStrings.t(isWeekend ? 'home_weekend_msg' : 'home_no_classes'),
          style: TextStyle(fontSize: 13, color: AppColors.textMuted, fontFamily: 'Plus Jakarta Sans', fontFamilyFallback: const ['NotoSansJP']),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [for (final c in classes) HomeClassCard(classModel: c)],
      ),
    );
  }
}
