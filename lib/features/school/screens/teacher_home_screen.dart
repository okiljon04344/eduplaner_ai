import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:toastification/toastification.dart';
import '../../../core/constants/periods.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/providers/clock_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_helper.dart';
import '../models/school.dart';
import '../models/school_assignment.dart';
import '../school_providers.dart';
import '../teacher_overview_providers.dart';
import '../widgets/teacher_scaffold.dart';
import 'teacher_assignments_screen.dart';
import 'teacher_screen.dart';

class TeacherHomeScreen extends ConsumerWidget {
  const TeacherHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(schoolInfoProvider).valueOrNull;
    final role = ref.watch(schoolRoleProvider);
    final user = FirebaseAuth.instance.currentUser;
    final mine = info?.profileOf(user?.email);

    final now = ref.watch(minuteTickProvider).valueOrNull ?? DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final nextDay = nextSchoolDay(today);

    final todayLessons = ref.watch(todayTeacherLessonsProvider);
    final nextDayLessons = ref.watch(nextDayTeacherLessonsProvider);
    final currentLesson = ref.watch(currentTeacherLessonProvider);
    final weekChanges = ref.watch(weekChangesProvider);
    final noticesSummary = ref.watch(myNoticesReadSummaryProvider);
    final classSizes = ref.watch(classSizesProvider).valueOrNull ?? const {};

    final isDesktop = MediaQuery.sizeOf(context).width >= 1100;

    int unreadCount = 0;
    if (noticesSummary.totalSize != null) {
      final unread = noticesSummary.totalSize! - noticesSummary.totalReads;
      unreadCount = unread > 0 ? unread : 0;
    }

    final hasProfileName = mine != null && mine.name.isNotEmpty;

    // Greeting text
    final hour = now.hour;
    final teacherName = hasProfileName ? mine.name : (user?.displayName ?? '');
    final greeting = hasProfileName
        ? (hour < 12
            ? AppStrings.t('tov_greeting_morning', {'name': teacherName})
            : hour < 18
                ? AppStrings.t('tov_greeting_afternoon', {'name': teacherName})
                : AppStrings.t('tov_greeting_evening', {'name': teacherName}))
        : (hour < 12
            ? AppStrings.t('tov_greeting_morning_default')
            : hour < 18
                ? AppStrings.t('tov_greeting_afternoon_default')
                : AppStrings.t('tov_greeting_evening_default'));

    // Date range pill: Mon-Fri
    final monday = mondayOf(today);
    final friday = monday.add(const Duration(days: 4));
    final weekDateRange = '${monday.month}/${monday.day}–${friday.month}/${friday.day}';

    Widget body;
    if (!role.teacher && info != null) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            AppStrings.t('teacher_no_access'),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
          ),
        ),
      );
    } else if (isDesktop) {
      body = _DesktopTeacherHome(
        info: info,
        role: role,
        hasProfileName: hasProfileName,
        greeting: greeting,
        today: today,
        nextDay: nextDay,
        now: now,
        weekDateRange: weekDateRange,
        todayLessons: todayLessons,
        nextDayLessons: nextDayLessons,
        currentLesson: currentLesson,
        weekChanges: weekChanges,
        noticesSummary: noticesSummary,
        classSizes: classSizes,
        unreadCount: unreadCount,
      );
    } else {
      body = _PhoneTeacherHome(
        info: info,
        role: role,
        hasProfileName: hasProfileName,
        greeting: greeting,
        today: today,
        nextDay: nextDay,
        now: now,
        todayLessons: todayLessons,
        currentLesson: currentLesson,
        weekChanges: weekChanges,
        noticesSummary: noticesSummary,
        classSizes: classSizes,
        unreadCount: unreadCount,
      );
    }

    return TeacherScaffold(
      section: TeacherSection.overview,
      title: AppStrings.t('tov_title'),
      body: body,
    );
  }
}

// ============================================================================
// Desktop Layout (Main.dc.html)
// ============================================================================

class _DesktopTeacherHome extends StatelessWidget {
  final SchoolInfo? info;
  final ({bool teacher, bool admin}) role;
  final bool hasProfileName;
  final String greeting;
  final DateTime today;
  final DateTime nextDay;
  final DateTime now;
  final String weekDateRange;
  final List<TeacherLesson> todayLessons;
  final List<TeacherLesson> nextDayLessons;
  final TeacherLesson? currentLesson;
  final WeekChangesSummary weekChanges;
  final NoticesReadSummary noticesSummary;
  final Map<String, int> classSizes;
  final int unreadCount;

