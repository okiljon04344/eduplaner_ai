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
import '../../school/widgets/school_load_error_banner.dart';
import '../providers/timetable_provider.dart';
import '../widgets/add_edit_class_sheet.dart';
import '../widgets/day_tab_row.dart';
import '../widgets/schedule_timeline.dart';
import '../widgets/school_changes_list.dart';
import '../widgets/school_slot_card.dart';
import '../widgets/school_week_grid.dart';

/// Schedule tab — a day-tab row (月火水木金) + a vertical timeline of that
/// day's classes, matching the dark-neon design reference.
///
/// UZ: Dars jadvali tabi — kunlar qatori (月火水木金) + to'q-neon dizayn namunasiga mos keladigan
/// o'sha kungi darslarning vertikal vaqt shkalasi.
class TimetableScreen extends ConsumerStatefulWidget {
  const TimetableScreen({super.key});

  @override
  ConsumerState<TimetableScreen> createState() => _TimetableScreenState();
}

/// Local-midnight Monday of [d]'s week (calendar arithmetic, so a DST change
/// can't push the result onto the neighbouring day).
///
/// UZ: [d] haftasining mahalliy yarim kechadagi dushanbasi (taqvim arifmetikasi, shuning uchun
/// DST o'zgarishi natijani qo'shni kunga surib yubora olmaydi).
DateTime _mondayOf(DateTime d) => DateTime(d.year, d.month, d.day - (d.weekday - 1));

/// Day indexes (0 = Mon) of [weekStart]'s week whose school lessons carry a
/// cancellation or a teacher change.
///
/// UZ: Maktab darslarida bekor qilish yoki o'qituvchi o'zgarishi mavjud bo'lgan
/// [weekStart] haftasining kun indekslari (0 = Dush).
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
    // UZ: Soatni kuzatish yarim kechadan keyin ko'rsatilgan haftani qayta hisoblab chiqaradi.
    final today = ref.watch(todayProvider).valueOrNull ?? DateTime.now();
    final monday = _mondayOf(today);
    final weekStart = DateTime(monday.year, monday.month, monday.day + 7 * _weekOffset);
    // Gate on school data + width only (not on the week having loaded), so
    // prev/next week doesn't flip between grid and day tabs while loading.
    // UZ: Faqat maktab ma'lumotlari + kenglik bo'yicha cheklash (hafta yuklanganligiga emas), shunda
    // oldingi/keyingi hafta yuklanayotganda jadval (grid) va kun tablari o'rtasida o'zgarib ketmaydi.
    final showGrid = context.isTablet && ref.watch(schoolClassProvider) != null;
    final isSchoolLinked = ref.watch(schoolClassProvider) != null;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          const Positioned.fill(child: HomeAmbientGlow()),
          ResponsiveBody(
            maxWidth: 900,
            child: SafeArea(
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
                if (isSchoolLinked)
                  const SchoolLoadErrorBanner(margin: EdgeInsets.fromLTRB(20, 0, 20, 12)),
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
        ),
      ],
    ),
  );
  }
}

/// Week grid, plus the recent-changes feed in a side column on desktop widths.
///
/// UZ: Hafta katakchasi (grid), shuningdek, desktop kengliklarida yon ustunda so'nggi o'zgarishlar tasmasi.
class _SchoolWeekBody extends StatelessWidget {
  final DateTime weekStart;
  const _SchoolWeekBody({required this.weekStart});

  @override
  Widget build(BuildContext context) {
    final grid = SchoolWeekGrid(weekStart: weekStart);
    if (context.screenWidth < Breakpoints.expanded) return grid;
    // stretch: a centered Row would float the short grid mid-screen.
    // Padding 20 on the right ensures the sidebar aligns with the glass header panel above.
    // UZ: stretch: markazlashtirilgan Row qisqa jadvalni ekranning o'rtasida suzdirib qo'yardi.
    // O'ng tomondagi 20 li padding yon panelning yuqoridagi shisha sarlavha paneli bilan tekislanishini ta'minlaydi.
    return Padding(
      padding: const EdgeInsets.only(right: 20),
      child: Row(
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
                      // UZ: Boshqa haftada bu yorliq "bugungi kunga qaytish" havolasidir.
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
///
/// UZ: Boshqa tablar kabi oddiy sarlavha qatori: 時間割 (yoki uning ostida maktab nomi),
/// o'qituvchi yorlig'i va shaxsiy dars qo'shish uchun dumaloq + tugmasi.
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
                  // UZ: Maktab ma'lumotlari bilan shaxsiy darslar soni ("0 コマ")
                  // ekrandagi darslarga zid keladi, shuning uchun maktab nomini ko'rsating.
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
          // A linked student's timetable comes from the school file: adding
          // classes by hand would mix made-up lessons into the official one.
          // UZ: Bog'langan talabaning dars jadvali maktab faylidan keladi: darslarni
          // qo'lda qo'shish rasmiy dars jadvaliga to'qima darslarni aralashtirib yuboradi.
          if (schoolName == null) const SizedBox(width: 12),
          if (schoolName == null) Tooltip(
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
