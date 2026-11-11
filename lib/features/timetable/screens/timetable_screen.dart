import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/providers/clock_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_helper.dart';
import '../../../core/utils/responsive.dart';
import '../../../shared/widgets/entrance.dart';
import '../../../shared/widgets/glass_panel.dart';
import '../../../shared/widgets/pressable.dart';
import '../../home/widgets/home_ambient_glow.dart';
import '../../school/models/school.dart';
import '../../school/school_providers.dart';
import '../providers/timetable_provider.dart';
import '../widgets/add_edit_class_sheet.dart';
import '../widgets/day_tab_row.dart';
import '../widgets/schedule_timeline.dart';
import '../widgets/school_changes_list.dart';
import '../widgets/school_slot_card.dart';
import '../widgets/school_week_grid.dart';

/// Schedule tab — a day-tab row (月火水木金) + a vertical timeline of that
/// day's classes, matching the dark-neon design reference.
class TimetableScreen extends ConsumerStatefulWidget {
  const TimetableScreen({super.key});

  @override
  ConsumerState<TimetableScreen> createState() => _TimetableScreenState();
}

/// Local-midnight Monday of [d]'s week (calendar arithmetic, so a DST change
/// can't push the result onto the neighbouring day).
DateTime _mondayOf(DateTime d) => DateTime(d.year, d.month, d.day - (d.weekday - 1));

/// Day indexes (0 = Mon) of [weekStart]'s week whose school lessons carry a
/// cancellation or a teacher change.
Set<int> _alertDays(WidgetRef ref, DateTime weekStart) {
  if (ref.watch(schoolClassProvider) == null) return const {};
  final week = ref.watch(schoolWeekProvider(weekStart)).valueOrNull ?? const {};
  return {
    for (var i = 0; i < 5; i++)
      if (week[DateHelper.dayKey(DateTime(weekStart.year, weekStart.month, weekStart.day + i))]
              ?.slots
              .any((s) => schoolSlotBadge(s) != null && s.status != SchoolSlotStatus.event) ??
          false)
        i,
  };
}

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
    final classCount = ref.watch(timetableStreamProvider).valueOrNull?.length ?? 0;
    // Watching the clock re-derives the displayed week after midnight.
    final today = ref.watch(todayProvider).valueOrNull ?? DateTime.now();
    final monday = _mondayOf(today);
    final weekStart = DateTime(monday.year, monday.month, monday.day + 7 * _weekOffset);
    // Gate on school data + width only (not on the week having loaded), so
    // prev/next week doesn't flip between grid and day tabs while loading.
    final showGrid = context.isTablet && ref.watch(schoolClassProvider) != null;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          const Positioned.fill(child: HomeAmbientGlow()),
          SafeArea(
            child: Column(
              children: [
                Entrance(
                  index: 0,
                  child: _Header(classCount: classCount),
                ),
                Entrance(
                  index: 1,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                    child: KeyedSubtree(
                      key: ValueKey(AppColors.brightness),
                      child: GlassPanel(
                        padding: const EdgeInsets.all(14),
                        radius: 24,
                        tint: AppColors.glassFill,
                        borderColor: AppColors.glassBorder,
                        shadows: AppColors.glassShadow,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _WeekNavigator(
                              weekStart: weekStart,
                              isCurrentWeek: _weekOffset == 0,
                              onPrevious: () => setState(() => _weekOffset -= 1),
                              onNext: () => setState(() => _weekOffset += 1),
                              onResetToday: () => setState(() => _weekOffset = 0),
                            ),
                            if (!showGrid) ...[
                              const SizedBox(height: 10),
                              DayTabRow(
                                selectedDay: _selectedDay,
                                weekStart: weekStart,
                                alertDays: _alertDays(ref, weekStart),
                                onSelect: (index) => setState(() => _selectedDay = index),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                if (showGrid)
                  Expanded(
                    child: Entrance(
                      index: 2,
                      child: _SchoolWeekBody(weekStart: weekStart),
                    ),
                  )
                else ...[
                  Expanded(
                    child: Entrance(
                      index: 2,
                      child: ScheduleTimeline(selectedDay: _selectedDay, weekStart: weekStart),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Week grid, plus the recent-changes feed in a side column on desktop widths.
class _SchoolWeekBody extends StatelessWidget {
  final DateTime weekStart;
  const _SchoolWeekBody({required this.weekStart});

  @override
  Widget build(BuildContext context) {
    final grid = SchoolWeekGrid(weekStart: weekStart);
    if (context.screenWidth < Breakpoints.expanded) return grid;
    // stretch: a centered Row would float the short grid mid-screen.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: grid),
        Container(
          width: 320,
          decoration: BoxDecoration(border: Border(left: BorderSide(color: AppColors.dividerSubtle))),
          child: const SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(16, 14, 16, 24),
            child: SchoolChangesList(compact: true),
          ),
        ),
      ],
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
    final range = '${weekStart.month}/${weekStart.day} – ${weekEnd.month}/${weekEnd.day}';
    return Row(
      children: [
        _RoundButton(icon: Icons.chevron_left_rounded, tooltip: AppStrings.t('teacher_prev_week'), onTap: onPrevious),
        Expanded(
          child: Pressable(
            child: InkWell(
              onTap: isCurrentWeek ? null : onResetToday,
              borderRadius: BorderRadius.circular(12),
              child: Column(
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // On another week the label is a "back to today" link.
                      if (!isCurrentWeek) ...[
                        Icon(Icons.today_rounded, size: 16, color: AppColors.accentText),
                        const SizedBox(width: 4),
                      ],
                      Text(
                        AppStrings.t(isCurrentWeek ? 'tt_this_week' : 'teacher_today'),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: isCurrentWeek ? AppColors.textPrimary : AppColors.accentText,
                        ),
                      ),
                    ],
                  ),
                  Text(range, style: TextStyle(fontSize: 12, height: 1.5, color: AppColors.textSecondary)),
                ],
              ),
            ),
          ),
        ),
        _RoundButton(icon: Icons.chevron_right_rounded, tooltip: AppStrings.t('teacher_next_week'), onTap: onNext),
      ],
    );
  }
}

class _RoundButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  const _RoundButton({required this.icon, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: Pressable(
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.statGlassFill,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.statGlassBorder),
              ),
              child: Icon(icon, size: 22, color: AppColors.textPrimary),
            ),
          ),
        ),
      );
}

/// Plain title row like the other tabs: 時間割 (or the school name under it),
/// the teacher shortcut, and a round + to add a personal class.
class _Header extends ConsumerWidget {
  final int classCount;
  const _Header({required this.classCount});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final schoolName = ref.watch(schoolClassProvider) == null
        ? null
        : ref.watch(schoolInfoProvider).valueOrNull?.name;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(AppStrings.t('nav_timetable'),
                    style: TextStyle(fontSize: 24, height: 1.4, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                Text(
                  // With school data the personal-class count ("0 コマ")
                  // contradicts the lessons on screen, so name the school.
                  schoolName ?? AppStrings.t('tt_count').replaceAll('{n}', '$classCount'),
                  style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                ),
                if (ref.watch(schoolRoleProvider).teacher) ...[
                  const SizedBox(height: 8),
                  ActionChip(
                    avatar: const Icon(Icons.co_present_outlined, size: 18, color: AppColors.warning),
                    label: Text(AppStrings.t('teacher_title')),
                    onPressed: () => context.push('/teacher'),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Tooltip(
            message: AppStrings.t('cls_add_title'),
            child: Pressable(
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => showAddEditClassSheet(context, ref),
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                  child: const Icon(Icons.add_rounded, color: AppColors.onPrimary, size: 24),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
