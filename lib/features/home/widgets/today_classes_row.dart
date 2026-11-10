import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/providers/clock_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_helper.dart';
import '../../school/models/school.dart';
import '../../school/school_providers.dart';
import '../../timetable/providers/timetable_provider.dart';
import '../../timetable/widgets/school_slot_card.dart';
import 'home_class_card.dart';
import '../../../core/l10n/app_strings.dart';

/// Vertical stack of today's classes (the currently-live one gets a glowing
/// highlighted card), matching the dark-neon design's home layout.
class TodayClassesRow extends ConsumerWidget {
  const TodayClassesRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final classes = ref.watch(todayClassesProvider);
    final now = ref.watch(todayProvider).valueOrNull ?? DateTime.now();
    final monday = DateTime(now.year, now.month, now.day - (now.weekday - 1));
    // School lessons (with teacher changes) come first; personal classes follow.
    final schoolSlots = ref.watch(schoolWeekProvider(monday)).valueOrNull?[DateHelper.dayKey(now)]?.slots ??
        const <SchoolSlot>[];
    final periods = ref.watch(schoolInfoProvider).valueOrNull?.periods ?? const <SchoolPeriod>[];
    if (classes.isEmpty && schoolSlots.isEmpty) {
      final isWeekend = now.weekday > 5;
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
        children: [
          for (final slot in schoolSlots)
            GestureDetector(
              onTap: () => context.go('/timetable'),
              child: SchoolSlotCard(
                slot: slot,
                period: periods.where((p) => p.key == slot.period).firstOrNull,
              ),
            ),
          for (final c in classes) HomeClassCard(classModel: c),
        ],
      ),
    );
  }
}
