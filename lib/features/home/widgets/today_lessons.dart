import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/periods.dart';
import '../../../core/constants/subject_colors.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/providers/clock_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/utils/date_helper.dart';
import '../../../shared/widgets/entrance.dart';
import '../../../shared/widgets/glass_panel.dart';
import '../../../shared/widgets/pressable.dart';
import '../../school/models/school.dart';
import '../../school/school_providers.dart';
import '../../timetable/providers/timetable_provider.dart';
import '../../timetable/widgets/school_slot_card.dart';

/// One lesson today, from the school timetable or the student's own list.
class TodayLesson {
  final DateTime start, end;
  final String periodLabel, title, detail;
  final String? badge;
  final Color accent;
  final bool cancelled;
  const TodayLesson({
    required this.start,
    required this.end,
    required this.periodLabel,
    required this.title,
    required this.detail,
    required this.badge,
    required this.accent,
    required this.cancelled,
  });
}

DateTime _on(DateTime day, Hm t) => DateTime(day.year, day.month, day.day, t.$1, t.$2);

/// Today's school lessons (with teacher changes) and personal classes, by start.
final todayLessonsProvider = Provider<List<TodayLesson>>((ref) {
  final now = ref.watch(todayProvider).valueOrNull ?? DateTime.now();
  final day = DateTime(now.year, now.month, now.day);
  final monday = DateTime(day.year, day.month, day.day - (day.weekday - 1));
  final slots = ref.watch(schoolWeekProvider(monday)).valueOrNull?[DateHelper.dayKey(day)]?.slots ??
      const <SchoolSlot>[];
  final periods = ref.watch(schoolInfoProvider).valueOrNull?.periods ?? const <SchoolPeriod>[];
  final lessons = <TodayLesson>[
    for (final s in slots)
      if (periods.where((p) => p.key == s.period).firstOrNull case final p?)
        TodayLesson(
          start: _on(day, p.start),
          end: _on(day, p.end),
          periodLabel: p.label,
          title: s.subject,
          detail: [formatHm(p.start), if (s.room.isNotEmpty) s.room, if (s.teacher.isNotEmpty) s.teacher].join(' · '),
          badge: schoolSlotBadge(s),
          accent: schoolSlotAccent(s),
          cancelled: s.status == SchoolSlotStatus.cancelled,
        ),
    for (final c in ref.watch(todayClassesProvider))
      if ((periodStartOn(day, c.period), periodEndOn(day, c.period)) case (final st?, final en?))
        TodayLesson(
          start: st,
          end: en,
          periodLabel: AppStrings.t('tt_period', {'n': c.period}),
          title: c.subject,
          detail: [periodTimeLabels(c.period).start, if (c.room.isNotEmpty) c.room].join(' · '),
          badge: null,
          accent: SubjectColors.of(c.subject).dot,
          cancelled: false,
        ),
  ]..sort((a, b) => a.start.compareTo(b.start));
  return lessons;
});

/// The lesson in progress, or else the next one today; nothing after the last.
class NowLessonCard extends ConsumerWidget {
  const NowLessonCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(minuteTickProvider).valueOrNull ?? DateTime.now();
    final open = ref.watch(todayLessonsProvider).where((l) => !l.cancelled && now.isBefore(l.end));
    final lesson = open.firstOrNull;
    if (lesson == null) return const SizedBox.shrink();
    final live = !now.isBefore(lesson.start);
    final minutes = (live ? lesson.end : lesson.start).difference(now).inMinutes + 1;
    final total = lesson.end.difference(lesson.start).inSeconds;
    final progress = live && total > 0 ? now.difference(lesson.start).inSeconds / total : 0.0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Pressable(
        child: GlassPanel(
          padding: const EdgeInsets.all(16),
          radius: 22,
          tint: AppColors.nowGlassFill,
          borderColor: AppColors.nowGlassBorder,
          shadows: AppColors.nowGlow,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (live) ...[
                    const _LiveDot(),
                    const SizedBox(width: 8),
                  ],
                  Container(
                    height: 26,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: live ? AppColors.primary : Colors.transparent,
                      border: live ? null : Border.all(color: AppColors.primary),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      AppStrings.t(live ? 'class_live' : 'home_next'),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: live ? AppColors.onPrimary : AppColors.accentText,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    AppStrings.t(live ? 'home_now_remaining' : 'home_next_in', {'n': minutes}),
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.accentText),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(lesson.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 20, height: 1.4, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              const SizedBox(height: 2),
              Text(
                [lesson.periodLabel, '${formatHm((lesson.start.hour, lesson.start.minute))}–${formatHm((lesson.end.hour, lesson.end.minute))}', ...lesson.detail.split(' · ').skip(1)].join(' · '),
                style: TextStyle(fontSize: 13, height: 1.5, color: AppColors.textSecondary),
              ),
              if (lesson.badge != null) ...[
                const SizedBox(height: 8),
                _Badge(text: lesson.badge!, color: lesson.accent),
              ],
              if (live) ...[
                const SizedBox(height: 10),
                _LessonProgressBar(progress: progress),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Small 8px pulsing dot next to the 授業中 badge (opacity 0.55 -> 1 over 2.4s).
class _LiveDot extends StatefulWidget {
  const _LiveDot();

  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AppMotion.dotDuration,
    );
    _animation = Tween<double>(begin: 0.55, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: AppMotion.dotCurve),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateAnimation();
  }

  void _updateAnimation() {
    final reduced = reduceMotion(context);
    final tickerEnabled = TickerMode.valuesOf(context).enabled;
    if (reduced || !tickerEnabled) {
      if (_controller.isAnimating) {
        _controller.stop();
      }
      _controller.value = 1.0;
    } else {
      if (!_controller.isAnimating) {
        _controller.repeat(reverse: true);
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isReduced = reduceMotion(context);
    return RepaintBoundary(
      child: isReduced
          ? Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary,
              ),
            )
          : FadeTransition(
              opacity: _animation,
              child: Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primary,
                ),
              ),
            ),
    );
  }
}

/// Lesson progress bar that animates from 0 to [progress] over 600ms on first entrance.
class _LessonProgressBar extends StatelessWidget {
  final double progress;
  const _LessonProgressBar({required this.progress});

