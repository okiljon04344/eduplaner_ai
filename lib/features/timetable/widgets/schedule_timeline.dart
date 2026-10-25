import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../models/class_model.dart';
import '../providers/timetable_provider.dart';
import 'timeline_class_card.dart';

/// Timeline of the selected day's classes with a fade+slide entrance on day
/// change and an empty state. [weekStart] (Monday) and [selectedDay] give each
/// card its exact date.
class ScheduleTimeline extends ConsumerWidget {
  final int selectedDay;
  final DateTime weekStart;
  const ScheduleTimeline({super.key, required this.selectedDay, required this.weekStart});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final classes = ref.watch(timetableStreamProvider).valueOrNull ?? const <ClassModel>[];
    // Compare against the canonical kanji key, not the localized label from
    // DayTabRow.days, which differs in every non-Japanese locale.
    final day = kWeekdayKanji[selectedDay];
    final date = DateTime(weekStart.year, weekStart.month, weekStart.day + selectedDay);
    final dayClasses = classes.where((c) => c.dayOfWeek == day).toList()
      ..sort((a, b) => a.period.compareTo(b.period));

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      switchInCurve: Curves.easeOutExpo,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 0.04), end: Offset.zero).animate(animation),
          child: child,
        ),
      ),
      child: dayClasses.isEmpty
          ? _EmptyDay(key: ValueKey('empty-$selectedDay'))
          : ListView.builder(
              key: ValueKey('list-$selectedDay'),
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
              itemCount: dayClasses.length,
              itemBuilder: (context, index) => TimelineClassCard(classModel: dayClasses[index], date: date),
            ),
    );
  }
}

class _EmptyDay extends StatelessWidget {
  const _EmptyDay({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🌤️', style: TextStyle(fontSize: 40)),
            const SizedBox(height: 12),
            Text(
              AppStrings.t('tt_no_classes_day'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}
