import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/periods.dart';
import '../../../core/constants/subject_colors.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_helper.dart';
import '../../school/models/school.dart';
import '../../school/school_providers.dart';
import '../models/class_model.dart';
import '../providers/timetable_provider.dart';
import 'class_detail_sheet.dart';
import 'day_tab_row.dart';
import 'school_changes_list.dart';
import 'school_slot_card.dart';

int _minutes(Hm t) => t.$1 * 60 + t.$2;

/// Row index of the school period whose `[start, end)` contains the start of
/// the personal class's period, or -1.
///
/// UZ: `[start, end)` oralig'ida shaxsiy dars vaqtining boshlanishi joylashgan maktab darsi
/// qatorining indeksi, yoki -1.
int _rowOf(ClassModel c, List<SchoolPeriod> periods) {
  final start = kPeriodTimes[c.period]?.start;
  if (start == null) return -1;
  final m = _minutes(start);
  return periods
      .indexWhere((p) => m >= _minutes(p.start) && m < _minutes(p.end));
}

/// Week view for wide screens: school periods as rows, 月-金 as columns.
/// Each cell holds the school lesson plus any personal class that starts
/// inside the period; personal classes that fit no row are listed below.
///
/// UZ: Keng ekranlar uchun hafta ko'rinishi: maktab darslari qatorlar sifatida, 月-金 ustunlar
/// sifatida. Har bir katak maktab darsi va ushbu davr ichida boshlanadigan shaxsiy darslarni
/// saqlaydi; hech qaysi qatorga sig'magan shaxsiy darslar pastda ko'rsatiladi.
class SchoolWeekGrid extends ConsumerWidget {
  final DateTime weekStart;
  const SchoolWeekGrid({super.key, required this.weekStart});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(schoolInfoProvider).valueOrNull;
    if (info == null) return const SizedBox.shrink();
    final week = ref.watch(schoolWeekProvider(weekStart)).valueOrNull ??
        const <String, SchoolDay>{};
    final classes =
        ref.watch(timetableStreamProvider).valueOrNull ?? const <ClassModel>[];
    final periods = info.periods;

    final cellClasses = <(int, int), List<ClassModel>>{};
    final unplaced = <ClassModel>[];
    for (final c in classes) {
      final col = kWeekdayKanji.indexOf(c.dayOfWeek);
      final row = _rowOf(c, periods);
      if (col == -1) continue;
      if (row == -1) {
        unplaced.add(c);
      } else {
        cellClasses.putIfAbsent((row, col), () => []).add(c);
      }
    }
    unplaced.sort((a, b) {
      final d = kWeekdayKanji.indexOf(a.dayOfWeek) -
          kWeekdayKanji.indexOf(b.dayOfWeek);
      return d != 0 ? d : a.period.compareTo(b.period);
    });

    final dates = [
      for (var i = 0; i < 5; i++)
        DateTime(weekStart.year, weekStart.month, weekStart.day + i)
    ];

    // Narrower time gutter so the five day columns keep room at 600-720dp.
    // UZ: 600-720dp kenglikda besh kunlik ustunlar uchun joy yetarli bo'lishi maqsadida torroq vaqt maydoni.
    final gutterWidth = MediaQuery.sizeOf(context).width < 720 ? 56.0 : 76.0;
    Widget gutter(Widget child) => SizedBox(width: gutterWidth, child: child);