  const _DesktopTeacherHome({
    required this.info,
    required this.role,
    required this.hasProfileName,
    required this.greeting,
    required this.today,
    required this.nextDay,
    required this.now,
    required this.weekDateRange,
    required this.todayLessons,
    required this.nextDayLessons,
    required this.currentLesson,
    required this.weekChanges,
    required this.noticesSummary,
    required this.classSizes,
    required this.unreadCount,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 24, 32),
      children: [
        // Header
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    greeting,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    AppStrings.t('tov_summary_line', {
                      'lessons': todayLessons.length,
                      'unread': unreadCount,
                      'changes': weekChanges.total,
                    }),
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            FilledButton.icon(
              onPressed: () => context.push('/teacher/notices'),
              icon: const Icon(Icons.add, size: 18),
              label: Text(
                AppStrings.t('tov_send_notice'),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.onPrimary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                padding: const EdgeInsets.symmetric(horizontal: 18),
                minimumSize: const Size(0, 44),
              ),
            ),
          ],
        ),

        const SizedBox(height: 16),

        // Filter pills row
        Row(
          children: [
            _PillChip(
              label: AppStrings.t('tov_pill_this_week', {'range': weekDateRange}),
            ),
            const SizedBox(width: 8),
            _PillChip(
              label: AppStrings.t('tov_pill_all_classes'),
            ),
          ],
        ),

        const SizedBox(height: 16),

        // If no profile name set, show prompt
        if (!hasProfileName) ...[
          _NoProfileWarning(role: role),
          const SizedBox(height: 16),
        ],

        // 3-Column Layout: Column 1 spans 2 rows
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Column 1: 今日の私の授業
            Expanded(
              child: _MyLessonsCard(
                info: info,
                today: today,
                nextDay: nextDay,
                now: now,
                todayLessons: todayLessons,
                nextDayLessons: nextDayLessons,
                currentLesson: currentLesson,
                classSizes: classSizes,
                mostUnreadNotice: noticesSummary.mostUnreadNotice,
                isDesktop: true,
              ),
            ),

            const SizedBox(width: 16),

            // Column 2: お知らせの既読 (Row 1) + 担当クラス (Row 2)
            Expanded(
              child: Column(
                children: [
                  _NoticesReadCard(
                    summary: noticesSummary,
                    isDesktop: true,
                  ),
                  const SizedBox(height: 16),
                  _MyClassesCard(
                    info: info,
                    classSizes: classSizes,
                    weekChanges: weekChanges,
                    isDesktop: true,
                  ),
                ],
              ),
            ),

            const SizedBox(width: 16),

