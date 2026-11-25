import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/periods.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/providers/clock_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_helper.dart';
import '../../../core/utils/responsive.dart';
import '../../school/models/school.dart';
import '../../school/school_providers.dart';
import '../models/class_model.dart';
import '../providers/timetable_provider.dart';
import 'school_changes_list.dart';
import 'school_slot_card.dart';
import 'timeline_class_card.dart';

/// Vertical timeline of classes for the currently selected day, with a
/// fade+slide entrance whenever the day changes and a friendly empty state.
///
/// [weekStart] is the Monday of the displayed week; together with
/// [selectedDay] it gives each card the exact date it is shown for.
///
/// When the user's school timetable is synced, that day's school lessons come
/// first (in the school's period order), followed by the personal classes,
/// each tagged 自分. Without school data it shows personal classes only.
///
/// UZ: Kun o'zgarganda fade+slide kirishi va qulay bo'sh holatga ega, joriy tanlangan
/// kun uchun darslarning vertikal vaqt shkalasi (timeline).
///
/// [weekStart] — ko'rsatilgan haftaning dushanbasi; [selectedDay] bilan birgalikda u har bir
/// kartaga ko'rsatilayotgan aniq sanani beradi.
///
/// Foydalanuvchining maktab dars jadvali sinxronlanganda, o'sha kungi maktab darslari birinchi
/// bo'lib keladi (maktabning dars soatlari tartibida), undan keyin esa har biri 自分 deb belgilangan
/// shaxsiy darslar keladi. Maktab ma'lumotlarisiz faqat shaxsiy darslarni ko'rsatadi.
class ScheduleTimeline extends ConsumerWidget {
  final int selectedDay;
  final DateTime weekStart;
  const ScheduleTimeline({super.key, required this.selectedDay, required this.weekStart});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final classes = ref.watch(timetableStreamProvider).valueOrNull ?? const <ClassModel>[];
    // Compare against the canonical (always-kanji) storage key, not the
    // localized display label from DayTabRow.days — those diverge for any
    // non-Japanese locale and previously made every day render empty.
    // UZ: DayTabRow.days'dagi mahalliylashtirilgan ko'rsatish yorlig'iga emas, kanonik (doim kanji)
    // saqlash kalitiga qarab solishtiring — ular har qanday yaponcha bo'lmagan lokalda farqlanadi va
    // ilgari har bir kunni bo'sh ko'rsatilishiga olib kelgan.
    final day = kWeekdayKanji[selectedDay];
    final date = DateTime(weekStart.year, weekStart.month, weekStart.day + selectedDay);
    final dayClasses = classes.where((c) => c.dayOfWeek == day).toList()
      ..sort((a, b) => a.period.compareTo(b.period));

    // Loading/error: no school lessons yet, keep showing the personal list.
    // UZ: Yuklanmoqda/xatolik: hali maktab darslari yo'q, shaxsiy ro'yxatni ko'rsatishda davom eting.
    final info = ref.watch(schoolInfoProvider).valueOrNull;
    final hasSchool = ref.watch(schoolClassProvider) != null;
    final week = hasSchool ? ref.watch(schoolWeekProvider(weekStart)).valueOrNull : null;
    final schoolDay = week?[DateHelper.dayKey(date)];
    final periods = info?.periods ?? const <SchoolPeriod>[];
    int order(SchoolSlot s) {
      final i = periods.indexWhere((p) => p.key == s.period);
      return i == -1 ? periods.length : i;
    }

    // List.sort isn't stable; the index tiebreak keeps same-period slots in
    // their sheet order.
    // UZ: List.sort barqaror emas; indeksli tenglikni yechish bir xil davrdagi slotlarni
    // ularning varaqdagi tartibida saqlaydi.
    final indexed = [...?schoolDay?.slots].indexed.toList()
      ..sort((a, b) {
        final c = order(a.$2).compareTo(order(b.$2));
        return c != 0 ? c : a.$1.compareTo(b.$1);
      });
    final slots = [for (final (_, s) in indexed) s];
    final tagPersonal = slots.isNotEmpty;
    final now = ref.watch(minuteTickProvider).valueOrNull ?? DateTime.now();
    DateTime at(Hm t) => DateTime(date.year, date.month, date.day, t.$1, t.$2);