  @override
  Widget build(BuildContext context) {
    final clamped = progress.clamp(0.0, 1.0);
    final animate = clamped > 0 && !Entrance.hasPlayed && !reduceMotion(context);

    Widget buildTrack(double scale) {
      return Container(
        height: 6,
        decoration: BoxDecoration(
          color: AppColors.surfaceVar,
          borderRadius: BorderRadius.circular(3),
        ),
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: clamped,
          child: Transform.scale(
            scaleX: scale,
            alignment: Alignment.centerLeft,
            child: Container(
              height: 6,
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        ),
      );
    }

    if (!animate) {
      return buildTrack(1.0);
    }

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: 1.0),
      duration: AppMotion.barDuration,
      curve: AppMotion.strongEaseOut,
      builder: (context, value, _) => buildTrack(value),
    );
  }
}

/// Today's lessons as rows in one card: colour bar, subject, time · room, badge.
class TodayLessonsCard extends ConsumerWidget {
  const TodayLessonsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(minuteTickProvider).valueOrNull ?? DateTime.now();
    final lessons = ref.watch(todayLessonsProvider);
    if (lessons.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Text(
          AppStrings.t(now.weekday > 5 ? 'home_weekend_msg' : 'home_no_classes'),
          style: TextStyle(fontSize: 13, color: AppColors.textMuted),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: AppColors.cardSurface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.cardStroke),
        ),
        child: Column(
          children: [
            for (var i = 0; i < lessons.length; i++)
              _LessonRow(lesson: lessons[i], ended: !now.isBefore(lessons[i].end), divider: i < lessons.length - 1),
          ],
        ),
      ),
    );
  }
}

class _LessonRow extends StatelessWidget {
  final TodayLesson lesson;
  final bool ended, divider;
  const _LessonRow({required this.lesson, required this.ended, required this.divider});

  @override
  Widget build(BuildContext context) {
    final muted = ended || lesson.cancelled;
    return InkWell(
      onTap: () => context.go('/timetable'),
      child: Container(
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          border: divider ? Border(bottom: BorderSide(color: AppColors.cardStroke)) : null,
        ),
        child: Row(
          children: [
            Container(
              width: 4,
              height: 32,
              decoration: BoxDecoration(color: lesson.accent, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    lesson.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.45,
                      fontWeight: FontWeight.w500,
                      color: muted ? AppColors.textSecondary : AppColors.textPrimary,
                      decoration: lesson.cancelled ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  Text(
                    '${lesson.periodLabel} ${lesson.detail}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, height: 1.5, color: muted ? AppColors.textMuted : AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (lesson.badge != null)
              _Badge(text: lesson.badge!, color: lesson.accent)
            else if (ended)
              Text(AppStrings.t('class_ended'), style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String text;
  final Color color;
  const _Badge({required this.text, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        height: 26,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: AppColors.isDark ? 0.18 : 0.12),
          borderRadius: BorderRadius.circular(999),
        ),
        alignment: Alignment.center,
        child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
      );
}
