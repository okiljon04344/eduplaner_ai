import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:table_calendar/table_calendar.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../models/assignment_model.dart';
import '../providers/assignments_provider.dart';
import '../widgets/add_edit_assignment_sheet.dart';
import '../widgets/assignment_card.dart';
import '../widgets/filter_chips_row.dart';

class AssignmentsScreen extends ConsumerStatefulWidget {
  const AssignmentsScreen({super.key});

  @override
  ConsumerState<AssignmentsScreen> createState() => _AssignmentsScreenState();
}

class _AssignmentsScreenState extends ConsumerState<AssignmentsScreen> {
  bool _calendarMode = false;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(assignmentsStreamProvider).valueOrNull ?? [];
    final doneCount = all.where((a) => a.status == AssignmentStatus.completed).length;
    final progressPct = all.isEmpty ? 0.0 : doneCount / all.length;
    final weekly = ref.watch(weeklyProgressProvider);

    // In calendar mode with a selected day: show only that day's assignments
    final displayAssignments = (_calendarMode && _selectedDay != null)
        ? all.where((a) => _sameDay(a.dueDate, _selectedDay!)).toList()
        : ref.watch(filteredAssignmentsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: _TasksHeader(
                doneCount: doneCount,
                totalCount: all.length,
                progressPct: progressPct,
                weekly: weekly,
                calendarMode: _calendarMode,
                onToggleCalendar: () => setState(() {
                  _calendarMode = !_calendarMode;
                  if (!_calendarMode) _selectedDay = null;
                }),
              ),
            ),
            if (_calendarMode)
              SliverToBoxAdapter(
                child: _AssignmentCalendar(
                  assignments: all,
                  focusedDay: _focusedDay,
                  selectedDay: _selectedDay,
                  onDaySelected: (selected, focused) => setState(() {
                    _selectedDay = _sameDay(selected, _selectedDay ?? DateTime(0))
                        ? null // tap same day to deselect
                        : selected;
                    _focusedDay = focused;
                  }),
                  onFocusedDayChanged: (focused) =>
                      setState(() => _focusedDay = focused),
                ),
              ),
            if (!_calendarMode) const SliverToBoxAdapter(child: FilterChipsRow()),
            if (_calendarMode && _selectedDay != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Text(
                    AppStrings.t('as_day_title')
                        .replaceAll('{month}', '${_selectedDay!.month}')
                        .replaceAll('{day}', '${_selectedDay!.day}')
                        .replaceAll('{n}', '${displayAssignments.length}'),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primaryMid.withValues(alpha: 0.8),
                      fontFamily: 'Plus Jakarta Sans',
                      fontFamilyFallback: const ['NotoSansJP'],
                    ),
                  ),
                ),
              ),
            if (displayAssignments.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Center(
                    child: Text(
                      _calendarMode && _selectedDay != null
                          ? AppStrings.t('as_empty_day')
                          : AppStrings.t('as_empty'),
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textMuted,
                        fontFamily: 'Plus Jakarta Sans',
                        fontFamilyFallback: const ['NotoSansJP'],
                      ),
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                sliver: SliverList.separated(
                  itemCount: displayAssignments.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => AssignmentCard(
                    key: ValueKey(displayAssignments[i].id),
                    assignment: displayAssignments[i],
                  ),
                ),
              ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                child: _AddTaskButton(
                  onTap: () => showAddEditAssignmentSheet(context, ref),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Header ─────────────────────────────────────────────────────────────────

class _TasksHeader extends StatelessWidget {
  final int doneCount;
  final int totalCount;
  final double progressPct;
  final ({int completed, int total}) weekly;
  final bool calendarMode;
  final VoidCallback onToggleCalendar;

  const _TasksHeader({
    required this.doneCount,
    required this.totalCount,
    required this.progressPct,
    required this.weekly,
    required this.calendarMode,
    required this.onToggleCalendar,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = AppColors.isDark;
    final accent = AppColors.accentText;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
      decoration: BoxDecoration(
        gradient: isDark ? null : AppColors.heroTasksGradient,
        border: isDark
            ? const Border(bottom: BorderSide(color: Color(0x2606D6A0)))
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
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: isDark
                    ? const RadialGradient(
                        colors: [Color(0x2E06D6A0), Color(0x0006D6A0)],
                        stops: [0.0, 0.7],
                      )
                    : null,
                color: isDark ? null : AppColors.primary.withValues(alpha: 0.06),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Overline + calendar toggle
              Row(
                children: [
                  Text(
                    AppStrings.t('as_overline'),
                    style: AppTextStyles.overline.copyWith(color: accent),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: onToggleCalendar,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: calendarMode ? 0.25 : (isDark ? 0.05 : 0.12)),
                        border: Border.all(
                          color: accent.withValues(alpha: calendarMode ? 0.6 : 0.3),
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            calendarMode ? Icons.list_rounded : Icons.calendar_month_outlined,
                            size: 13,
                            color: accent,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            calendarMode ? AppStrings.t('as_list_view') : AppStrings.t('as_calendar_view'),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: accent,
                              fontFamily: 'Plus Jakarta Sans',
                              fontFamilyFallback: const ['NotoSansJP'],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '📝 ${AppStrings.t('as_title')}',
                style: AppTextStyles.headLG.copyWith(fontSize: 24),
              ),
              const SizedBox(height: 5),
              Text(
                AppStrings.t('as_summary')
                    .replaceAll('{done}', '$doneCount')
                    .replaceAll('{total}', '$totalCount'),
                style: TextStyle(
                  fontFamily: 'Plus Jakarta Sans',
                  fontFamilyFallback: const ['NotoSansJP'],
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 14),

              // Total progress bar
              Container(
                height: 8,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0x12FFFFFF) : AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.1)),
                ),
                clipBehavior: Clip.hardEdge,
                // Isolate the 600ms tween's per-frame paint from the header's
                // radial-gradient background so the whole header doesn't
                // repaint 60x/s while the bar animates.
                child: RepaintBoundary(
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: progressPct.clamp(0.0, 1.0)),
                    duration: const Duration(milliseconds: 600),
                    curve: Curves.easeOutExpo,
                    builder: (context, value, _) => FractionallySizedBox(
                      widthFactor: value,
                      alignment: Alignment.centerLeft,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: AppColors.gradientPrimary,
                          borderRadius: BorderRadius.circular(4),
                          boxShadow: [BoxShadow(color: AppColors.primaryMid.withValues(alpha: 0.6), blurRadius: 14)],
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 14),

              // Weekly progress graph
              _WeeklyProgressBar(completed: weekly.completed, total: weekly.total),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Weekly progress graph ───────────────────────────────────────────────────

class _WeeklyProgressBar extends StatelessWidget {
  final int completed;
  final int total;
  const _WeeklyProgressBar({required this.completed, required this.total});

  @override
  Widget build(BuildContext context) {
    final pct = total == 0 ? 0.0 : completed / total;
    final pctText = '${(pct * 100).round()}%';
    final isDark = AppColors.isDark;
    final labelColor = AppColors.isDark ? AppColors.primaryLight : AppColors.primaryIndigo;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.primaryMid.withValues(alpha: isDark ? 0.07 : 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primaryMid.withValues(alpha: isDark ? 0.18 : 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.bar_chart_rounded,
                    size: 13,
                    color: labelColor.withValues(alpha: 0.75),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    AppStrings.t('as_week_progress'),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: labelColor.withValues(alpha: 0.75),
                      fontFamily: 'Plus Jakarta Sans',
                      fontFamilyFallback: const ['NotoSansJP'],
                    ),
                  ),
                ],
              ),
              Text(
                '${AppStrings.t('as_progress_count').replaceAll('{done}', '$completed').replaceAll('{total}', '$total')}  $pctText',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: labelColor,
                  fontFamily: 'Plus Jakarta Sans',
                  fontFamilyFallback: const ['NotoSansJP'],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Container(
              height: 6,
              color: AppColors.primaryMid.withValues(alpha: isDark ? 0.15 : 0.12),
              // Isolate the tween from the header's radial-gradient decoration
              // so it repaints in its own layer during the 700ms animation.
              child: RepaintBoundary(
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: pct.clamp(0.0, 1.0)),
                  duration: const Duration(milliseconds: 700),
                  curve: Curves.easeOutExpo,
                  builder: (context, value, _) => FractionallySizedBox(
                    widthFactor: value,
                    alignment: Alignment.centerLeft,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: AppColors.gradientPrimary,
                        borderRadius: BorderRadius.circular(4),
                        boxShadow: [BoxShadow(color: AppColors.primaryMid.withValues(alpha: 0.6), blurRadius: 8)],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Calendar ────────────────────────────────────────────────────────────────

class _AssignmentCalendar extends StatelessWidget {
  final List<AssignmentModel> assignments;
  final DateTime focusedDay;
  final DateTime? selectedDay;
  final void Function(DateTime, DateTime) onDaySelected;
  final void Function(DateTime) onFocusedDayChanged;

  const _AssignmentCalendar({
    required this.assignments,
    required this.focusedDay,
    required this.selectedDay,
    required this.onDaySelected,
    required this.onFocusedDayChanged,
  });

  /// Groups [assignments] by due-day once so `eventLoader` below is an O(1)
  /// map lookup per visible cell instead of an O(n) scan per cell.
  Map<DateTime, List<AssignmentModel>> _groupByDueDay() {
    final byDay = <DateTime, List<AssignmentModel>>{};
    for (final a in assignments) {
      final key = DateTime(a.dueDate.year, a.dueDate.month, a.dueDate.day);
      byDay.putIfAbsent(key, () => []).add(a);
    }
    return byDay;
  }

  @override
  Widget build(BuildContext context) {
    final eventsByDay = _groupByDueDay();
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceVar,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: TableCalendar<AssignmentModel>(
        locale: 'ja_JP',
        firstDay: DateTime.now().subtract(const Duration(days: 365)),
        lastDay: DateTime.now().add(const Duration(days: 365)),
        focusedDay: focusedDay,
        selectedDayPredicate: (day) =>
            selectedDay != null && isSameDay(day, selectedDay!),
        onDaySelected: onDaySelected,
        onPageChanged: onFocusedDayChanged,
        eventLoader: (day) =>
            eventsByDay[DateTime(day.year, day.month, day.day)] ?? const [],
        calendarFormat: CalendarFormat.month,
        availableCalendarFormats: {CalendarFormat.month: AppStrings.t('as_month_view')},
        calendarStyle: CalendarStyle(
          outsideDaysVisible: false,
          defaultTextStyle: TextStyle(
            color: AppColors.textPrimary,
            fontFamily: 'Plus Jakarta Sans',
            fontSize: 13,
          ),
          weekendTextStyle: TextStyle(
            color: AppColors.textSecondary,
            fontFamily: 'Plus Jakarta Sans',
            fontSize: 13,
          ),
          outsideTextStyle: TextStyle(
            color: AppColors.textMuted,
            fontFamily: 'Plus Jakarta Sans',
            fontSize: 13,
          ),
          todayDecoration: BoxDecoration(
            color: AppColors.primaryMid.withValues(alpha: 0.3),
            shape: BoxShape.circle,
          ),
          todayTextStyle: const TextStyle(
            color: AppColors.primaryLight,
            fontFamily: 'Plus Jakarta Sans',
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
          selectedDecoration: const BoxDecoration(
            gradient: AppColors.gradientPrimary,
            shape: BoxShape.circle,
          ),
          selectedTextStyle: const TextStyle(
            color: Colors.white,
            fontFamily: 'Plus Jakarta Sans',
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
          markerDecoration: const BoxDecoration(
            color: AppColors.primaryMid,
            shape: BoxShape.circle,
          ),
          markerSize: 5,
          markersMaxCount: 3,
          cellMargin: const EdgeInsets.all(4),
        ),
        headerStyle: HeaderStyle(
          formatButtonVisible: false,
          titleCentered: true,
          titleTextStyle: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w700,
            fontFamily: 'Plus Jakarta Sans',
            fontFamilyFallback: const ['NotoSansJP'],
          ),
          leftChevronIcon: Icon(
            Icons.chevron_left_rounded,
            color: AppColors.textSecondary,
          ),
          rightChevronIcon: Icon(
            Icons.chevron_right_rounded,
            color: AppColors.textSecondary,
          ),
          headerPadding: const EdgeInsets.symmetric(vertical: 10),
        ),
        daysOfWeekStyle: DaysOfWeekStyle(
          weekdayStyle: TextStyle(
            color: AppColors.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            fontFamily: 'Plus Jakarta Sans',
          ),
          weekendStyle: TextStyle(
            color: AppColors.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            fontFamily: 'Plus Jakarta Sans',
          ),
        ),
      ),
    );
  }
}

// ─── Add button ──────────────────────────────────────────────────────────────

class _AddTaskButton extends StatelessWidget {
  final VoidCallback onTap;
  const _AddTaskButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = AppColors.isDark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: isDark
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.primary.withValues(alpha: 0.2), AppColors.primaryDark.withValues(alpha: 0.1)],
                )
              : AppColors.gradientAddTaskLight,
          borderRadius: BorderRadius.circular(isDark ? 20 : 18),
          border: isDark ? Border.all(color: AppColors.primary.withValues(alpha: 0.3)) : null,
          boxShadow: [
            BoxShadow(
              color: isDark ? AppColors.primary.withValues(alpha: 0.15) : const Color(0x5900B894),
              blurRadius: isDark ? 20 : 24,
              offset: isDark ? Offset.zero : const Offset(0, 6),
            ),
          ],
        ),
        child: Text(
          '＋ ${AppStrings.t('as_add_new')}',
          style: TextStyle(
            fontFamily: 'Plus Jakarta Sans',
            fontFamilyFallback: const ['NotoSansJP'],
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: isDark ? AppColors.accentText : Colors.white,
          ),
        ),
      ),
    );
  }
}