    final rows = <Widget>[];
    if (hasSchool && periods.isNotEmpty) {
      // One row per school period: the lesson, or a dashed 空きコマ.
      // UZ: Har bir maktab dars soati uchun bitta qator: dars yoki chiziqchali 空きコマ.
      for (var i = 0; i < periods.length; i++) {
        final p = periods[i];
        final slot = slots.where((s) => s.period == p.key).firstOrNull;
        final start = at(p.start), end = at(p.end);
        rows.add(_TimeRow(
          label: p.label,
          time: formatHm(p.start),
          past: !now.isBefore(end),
          live: !now.isBefore(start) && now.isBefore(end) && slot?.status != SchoolSlotStatus.cancelled,
          child: slot == null
              ? const _FreeSlot()
              : _LessonTile(
                  slot: slot,
                  live: !now.isBefore(start) && now.isBefore(end) && slot.status != SchoolSlotStatus.cancelled,
                  minutesLeft: end.difference(now).inMinutes + 1,
                ),
        ));
        // A gap of 30+ minutes before the next period is the lunch break.
        // UZ: Keyingi dars soatigacha 30+ daqiqalik tanaffus tushlik tanaffusidir.
        if (i < periods.length - 1) {
          final next = at(periods[i + 1].start);
          if (next.difference(end).inMinutes >= 30) {
            rows.add(_BreakLine(text: AppStrings.t('tt_lunch', {'time': '${formatHm(p.end)}–${formatHm(periods[i + 1].start)}'})));
          }
        }
      }
    } else {
      // Slots whose period key is unknown still show, after the periods.
      // UZ: Dars soati kaliti noma'lum bo'lgan slotlar dars soatlaridan keyin ham ko'rsatiladi.
      for (final s in slots) {
        rows.add(SchoolSlotCard(slot: s, period: periods.where((p) => p.key == s.period).firstOrNull));
      }
    }
    for (final c in dayClasses) {
      final t = periodTimeLabels(c.period);
      final start = periodStartOn(date, c.period);
      final end = periodEndOn(date, c.period);
      final isLive = start != null && end != null && !now.isBefore(start) && now.isBefore(end) && c.status != ClassStatus.cancelled;
      rows.add(_TimeRow(
        label: AppStrings.t('tt_period', {'n': c.period}),
        time: t.start,
        past: end != null && !now.isBefore(end),
        live: isLive,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (tagPersonal)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(AppStrings.t('school_label_personal'),
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.accentText)),
              ),
            TimelineClassCard(classModel: c, date: date, isLive: isLive),
          ],
        ),
      ));
    }

    final body = (dayClasses.isEmpty && slots.isEmpty && !(hasSchool && periods.isNotEmpty))
        ? _EmptyDay(key: ValueKey('empty-$selectedDay'))
        : ListView(
            key: ValueKey('list-$selectedDay'),
            padding: EdgeInsets.fromLTRB(20, 4, 20, context.isTablet ? 24 : 110),
            children: rows,
          );

    final switcher = AnimatedSwitcher(
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
      child: body,
    );
    if (!hasSchool || info?.lastSyncAt == null) return switcher;
    return Column(
      children: [
        Expanded(child: switcher),
        SchoolLastSyncLine(padding: EdgeInsets.only(bottom: context.isTablet ? 10 : 96)),
      ],
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
            Icon(Icons.wb_sunny_outlined, size: 40, color: AppColors.textMuted),
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

/// Redesign timeline row: period label + start time in a 52px column, the
/// lesson card beside it. Finished periods fade to 60%.
///
/// UZ: Qayta dizayn qilingan vaqt shkalasi qatori: 52px ustunda dars soati yorlig'i + boshlanish vaqti,
/// uning yonida dars kartasi. Tugagan dars soatlari 60% ga xiralashadi.
class _TimeRow extends StatelessWidget {
  final String label, time;
  final bool past, live;
  final Widget child;
  const _TimeRow({required this.label, required this.time, required this.past, required this.live, required this.child});

  @override
  Widget build(BuildContext context) => Opacity(
        opacity: past ? 0.6 : 1,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 52,
                child: Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label,
                          style: TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w700, color: live ? AppColors.accentText : AppColors.textPrimary)),
                      Text(time, style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: child),
            ],
          ),
        ),
      );
}

