import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:table_calendar/table_calendar.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_helper.dart';
import '../../../core/utils/responsive.dart';
import '../../../shared/widgets/entrance.dart';
import '../../../shared/widgets/glass_panel.dart';
import '../../../shared/widgets/pressable.dart';
import '../../home/widgets/assignment_row_item.dart';
import '../../home/widgets/home_ambient_glow.dart';
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
    final weekly = ref.watch(weeklyProgressProvider);

    final filtered = ref.watch(filteredAssignmentsProvider);

    // Calendar mode hides the filter chips, so it ignores the status filter
    // (all assignments); with a selected day it shows only that day's.
    final displayAssignments = !_calendarMode
        ? filtered
        : (_selectedDay != null
            ? all.where((a) => _sameDay(a.dueDate, _selectedDay!)).toList()
            : all);

    final overdue = all
        .where((a) => a.status != AssignmentStatus.completed && DateHelper.daysUntil(a.dueDate) < 0)
        .length;

    return Scaffold(
      backgroundColor: AppColors.background,
      floatingActionButton: Padding(
        padding: EdgeInsets.only(bottom: context.isTablet ? 0 : 84),
        child: Pressable(
          child: FloatingActionButton.extended(
            heroTag: 'assignments-add',
            onPressed: () => showAddEditAssignmentSheet(context, ref),
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.onPrimary,
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            icon: const Icon(Icons.add_rounded),
            label: Text(AppStrings.t('home_add_assignment'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          ),
        ),
      ),
      body: Stack(
        children: [
          const Positioned.fill(child: HomeAmbientGlow()),
          SafeArea(
            bottom: false,
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Entrance(
                    index: 0,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(AppStrings.t('nav_assignments'),
                                style: TextStyle(fontSize: 24, height: 1.4, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                          ),
                          Tooltip(
                            message: AppStrings.t(_calendarMode ? 'as_view_list' : 'as_view_calendar'),
                            child: Pressable(
                              child: InkWell(
                                customBorder: const CircleBorder(),
                                onTap: () => setState(() {
                                  _calendarMode = !_calendarMode;
                                  if (!_calendarMode) _selectedDay = null;
                                }),
                                child: Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    color: AppColors.cardSurface,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: AppColors.cardStroke),
                                  ),
                                  child: Icon(_calendarMode ? Icons.view_list_rounded : Icons.calendar_month_outlined,
                                      size: 20, color: AppColors.textPrimary),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (!_calendarMode)
                  SliverToBoxAdapter(
                    child: Entrance(
                      index: 1,
                      child: _ProgressCard(weekly: weekly, overdue: overdue),
                    ),
                  ),
                if (_calendarMode)
                  SliverToBoxAdapter(
                    child: Entrance(
                      index: 1,
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
                  ),
                if (!_calendarMode)
                  const SliverToBoxAdapter(
                    child: Entrance(
                      index: 2,
                      child: FilterChipsRow(),
                    ),
                  ),
                if (_calendarMode && _selectedDay != null)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                      child: Text(
                        AppStrings.t('as_day_title')
                            .replaceAll('{month}', '${_selectedDay!.month}')
                            .replaceAll('{day}', '${_selectedDay!.day}')
                            .replaceAll('{n}', '${displayAssignments.length}'),
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textSecondary),
                      ),
                    ),
                  ),
                if (displayAssignments.isEmpty)
                  SliverToBoxAdapter(
                    child: Entrance(
                      index: 3,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 40),
                        child: Center(
                          child: Text(
                            _calendarMode && _selectedDay != null
                                ? AppStrings.t('as_empty_day')
                                : AppStrings.t('as_empty'),
                            style: TextStyle(fontSize: 13, color: AppColors.textMuted),
                          ),
                        ),
                      ),
                    ),
                  )
                else if (_calendarMode)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                    sliver: SliverList.separated(
                      itemCount: displayAssignments.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) => Entrance(
                        key: ValueKey(displayAssignments[i].id),
                        index: 3,
                        child: AssignmentCard(
                          assignment: displayAssignments[i],
                        ),
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                    sliver: SliverList.list(children: [
                      Entrance(
                        index: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: _dueGroups(displayAssignments),
                        ),
                      ),
                    ]),
                  ),
                // Room for the floating 課題を追加 button and bottom navigation bar.
                SliverToBoxAdapter(child: SizedBox(height: context.isTablet ? 96 : 130)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Redesign grouping by due date: 期限切れ / 今日・明日 / 今週 / 来週以降,
  /// then 完了 last (a finished assignment is never overdue).
  List<Widget> _dueGroups(List<AssignmentModel> list) {
    int bucket(AssignmentModel a) {
      if (a.status == AssignmentStatus.completed) return 4;
      final d = DateHelper.daysUntil(a.dueDate);
      if (d < 0) return 0;
      if (d <= 1) return 1;
      if (d <= 6) return 2;
      return 3;
    }

    final groups = [
      (AppStrings.t('due_overdue'), AppColors.danger),
      (AppStrings.t('as_group_soon'), AppColors.warning),
      (AppStrings.t('as_group_week'), AppColors.textSecondary),
      (AppStrings.t('as_group_later'), AppColors.textSecondary),
      (AppStrings.t('status_completed'), AppColors.textMuted),
    ];
    return [
      for (var g = 0; g < groups.length; g++)
        if (list.where((a) => bucket(a) == g).toList() case final items when items.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
            child: Text(groups[g].$1,
                style: TextStyle(fontSize: 13, height: 1.4, fontWeight: FontWeight.w700, color: groups[g].$2)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: AppColors.cardSurface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.cardStroke),
            ),
            child: Column(
              children: [
                for (var i = 0; i < items.length; i++)
                  AssignmentRowItem(key: ValueKey(items[i].id), assignment: items[i], showDivider: i < items.length - 1),
              ],
            ),
          ),
        ],
    ];
  }
}

/// 今週の進捗: done / total this week, a bar, and an overdue nudge.
class _ProgressCard extends StatelessWidget {
  final ({int completed, int total}) weekly;
  final int overdue;
  const _ProgressCard({required this.weekly, required this.overdue});

  @override
  Widget build(BuildContext context) {
    final pct = weekly.total == 0 ? 0.0 : weekly.completed / weekly.total;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
      child: KeyedSubtree(
        key: ValueKey(AppColors.brightness),
        child: GlassPanel(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          radius: 24,
          tint: AppColors.glassFill,
          borderColor: AppColors.glassBorder,
          shadows: AppColors.glassShadow,
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Expanded(
                  child: Text(AppStrings.t('as_week_progress'),
                      style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                ),
                Text('${weekly.completed}',
                    style: TextStyle(
                        fontFamily: 'Space Grotesk',
                        fontFamilyFallback: const ['Plus Jakarta Sans'],
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
                Text(' / ${weekly.total}', style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: pct,
                minHeight: 8,
                backgroundColor: AppColors.surfaceVar,
                color: AppColors.primary,
              ),
            ),
            if (overdue > 0) ...[
              const SizedBox(height: 10),
              Text(AppStrings.t('as_overdue_hint', {'n': overdue}),
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.danger)),
            ],
          ],
        ),
      ),
    ));
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
        locale: AppStrings.currentLocale,
        firstDay: DateTime.now().subtract(const Duration(days: 365)),
        lastDay: DateTime.now().add(const Duration(days: 365 * 2)),
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
          todayTextStyle: TextStyle(
            color: AppColors.accentText,
            fontFamily: 'Plus Jakarta Sans',
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
          selectedDecoration: const BoxDecoration(
            gradient: AppColors.gradientPrimary,
            shape: BoxShape.circle,
          ),
          selectedTextStyle: const TextStyle(
            color: AppColors.onPrimary,
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