            // Column 3: 今週の時間割変更 (Row 1) + 課題配布 (Row 2)
            Expanded(
              child: Column(
                children: [
                  _WeekChangesCard(
                    summary: weekChanges,
                    isDesktop: true,
                  ),
                  const SizedBox(height: 16),
                  const _AssignmentsCard(isDesktop: true),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ============================================================================
// Phone Layout (Phone.dc.html)
// ============================================================================

class _PhoneTeacherHome extends StatelessWidget {
  final SchoolInfo? info;
  final ({bool teacher, bool admin}) role;
  final bool hasProfileName;
  final String greeting;
  final DateTime today;
  final DateTime nextDay;
  final DateTime now;
  final List<TeacherLesson> todayLessons;
  final TeacherLesson? currentLesson;
  final WeekChangesSummary weekChanges;
  final NoticesReadSummary noticesSummary;
  final Map<String, int> classSizes;
  final int unreadCount;

  const _PhoneTeacherHome({
    required this.info,
    required this.role,
    required this.hasProfileName,
    required this.greeting,
    required this.today,
    required this.nextDay,
    required this.now,
    required this.todayLessons,
    required this.currentLesson,
    required this.weekChanges,
    required this.noticesSummary,
    required this.classSizes,
    required this.unreadCount,
  });

  @override
  Widget build(BuildContext context) {
    final dateHeader =
        '${now.month}月${now.day}日（${DateHelper.getDayOfWeek(now)}）· ${info?.name ?? ''}';

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        // Phone Header
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              dateHeader,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              greeting,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              AppStrings.t('tov_summary_phone', {
                'lessons': todayLessons.length,
                'unread': unreadCount,
              }),
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),

        const SizedBox(height: 14),

        // 2-card stats row
        Row(
          children: [
            Expanded(
              child: _PhoneStatCard(
                title: AppStrings.t('tov_notices_read_phone_title'),
                value: noticesSummary.overallPercent != null
                    ? '${noticesSummary.overallPercent}%'
                    : '—',
                sub: noticesSummary.totalSize != null
                    ? AppStrings.t('tov_notices_read_stat', {
                        'count': noticesSummary.items.length,
                        'reads': noticesSummary.totalReads,
                        'total': noticesSummary.totalSize!,
                      })
                    : AppStrings.t('tov_notices_read_stat_no_total', {
                        'count': noticesSummary.items.length,
                        'reads': noticesSummary.totalReads,
                      }),
                onTap: () => context.go('/teacher/notices'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _PhoneStatCard(
                title: AppStrings.t('tov_week_changes_phone_title'),
                value: '${weekChanges.total} ${AppStrings.t('tov_changes_count_unit')}',
                sub: AppStrings.t('tov_changes_phone_sub', {
                  'cancel': weekChanges.cancelledCount,
                  'room': weekChanges.roomChangeCount,
                  'makeup': weekChanges.makeupCount,
                }),
                onTap: () => context.go('/teacher/timetable'),
              ),
            ),
          ],
        ),

        const SizedBox(height: 14),

        // If no profile name set, show prompt
        if (!hasProfileName) ...[
          _NoProfileWarning(role: role),
          const SizedBox(height: 14),
        ],

        // 今日の私の授業
        _MyLessonsCard(
          info: info,
          today: today,
          nextDay: nextDay,
          now: now,
          todayLessons: todayLessons,
          nextDayLessons: const [], // Phone shows today only in this section
          currentLesson: currentLesson,
          classSizes: classSizes,
          mostUnreadNotice: null,
          isDesktop: false,
        ),

        const SizedBox(height: 14),

        // Unread hint row
        if (noticesSummary.mostUnreadNotice != null) ...[
          _UnreadHintRow(
            unreadNotice: noticesSummary.mostUnreadNotice!,
            isDesktop: false,
          ),
          const SizedBox(height: 14),
        ],

        // お知らせの既読
        _NoticesReadCard(
          summary: noticesSummary,
          isDesktop: false,
        ),

        const SizedBox(height: 14),

        // 担当クラス
        _MyClassesCard(
          info: info,
          classSizes: classSizes,
          weekChanges: weekChanges,
          isDesktop: false,
        ),

        const SizedBox(height: 14),

        // 課題配布
        const _AssignmentsCard(),
      ],
    );
  }
}

// ============================================================================
// Shared Section Cards
// ============================================================================

class _NoProfileWarning extends StatelessWidget {
  final ({bool teacher, bool admin}) role;
  const _NoProfileWarning({required this.role});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.warningLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.warning),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline, color: AppColors.warning, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  AppStrings.t('tov_empty_no_profile_name'),
                  style: TextStyle(fontSize: 13, height: 1.4, color: AppColors.textPrimary),
                ),
              ),
            ],
          ),
          if (role.admin) ...[
            const SizedBox(height: 10),
            FilledButton.tonal(
              onPressed: () => context.go('/school-admin'),
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(AppStrings.t('school_admin_title')),
            ),
          ],
        ],
      ),
    );
  }
}

class _PillChip extends StatelessWidget {
  final String label;
  const _PillChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.cardStroke),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }
}

class _PhoneStatCard extends StatelessWidget {
  final String title;
  final String value;
  final String sub;
  final VoidCallback onTap;