/// One school lesson in the day view; the live one is tinted with 授業中.
///
/// UZ: Kun ko'rinishidagi bitta maktab darsi; jonli dars 授業中 bilan tuslanadi.
class _LessonTile extends StatelessWidget {
  final SchoolSlot slot;
  final bool live;
  final int minutesLeft;
  const _LessonTile({required this.slot, required this.live, required this.minutesLeft});

  @override
  Widget build(BuildContext context) {
    final badge = schoolSlotBadge(slot);
    final accent = schoolSlotAccent(slot);
    final cancelled = slot.status == SchoolSlotStatus.cancelled;
    final detail = [
      if (slot.room.isNotEmpty) slot.room,
      if (slot.teacher.isNotEmpty) slot.teacher,
      if (live) AppStrings.t('home_now_remaining', {'n': minutesLeft}),
      if (slot.note.isNotEmpty) slot.note,
    ].join(' · ');
    // A uniform border keeps the rounded corners legal; the 4px subject bar
    // is a child clipped by the same radius.
    // UZ: Bir xil chegara burchaklarning to'g'ri yumaloqlanishini ta'minlaydi; 4px fan paneli
    // xuddi shu radius bilan qirqilgan bola (child) elementdir.
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: live ? AppColors.nowGlow : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            color: live ? AppColors.primary.withValues(alpha: AppColors.isDark ? 0.14 : 0.12) : AppColors.cardSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: live ? AppColors.primary : AppColors.cardStroke),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              // 掲示板 filtered to this lesson's subject.
              // UZ: Ushbu dars faniga filtrlangan 掲示板.
              onTap: slot.subject.isEmpty
                  ? null
                  : () => context.push(Uri(path: '/board', queryParameters: {'subject': slot.subject}).toString()),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!live) Container(width: 4, color: accent),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    slot.status == SchoolSlotStatus.elective
                        ? AppStrings.t('school_slot_elective', {'label': slot.subject})
                        : slot.subject,
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.45,
                      fontWeight: live ? FontWeight.w700 : FontWeight.w500,
                      color: cancelled ? AppColors.textSecondary : AppColors.textPrimary,
                      decoration: cancelled ? TextDecoration.lineThrough : null,
                    ),
                  ),
                ),
                if (live)
                  _Pill(text: AppStrings.t('class_live'), fill: AppColors.primary, ink: AppColors.onPrimary)
                else if (badge != null)
                  _Pill(text: badge, fill: accent.withValues(alpha: AppColors.isDark ? 0.18 : 0.12), ink: accent),
              ],
            ),
            if (detail.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(detail, style: TextStyle(fontSize: 12, height: 1.5, color: AppColors.textSecondary)),
            ],
          ],
        ),
                  ),
                ),
              ],
            ),
          ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String text;
  final Color fill, ink;
  const _Pill({required this.text, required this.fill, required this.ink});

  @override
  Widget build(BuildContext context) => Container(
        height: 24,
        padding: const EdgeInsets.symmetric(horizontal: 9),
        decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(999)),
        alignment: Alignment.center,
        child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: ink)),
      );
}

/// Empty period: a dashed-look button that opens the add-class sheet.
/// Display only: the school timetable is not edited by students.
///
/// UZ: Bo'sh dars soati: dars qo'shish varag'ini ochadigan chiziqchali ko'rinishdagi tugma.
/// Faqat ko'rsatish uchun: maktab dars jadvali talabalar tomonidan tahrirlanmaydi.
class _FreeSlot extends StatelessWidget {
  const _FreeSlot();

  @override
  Widget build(BuildContext context) => Container(
            constraints: const BoxConstraints(minHeight: 56),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.checkboxUnchecked, width: 1.5),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(AppStrings.t('tt_free_slot'),
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
              ],
            ),
      );
}

/// 昼休み divider between two periods.
///
/// UZ: Ikki dars soati orasidagi 昼休み ajratuvchisi.
class _BreakLine extends StatelessWidget {
  final String text;
  const _BreakLine({required this.text});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(64, 0, 0, 10),
        child: Row(
          children: [
            Expanded(child: Divider(color: AppColors.cardStroke, height: 1)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(text, style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
            ),
            Expanded(child: Divider(color: AppColors.cardStroke, height: 1)),
          ],
        ),
      );
}
