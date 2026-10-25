import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/providers/clock_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../providers/timetable_provider.dart';
import '../widgets/add_edit_class_sheet.dart';
import '../widgets/day_tab_row.dart';
import '../widgets/schedule_timeline.dart';

/// Schedule tab: day tabs plus a vertical timeline of that day's classes.
class TimetableScreen extends ConsumerStatefulWidget {
  const TimetableScreen({super.key});

  @override
  ConsumerState<TimetableScreen> createState() => _TimetableScreenState();
}

/// Local-midnight Monday of [d]'s week (calendar arithmetic, so a DST change
/// can't push the result onto the neighbouring day).
DateTime _mondayOf(DateTime d) =>
    DateTime(d.year, d.month, d.day - (d.weekday - 1));

class _TimetableScreenState extends ConsumerState<TimetableScreen> {
  late int _selectedDay;
  int _weekOffset = 0;

  @override
  void initState() {
    super.initState();
    final weekday = DateTime.now().weekday; // 1=Mon .. 7=Sun
    _selectedDay = (weekday >= 1 && weekday <= 5) ? weekday - 1 : 0;
  }

  @override
  Widget build(BuildContext context) {
    final classCount =
        ref.watch(timetableStreamProvider).valueOrNull?.length ?? 0;
    // Watching the clock re-derives the displayed week after midnight.
    final today = ref.watch(todayProvider).valueOrNull ?? DateTime.now();
    final monday = _mondayOf(today);
    final weekStart =
        DateTime(monday.year, monday.month, monday.day + 7 * _weekOffset);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _Header(classCount: classCount),
            _WeekNavigator(
              weekStart: weekStart,
              isCurrentWeek: _weekOffset == 0,
              onPrevious: () => setState(() => _weekOffset -= 1),
              onNext: () => setState(() => _weekOffset += 1),
              onResetToday: () => setState(() => _weekOffset = 0),
            ),
            DayTabRow(
              selectedDay: _selectedDay,
              weekStart: weekStart,
              onSelect: (index) => setState(() => _selectedDay = index),
            ),
            Expanded(
                child: ScheduleTimeline(
                    selectedDay: _selectedDay, weekStart: weekStart)),
          ],
        ),
      ),
    );
  }
}

class _WeekNavigator extends StatelessWidget {
  final DateTime weekStart;
  final bool isCurrentWeek;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onResetToday;
  const _WeekNavigator({
    required this.weekStart,
    required this.isCurrentWeek,
    required this.onPrevious,
    required this.onNext,
    required this.onResetToday,
  });

  @override
  Widget build(BuildContext context) {
    final weekEnd = weekStart.add(const Duration(days: 4));
    final label =
        '${weekStart.month}/${weekStart.day} - ${weekEnd.month}/${weekEnd.day}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _NavIconButton(icon: Icons.chevron_left, onTap: onPrevious),
          GestureDetector(
            onTap: isCurrentWeek ? null : onResetToday,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                isCurrentWeek
                    ? '${AppStrings.t('tt_this_week')} · $label'
                    : label,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary.withValues(alpha: 0.8)),
              ),
            ),
          ),
          _NavIconButton(icon: Icons.chevron_right, onTap: onNext),
        ],
      ),
    );
  }
}

class _NavIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _NavIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
              color: AppColors.surfaceVar,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.border)),
          child: Icon(icon, size: 16, color: AppColors.textSecondary),
        ),
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  final int classCount;
  const _Header({required this.classCount});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = AppColors.isDark;
    return Container(
      decoration: BoxDecoration(
        gradient: isDark ? null : AppColors.heroScheduleGradient,
        border: isDark
            ? const Border(bottom: BorderSide(color: Color(0x26A855F7)))
            : null,
        borderRadius: isDark
            ? null
            : const BorderRadius.only(
                bottomLeft: Radius.circular(28),
                bottomRight: Radius.circular(28),
              ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -60,
            right: -40,
            child: IgnorePointer(
              child: Container(
                width: 180,
                height: 180,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: isDark
                      ? RadialGradient(
                          colors: [
                            AppColors.primaryMid.withValues(alpha: 0.25),
                            AppColors.primaryMid.withValues(alpha: 0)
                          ],
                        )
                      : null,
                  color: isDark ? null : Colors.white.withValues(alpha: 0.06),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 26),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppStrings.t('tt_overline'),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                          color: AppColors.accentText,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text('📅 ${AppStrings.t('tt_title')}',
                          style: AppTextStyles.headLG),
                      const SizedBox(height: 4),
                      Text(
                        AppStrings.t('tt_count')
                            .replaceAll('{n}', '$classCount'),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: () => showAddEditClassSheet(context, ref),
                  child: Container(
                    width: 44,
                    height: 44,
                    margin: const EdgeInsets.only(top: 2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: AppColors.gradientPrimary,
                      boxShadow: [
                        BoxShadow(
                            color: AppColors.primaryMid.withValues(alpha: 0.5),
                            blurRadius: 20)
                      ],
                    ),
                    child: const Icon(Icons.add,
                        color: AppColors.onPrimary, size: 22),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