    // Slots whose period key isn't a grid row (e.g. a 休講 with an unknown
    // key) must not vanish; they are listed below the grid.
    // UZ: Period kaliti jadval qatori bo'lmagan slotlar (masalan, noma'lum kalitli 休講)
    // yo'qolib ketmasligi kerak; ular setkaning pastida ko'rsatiladi.
    final rowKeys = {for (final p in periods) p.key};
    final orphans = <(int, SchoolSlot)>[
      for (var col = 0; col < 5; col++)
        for (final slot
            in week[DateHelper.dayKey(dates[col])]?.slots ?? const <SchoolSlot>[])
          if (!rowKeys.contains(slot.period)) (col, slot)
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              gutter(const SizedBox.shrink()),
              for (var col = 0; col < 5; col++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: Column(
                      children: [
                        Text(DayTabRow.days[col],
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textPrimary)),
                        Text('${dates[col].month}/${dates[col].day}',
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: DateHelper.isToday(dates[col])
                                    ? FontWeight.w800
                                    : FontWeight.w500,
                                color: DateHelper.isToday(dates[col])
                                    ? AppColors.accentText
                                    : AppColors.textSecondary)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          for (var row = 0; row < periods.length; row++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    gutter(Padding(
                      padding: const EdgeInsets.only(right: 6, top: 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(periods[row].label,
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.accentText)),
                          Text(schoolPeriodTimes(periods[row]),
                              style: TextStyle(
                                  fontSize: 10, color: AppColors.textSecondary)),
                        ],
                      ),
                    )),
                    for (var col = 0; col < 5; col++)
                      Expanded(
                        child: Padding(
                          key: ValueKey('school-cell-$row-$col'),
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          child: _Cell(
                            slots: [
                              for (final s
                                  in week[DateHelper.dayKey(dates[col])]
                                          ?.slots ??
                                      const <SchoolSlot>[])
                                if (s.period == periods[row].key) s
                            ],
                            period: periods[row],
                            personal: cellClasses[(row, col)] ?? const [],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          if (orphans.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final (col, slot) in orphans)
                  SizedBox(
                    width: 180,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${DayTabRow.days[col]} · ${slot.period}',
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: AppColors.accentText)),
                        const SizedBox(height: 2),
                        SchoolSlotCard(slot: slot, period: null, compact: true),
                      ],
                    ),
                  ),
              ],
            ),
          ],
          if (unplaced.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(AppStrings.t('school_label_personal'),
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final c in unplaced)
                  _PersonalChip(c, label: _unplacedLabel(c))
              ],
            ),
          ],
          const SchoolLastSyncLine(padding: EdgeInsets.only(top: 14)),
        ],
      ),
    );
  }

  static String _unplacedLabel(ClassModel c) =>
      '${weekdayLabel(c.dayOfWeek)} ${AppStrings.t('tt_period', {
            'n': c.period
          })} ${c.subject}';
}

class _Cell extends StatelessWidget {
  final List<SchoolSlot> slots;
  final SchoolPeriod period;
  final List<ClassModel> personal;
  const _Cell(
      {required this.slots, required this.period, required this.personal});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final s in slots)
            _SchoolSlotGridItem(slot: s, period: period),
          for (final c in personal)
            _PersonalChip(c, label: c.subject, marked: true),
        ],
      ),
    );
  }
}

class _SchoolSlotGridItem extends StatelessWidget {
  final SchoolSlot slot;
  final SchoolPeriod period;
  const _SchoolSlotGridItem({required this.slot, required this.period});

  @override
  Widget build(BuildContext context) {
    final elective = slot.status == SchoolSlotStatus.elective;
    final subject = elective
        ? AppStrings.t('school_slot_elective', {'label': slot.subject})
        : slot.subject;
    final accent = schoolSlotAccent(slot);
    final badge = schoolSlotBadge(slot);

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      constraints: const BoxConstraints(minHeight: 56),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.cardStroke),
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 3, color: accent),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      subject,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                        decoration: slot.status == SchoolSlotStatus.cancelled
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                    if (slot.room.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        slot.room,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                    if (badge != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            badge,
                            style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: accent),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A personal class in the grid; tapping opens its detail sheet.
///
/// UZ: Jadvaldagi shaxsiy dars; bosilganda batafsil ma'lumot varaqasini ochadi.
class _PersonalChip extends ConsumerWidget {
  final ClassModel classModel;
  final String label;
  final bool marked;
  const _PersonalChip(this.classModel,
      {required this.label, this.marked = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = SubjectColors.of(classModel.subject);
    return GestureDetector(
      onTap: () => showClassDetailSheet(context, ref, classModel),
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        constraints: BoxConstraints(minHeight: marked ? 56 : 0),
        decoration: BoxDecoration(
          color: style.fill,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: style.dot.withValues(alpha: 0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                if (marked) ...[
                  Text(AppStrings.t('school_label_personal'),
                      style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: style.text)),
                  const SizedBox(width: 4),
                ],
                Expanded(
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: style.text)),
                ),
              ],
            ),
            if (classModel.room.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                classModel.room,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: style.text.withValues(alpha: 0.85),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