  const _PhoneStatCard({
    required this.title,
    required this.value,
    required this.sub,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.cardSurface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.cardStroke),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: TextStyle(
                fontFamily: 'Space Grotesk',
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            Text(
              sub,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------------
// 今日の私の授業 Card
// ----------------------------------------------------------------------------

class _MyLessonsCard extends StatelessWidget {
  final SchoolInfo? info;
  final DateTime today;
  final DateTime nextDay;
  final DateTime now;
  final List<TeacherLesson> todayLessons;
  final List<TeacherLesson> nextDayLessons;
  final TeacherLesson? currentLesson;
  final Map<String, int> classSizes;
  final NoticeReadItem? mostUnreadNotice;
  final bool isDesktop;

  const _MyLessonsCard({
    required this.info,
    required this.today,
    required this.nextDay,
    required this.now,
    required this.todayLessons,
    required this.nextDayLessons,
    required this.currentLesson,
    required this.classSizes,
    this.mostUnreadNotice,
    required this.isDesktop,
  });

  void _openOverride(BuildContext context, SchoolOverrideKind kind) {
    final cur = currentLesson;
    if (cur == null || info == null) return;
    final me = FirebaseAuth.instance.currentUser;

    final allowed = info!.canEdit(
      uid: me?.uid,
      email: me?.email,
      grade: cur.grade,
      course: cur.course,
      slot: cur.slot,
    );

    if (!allowed) {
      toastification.show(
        context: context,
        type: ToastificationType.error,
        style: ToastificationStyle.flat,
        title: Text(AppStrings.t('teacher_no_edit_slot')),
        autoCloseDuration: const Duration(seconds: 3),
      );
      return;
    }

    showOverrideSheet(
      context,
      grade: cur.grade,
      course: cur.course,
      date: cur.date,
      period: cur.period,
      slot: cur.slot,
      initialKind: kind,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cur = currentLesson;
    final curSize = cur != null ? classSizes['${cur.grade}_${cur.course}'] : null;

    final nextDayLabel = nextDay.year == today.year &&
            nextDay.month == today.month &&
            nextDay.day == today.day + 1
        ? AppStrings.t('tov_tomorrow')
        : DateHelper.getDayOfWeek(nextDay);

    return Container(
      constraints: isDesktop ? const BoxConstraints(minHeight: 476) : null,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.cardStroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              Expanded(
                child: Text(
                  AppStrings.t('tov_my_today_lessons'),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              InkWell(
                onTap: () => context.go('/teacher/timetable'),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Text(
                    AppStrings.t('tov_go_timetable'),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.accentText,
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Current lesson highlighted box
          if (cur != null) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          AppStrings.t('tov_now_badge'),
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: AppColors.onPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${cur.period.label} ${_formatTime(cur.period.start)}–${_formatTime(cur.period.end)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    cur.slot.subject,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${cur.grade}年${cur.course}${cur.slot.room.isNotEmpty ? " · ${cur.slot.room}" : ""}${curSize != null ? " · $curSize人" : ""}',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => _openOverride(context, SchoolOverrideKind.cancelled),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.danger,
                            side: BorderSide(color: AppColors.cardStroke),
                            backgroundColor: AppColors.cardSurface,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            minimumSize: const Size(0, 40),
                          ),
                          child: Text(
                            AppStrings.t('tov_btn_cancel_lesson'),
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => _openOverride(context, SchoolOverrideKind.room),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.textPrimary,
                            side: BorderSide(color: AppColors.cardStroke),
                            backgroundColor: AppColors.cardSurface,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            minimumSize: const Size(0, 40),
                          ),
                          child: Text(
                            AppStrings.t('tov_btn_change_room'),
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Empty state when no lessons today
          if (todayLessons.isEmpty) ...[
            Padding(
              padding: EdgeInsets.symmetric(vertical: isDesktop ? 60 : 20),
              child: Center(
                child: Text(
                  AppStrings.t('tov_empty_no_lessons_today'),
                  style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                ),
              ),
            ),
          ] else ...[
            // "今日" section
            Text(
              AppStrings.t('tov_today'),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 4),
            for (final l in todayLessons) _LessonRow(lesson: l, now: now),
          ],

          // "明日" (Desktop shows tomorrow's lessons if available)
          if (isDesktop && nextDayLessons.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              nextDayLabel,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 4),
            for (final l in nextDayLessons) _LessonRow(lesson: l, now: now),
          ],

          // Unread hint row at bottom (Desktop)
          if (isDesktop && mostUnreadNotice != null) ...[
            const SizedBox(height: 10),
            _UnreadHintRow(unreadNotice: mostUnreadNotice!, isDesktop: true),
          ],
        ],
      ),
    );
  }

  String _formatTime(Hm hm) => '${hm.$1}:${hm.$2.toString().padLeft(2, '0')}';
}

class _LessonRow extends StatelessWidget {
  final TeacherLesson lesson;
  final DateTime now;
  const _LessonRow({required this.lesson, required this.now});

  @override
  Widget build(BuildContext context) {
    final isDone = isLessonDone(lesson, now);
    final isCancelled = lesson.slot.status == SchoolSlotStatus.cancelled ||
        lesson.slot.teacherKind == SchoolOverrideKind.cancelled;

    String tagText = '';
    Color tagColor = AppColors.textSecondary;

    if (isDone) {
      tagText = AppStrings.t('tov_tag_done');
      tagColor = AppColors.textMuted;
    } else if (isCancelled) {
      tagText = AppStrings.t('tov_cancelled');
      tagColor = AppColors.danger;
    } else if (lesson.period.start.$1 > 0 || lesson.period.start.$2 > 0) {
      tagText = '${lesson.period.start.$1}:${lesson.period.start.$2.toString().padLeft(2, '0')}〜';
      tagColor = AppColors.textSecondary;
    }

    return Container(
      constraints: const BoxConstraints(minHeight: 52),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.borderLight)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 54,
            child: Text(
              lesson.period.label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  lesson.slot.subject,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  '${lesson.grade}年${lesson.course}${lesson.slot.room.isNotEmpty ? " · ${lesson.slot.room}" : ""}',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          if (tagText.isNotEmpty)
            Text(
              tagText,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: tagColor,
              ),
            ),
        ],
      ),
    );
  }
}

class _UnreadHintRow extends StatelessWidget {
  final NoticeReadItem unreadNotice;
  final bool isDesktop;

  const _UnreadHintRow({required this.unreadNotice, required this.isDesktop});

  @override
  Widget build(BuildContext context) {
    final n = unreadNotice.notice;
    final clsStr = '${n.grade}年${n.course ?? ''}';
    final title = AppStrings.t('tov_unread_hint_title', {'cls': clsStr, 'n': unreadNotice.unread});
    final sub = isDesktop
        ? AppStrings.t('tov_unread_hint_sub', {'title': n.title})
        : AppStrings.t('tov_unread_hint_sub_phone', {'title': n.title});
    final btn = isDesktop
        ? AppStrings.t('tov_unread_hint_btn')
        : AppStrings.t('tov_unread_hint_btn_phone');

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => context.push('/teacher/notices'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.warning.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              size: 20,
              color: AppColors.warning,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              btn,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: AppColors.accentText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------------
// お知らせの既読 Card
// ----------------------------------------------------------------------------

class _NoticesReadCard extends StatelessWidget {
  final NoticesReadSummary summary;
  final bool isDesktop;

  const _NoticesReadCard({required this.summary, required this.isDesktop});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: isDesktop ? const BoxConstraints(minHeight: 220) : null,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.cardStroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  AppStrings.t('tov_notices_read_card'),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              InkWell(
                onTap: () => context.go('/teacher/notices'),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Text(
                    isDesktop
                        ? AppStrings.t('tov_detail_link')
                        : AppStrings.t('tov_all_link'),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.accentText,
                    ),
                  ),
                ),
              ),
            ],
          ),

          if (isDesktop) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  summary.overallPercent != null ? '${summary.overallPercent}%' : '—',
                  style: TextStyle(
                    fontFamily: 'Space Grotesk',
                    fontSize: 44,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.8,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  summary.totalSize != null
                      ? AppStrings.t('tov_notices_read_stat', {
                          'count': summary.items.length,
                          'reads': summary.totalReads,
                          'total': summary.totalSize!,
                        })
                      : AppStrings.t('tov_notices_read_stat_no_total', {
                          'count': summary.items.length,
                          'reads': summary.totalReads,
                        }),
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(height: 12),

          if (summary.items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                AppStrings.t('notice_empty'),
                style: TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
            )
          else
            for (int i = 0; i < summary.items.length; i++) ...[
              if (i > 0) const SizedBox(height: 10),
              _NoticeBar(item: summary.items[i]),
            ],
        ],
      ),
    );
  }
}

