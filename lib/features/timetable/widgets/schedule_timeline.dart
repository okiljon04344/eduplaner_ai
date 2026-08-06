import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../models/class_model.dart';
import '../providers/timetable_provider.dart';
import 'day_tab_row.dart';
import 'timeline_class_card.dart';

/// Vertical timeline of classes for the currently selected day, with a
/// fade+slide entrance whenever the day changes and a friendly empty state.
class ScheduleTimeline extends ConsumerWidget {
  final int selectedDay;
  const ScheduleTimeline({super.key, required this.selectedDay});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final classes = ref.watch(timetableStreamProvider).valueOrNull ?? const <ClassModel>[];
    final day = DayTabRow.days[selectedDay];
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
              itemBuilder: (context, index) => TimelineClassCard(classModel: dayClasses[index]),
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
              'この日は授業がありません',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}