class _NoticeBar extends StatelessWidget {
  final NoticeReadItem item;
  const _NoticeBar({required this.item});

  @override
  Widget build(BuildContext context) {
    final countLabel = item.size != null
        ? '${item.reads} / ${item.size}人'
        : AppStrings.t('teacher_read_count', {'n': item.reads});

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                item.notice.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              countLabel,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          height: 6,
          decoration: BoxDecoration(
            color: AppColors.borderLight,
            borderRadius: BorderRadius.circular(6),
          ),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: item.percent ?? 0.0,
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ----------------------------------------------------------------------------
// 今週の時間割変更 Card
// ----------------------------------------------------------------------------

class _WeekChangesCard extends StatelessWidget {
  final WeekChangesSummary summary;
  final bool isDesktop;

  const _WeekChangesCard({required this.summary, required this.isDesktop});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: isDesktop ? const BoxConstraints(minHeight: 220) : null,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.cardStroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  AppStrings.t('tov_week_changes_card'),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              InkWell(
                onTap: () => context.go('/teacher/timetable'),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Text(
                    AppStrings.t('tov_detail_link'),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.accentText,
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '${summary.total}',
                style: TextStyle(
                  fontFamily: 'Space Grotesk',
                  fontSize: 44,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.8,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                AppStrings.t('tov_changes_stat_sub'),
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // 3 colored boxes
          Row(
            children: [
              Expanded(
                child: _ChangeBox(
                  count: summary.cancelledCount,
                  label: AppStrings.t('tov_cancelled'),
                  color: AppColors.danger,
                  bg: AppColors.danger.withValues(alpha: 0.14),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ChangeBox(
                  count: summary.roomChangeCount,
                  label: AppStrings.t('tov_room_change'),
                  color: AppColors.warning,
                  bg: AppColors.warning.withValues(alpha: 0.14),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ChangeBox(
                  count: summary.makeupCount,
                  label: AppStrings.t('tov_makeup'),
                  color: AppColors.accentText,
                  bg: AppColors.primary.withValues(alpha: 0.14),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // 2 recent items
          if (summary.recentItems.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                '—',
                style: TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
            )
          else
            for (final item in summary.recentItems) _RecentChangeRow(item: item),
        ],
      ),
    );
  }
}

class _ChangeBox extends StatelessWidget {
  final int count;
  final String label;
  final Color color;
  final Color bg;

  const _ChangeBox({
    required this.count,
    required this.label,
    required this.color,
    required this.bg,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$count',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentChangeRow extends StatelessWidget {
  final ClassChangeItem item;
  const _RecentChangeRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final parts = item.change.date.split('-');
    String dateStr = item.change.date;
    if (parts.length == 3) {
      final m = int.tryParse(parts[1]) ?? 0;
      final d = int.tryParse(parts[2]) ?? 0;
      final dt = DateTime(int.tryParse(parts[0]) ?? 0, m, d);
      dateStr = '$m/$d ${DateHelper.getDayOfWeek(dt)}';
    }

    String tag = item.change.what;
    Color tagColor = AppColors.warning;
    if (item.change.what == '休講') {
      tag = AppStrings.t('tov_cancelled');
      tagColor = AppColors.danger;
    } else if (item.change.what == '補講') {
      tag = AppStrings.t('tov_makeup');
      tagColor = AppColors.accentText;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 70,
            child: Text(
              dateStr,
              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          ),
          Expanded(
            child: Text(
              '${item.grade}年${item.course} ${item.change.period} ${item.change.subject}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: AppColors.textPrimary),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            tag,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: tagColor,
            ),
          ),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------------------
// 担当クラス Card
// ----------------------------------------------------------------------------

class _MyClassesCard extends StatelessWidget {
  final SchoolInfo? info;
  final Map<String, int> classSizes;
  final WeekChangesSummary weekChanges;
  final bool isDesktop;

  const _MyClassesCard({
    required this.info,
    required this.classSizes,
    required this.weekChanges,
    required this.isDesktop,
  });

  @override
  Widget build(BuildContext context) {
    if (info == null) return const SizedBox.shrink();

    final user = FirebaseAuth.instance.currentUser;
    final mine = info!.profileOf(user?.email);

    int totalClasses = 0;
    for (final _ in info!.grades) {
      totalClasses += info!.courses.length;
    }

    return Container(
      constraints: isDesktop ? const BoxConstraints(minHeight: 240) : null,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.cardStroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  AppStrings.t('tov_my_classes'),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              Text(
                AppStrings.t('tov_classes_count', {'n': totalClasses}),
                style: TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
            ],
          ),
          const SizedBox(height: 8),

          for (final grade in info!.grades.reversed) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  const Icon(Icons.keyboard_arrow_down, size: 16),
                  const SizedBox(width: 4),
                  Text(
                    '$grade年',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            for (final course in info!.courses) ...[
              _ClassRowItem(
                grade: grade,
                course: course,
                isHomeroom: mine?.homeroomGrade == grade && mine?.homeroomCourse == course,
                size: classSizes['${grade}_$course'],
                weekChanges: weekChanges,
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _ClassRowItem extends StatelessWidget {
  final int grade;
  final String course;
  final bool isHomeroom;
  final int? size;
  final WeekChangesSummary weekChanges;

  const _ClassRowItem({
    required this.grade,
    required this.course,
    required this.isHomeroom,
    this.size,
    required this.weekChanges,
  });

  @override
  Widget build(BuildContext context) {
    // Count changes for this class
    int cancelledForClass = 0;
    int changesForClass = 0;
    for (final item in weekChanges.recentItems) {
      if (item.grade == grade && item.course == course) {
        if (item.change.what == '休講') {
          cancelledForClass++;
        } else {
          changesForClass++;
        }
      }
    }

    String chgText = '—';
    Color chgColor = AppColors.textMuted;
    if (cancelledForClass > 0) {
      chgText = AppStrings.t('tov_cancelled_n', {'n': cancelledForClass});
      chgColor = AppColors.danger;
    } else if (changesForClass > 0) {
      chgText = AppStrings.t('tov_changes_n', {'n': changesForClass});
      chgColor = AppColors.warning;
    }

    return Container(
      constraints: const BoxConstraints(minHeight: 40),
      padding: const EdgeInsets.only(left: 20),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.borderLight)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              course,
              style: TextStyle(fontSize: 13, color: AppColors.textPrimary),
            ),
          ),
          if (isHomeroom) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                AppStrings.t('teacher_homeroom_badge'),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: AppColors.accentText,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          SizedBox(
            width: 44,
            child: Text(
              size != null ? AppStrings.t('tov_count_people', {'n': size!}) : '—',
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 56,
            child: Text(
              chgText,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: chgColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------------------
// 課題配布 Card (準備中)
// ----------------------------------------------------------------------------

class _AssignmentsCard extends ConsumerWidget {
  final bool isDesktop;
  const _AssignmentsCard({this.isDesktop = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assignments = ref.watch(schoolAssignmentsProvider).valueOrNull ?? const [];
    final latest = assignments.isNotEmpty ? assignments.first : null;

    final progressList = latest != null
        ? (ref.watch(assignmentProgressProvider(latest.id)).valueOrNull ?? const [])
        : const <AssignmentProgress>[];
    final summary = summarizeProgress(progressList);
    final total = summary.total > 0 ? summary.total : (latest?.total ?? 0);
    final rate = total > 0 ? (summary.completed / total).clamp(0.0, 1.0) : 0.0;

    return Container(
      constraints: isDesktop ? const BoxConstraints(minHeight: 240) : null,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.cardStroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  AppStrings.t('tov_assignments_card'),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              InkWell(
                onTap: () => context.go('/teacher/assignments'),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        AppStrings.t('sas_view_all'),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                      const Icon(Icons.chevron_right, size: 16, color: AppColors.primary),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (latest == null) ...[
            Padding(
              padding: EdgeInsets.symmetric(vertical: isDesktop ? 36 : 0),
              child: Center(
                child: Text(
                  AppStrings.t('sas_empty_overview'),
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          ] else ...[
            InkWell(
              onTap: () => context.go('/teacher/assignments'),
              borderRadius: BorderRadius.circular(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    latest.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    [
                      latest.subject,
                      assignmentTargetLabel(latest.grade, latest.course),
                      '${AppStrings.t('sas_due_label')}: ${DateHelper.formatJapaneseDate(latest.dueAt)}',
                    ].where((s) => s.isNotEmpty).join(' · '),
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: rate,
                      minHeight: 6,
                      backgroundColor: AppColors.border,
                      valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        AppStrings.t('sas_progress_summary', {
                          'done': summary.completed,
                          'total': total,
                        }),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.accentText,
                        ),
                      ),
                      Text(
                        AppStrings.t('sas_progress_breakdown', {
                          'inProgress': summary.inProgress,
                          'notStarted': summary.notStarted,
                        }),
                        style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
