import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toastification/toastification.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/services/functions_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_helper.dart';
import '../../../core/utils/responsive.dart';
import '../../timetable/widgets/school_slot_card.dart';
import '../models/school.dart';
import '../school_providers.dart';
import '../widgets/teacher_scaffold.dart';

const _kWeekdays = ['月', '火', '水', '木', '金'];
const _kLinkPage = 'https://eduplannerai-97365.web.app/school-link.html';

DateTime _mondayOf(DateTime d) => DateTime(d.year, d.month, d.day - (d.weekday - 1));

void _toast(BuildContext context, String msg, {bool error = false}) => toastification.show(
      context: context,
      type: error ? ToastificationType.error : ToastificationType.success,
      style: ToastificationStyle.flat,
      title: Text(msg),
      autoCloseDuration: const Duration(seconds: 3),
    );

String _callError(Object e) => switch (e) {
      FirebaseFunctionsException(code: 'permission-denied') => AppStrings.t('teacher_no_edit_slot'),
      FirebaseFunctionsException(code: 'invalid-argument', :final message?) => message,
      FirebaseFunctionsException() => FunctionsService.describeError(e),
      _ => AppStrings.t('teacher_failed'),
    };

/// 教員メニュー (§9): pick a class and week, tap a lesson to publish a
/// 休講・教室変更・補講・メモ that reaches the class at once. Admins also
/// register teacher emails here.
class TeacherScreen extends ConsumerStatefulWidget {
  const TeacherScreen({super.key});

  @override
  ConsumerState<TeacherScreen> createState() => _TeacherScreenState();
}

class _TeacherScreenState extends ConsumerState<TeacherScreen> {
  int? _grade;
  String? _course;
  int _weekOffset = 0;

  /// Desktop: the lesson shown in the side panel.
  ({DateTime date, SchoolPeriod period, SchoolSlot? slot})? _sel;

  @override
  Widget build(BuildContext context) {
    final info = ref.watch(schoolInfoProvider).valueOrNull;
    final role = ref.watch(schoolRoleProvider);

    Widget body;
    if (info == null || info.periods.isEmpty) {
      body = _Message(AppStrings.t('teacher_no_school'));
    } else if (!role.teacher) {
      body = _Message(AppStrings.t('teacher_no_access'));
    } else {
      final me = FirebaseAuth.instance.currentUser;
      final mine = info.profileOf(me?.email);
      // Homeroom teachers start on their own class.
      final grade = info.grades.contains(_grade)
          ? _grade!
          : (info.grades.contains(mine?.homeroomGrade) ? mine!.homeroomGrade! : info.grades.first);
      final course = info.courses.contains(_course)
          ? _course!
          : (info.courses.contains(mine?.homeroomCourse) ? mine!.homeroomCourse! : info.courses.first);
      final now = DateTime.now();
      final monday = _mondayOf(now);
      final weekStart = DateTime(monday.year, monday.month, monday.day + 7 * _weekOffset);
      final week = ref
              .watch(schoolClassWeekProvider((grade: grade, course: course, weekStart: weekStart)))
              .valueOrNull ??
          const <String, SchoolDay>{};
      final today = DateTime(now.year, now.month, now.day);

      final wide = context.screenWidth >= 1100;
      void tap(DateTime date, SchoolPeriod period, SchoolSlot? slot) {
        final allowed = info.canEdit(
          uid: me?.uid,
          email: me?.email,
          grade: grade,
          course: course,
          slot: slot,
          dayTeachers: week[DateHelper.dayKey(date)]?.slots.map((s) => s.teacher) ?? const [],
        );
        if (!allowed) {
          _toast(context, AppStrings.t('teacher_no_edit_slot'), error: true);
          return;
        }
        if (wide) {
          setState(() => _sel = (date: date, period: period, slot: slot));
        } else {
          _openSheet(context, info, grade, course, date, period, slot);
        }
      }

      void pickClass(int g, String c) => setState(() {
            _grade = g;
            _course = c;
            _sel = null;
          });
      void moveWeek(int delta) => setState(() {
            _weekOffset = delta == 0 ? 0 : _weekOffset + delta;
            _sel = null;
          });

      final weekColumn = <Widget>[
        const _TeacherGuide(),
        const SizedBox(height: 4),
        _WeekBar(
          weekStart: weekStart,
          isCurrent: _weekOffset == 0,
          onPrevious: () => moveWeek(-1),
          onNext: () => moveWeek(1),
          onToday: () => moveWeek(0),
        ),
        const SizedBox(height: 8),
        _WeekView(info: info, week: week, weekStart: weekStart, today: today, onTap: tap),
      ];

      if (wide) {
        final sel = _sel;
        body = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 220,
              child: _ClassList(
                info: info,
                mine: mine,
                grade: grade,
                course: course,
                onPick: pickClass,
              ),
            ),
            Expanded(
              child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: weekColumn),
            ),
            Container(
              width: 360,
              margin: const EdgeInsets.fromLTRB(0, 8, 16, 16),
              decoration: BoxDecoration(
                color: AppColors.cardSurface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.cardStroke),
              ),
              child: sel == null
                  ? Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(AppStrings.t('teacher_pick_slot'),
                          style: TextStyle(fontSize: 13, height: 1.5, color: AppColors.textSecondary)),
                    )
                  : _OverrideSheet(
                      key: ValueKey('$grade$course${sel.date}${sel.period.key}'),
                      grade: grade,
                      course: course,
                      date: sel.date,
                      period: sel.period,
                      slot: sel.slot,
                      onDone: () => setState(() => _sel = null),
                    ),
            ),
          ],
        );
      } else {
        body = ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final g in info.grades)
                  ChoiceChip(
                    label: Text(AppStrings.t('teacher_grade', {'n': g})),
                    selected: g == grade,
                    onSelected: (_) => pickClass(g, course),
                  ),
                for (final c in info.courses)
                  ChoiceChip(
                    label: Text(c),
                    selected: c == course,
                    onSelected: (_) => pickClass(grade, c),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            ...weekColumn,
          ],
        );
      }
    }

    return TeacherScaffold(
      section: TeacherSection.timetable,
      title: AppStrings.t('teacher_title'),
      body: ResponsiveBody(maxWidth: 1600, child: body),
    );
  }

  Future<void> _openSheet(BuildContext context, SchoolInfo info, int grade, String course,
      DateTime date, SchoolPeriod period, SchoolSlot? slot) {
    return showOverrideSheet(
      context,
      grade: grade,
      course: course,
      date: date,
      period: period,
      slot: slot,
    );
  }
}

/// First-run guide: three steps the first time, then the one-line hint with
/// a button to see the steps again.
class _TeacherGuide extends StatefulWidget {
  const _TeacherGuide();

  @override
  State<_TeacherGuide> createState() => _TeacherGuideState();
}

class _TeacherGuideState extends State<_TeacherGuide> {
  static const _seenKey = 'teacher_guide_seen';
  int? _step; // null = closed

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (mounted && !(p.getBool(_seenKey) ?? false)) setState(() => _step = 0);
    });
  }

  Future<void> _close() async {
    setState(() => _step = null);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_seenKey, true);
  }

  @override
  Widget build(BuildContext context) {
    final step = _step;
    if (step == null) {
      return Row(
        children: [
          Expanded(
            child: Text(AppStrings.t('teacher_hint'), style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ),
          TextButton(onPressed: () => setState(() => _step = 0), child: Text(AppStrings.t('teacher_guide_reopen'))),
        ],
      );
    }
    // Align: a ListView child gets tight width, which ConstrainedBox alone can't narrow.
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 640),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
        decoration: BoxDecoration(
          color: AppColors.warningLight,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.warning),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${AppStrings.t('teacher_guide_title')} · ${step + 1} / 3',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 4),
            Text(AppStrings.t('teacher_guide_step${step + 1}'),
                style: TextStyle(fontSize: 14, height: 1.5, color: AppColors.textPrimary)),
            Row(
              children: [
                TextButton(
                  onPressed: step == 0 ? _close : () => setState(() => _step = step - 1),
                  child: Text(AppStrings.t(step == 0 ? 'teacher_guide_skip' : 'teacher_guide_back')),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: step == 2 ? _close : () => setState(() => _step = step + 1),
                  child: Text(AppStrings.t(step == 2 ? 'teacher_guide_start' : 'teacher_guide_next')),
                ),
              ],
            ),
          ],
        ),
      ),
      ),
    );
  }
}

/// 学校の管理 (admin only): teacher registry, the student-edit switch and
/// the file-link page, kept off the teachers' daily screen.
class SchoolAdminScreen extends ConsumerWidget {
  const SchoolAdminScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(schoolInfoProvider).valueOrNull;
    final role = ref.watch(schoolRoleProvider);
    return TeacherScaffold(
      section: TeacherSection.admin,
      title: AppStrings.t('school_admin_title'),
      body: info == null || !role.admin
          ? _Message(AppStrings.t('teacher_no_access'))
          : ResponsiveBody(
              maxWidth: 640,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [_TeacherRegistry(info: info), const SizedBox(height: 16), _TesterSection(info: info)],
              ),
            ),
    );
  }
}

/// Pilot test accounts: non-school emails (e.g. Gmail) that act as students
/// of this school until removed (setSchoolTester).
class _TesterSection extends StatefulWidget {
  final SchoolInfo info;
  const _TesterSection({required this.info});

  @override
  State<_TesterSection> createState() => _TesterSectionState();
}

class _TesterSectionState extends State<_TesterSection> {
  final _email = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _set(String email, bool add) async {
    if (_busy || email.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      await FunctionsService.callable('setSchoolTester').call({'email': email.trim(), 'add': add});
      if (!mounted) return;
      if (add) _email.clear();
      _toast(context, AppStrings.t(add ? 'teacher_admin_added' : 'teacher_admin_removed'));
    } catch (e) {
      if (mounted) _toast(context, _callError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final testers = widget.info.testers;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.cardStroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(AppStrings.t('school_tester_title'),
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
          const SizedBox(height: 4),
          Text(AppStrings.t('school_tester_sub'),
              style: TextStyle(fontSize: 12, height: 1.5, color: AppColors.textSecondary)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  maxLength: 200,
                  decoration: const InputDecoration(hintText: 'example@gmail.com', counterText: ''),
                  onSubmitted: (v) => _set(v, true),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _busy ? null : () => _set(_email.text, true),
                child: Text(AppStrings.t('teacher_admin_add')),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final t in testers)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: Icon(Icons.science_outlined, color: AppColors.textSecondary),
              title: Text(t, style: TextStyle(fontSize: 13, color: AppColors.textPrimary)),
              trailing: IconButton(
                tooltip: AppStrings.t('teacher_admin_remove'),
                icon: const Icon(Icons.delete_outline, color: AppColors.danger),
                onPressed: _busy ? null : () => _set(t, false),
              ),
            ),
        ],
      ),
    );
  }
}

/// Desktop class picker: the homeroom class first, marked 担任.
class _ClassList extends StatelessWidget {
  final SchoolInfo info;
  final TeacherProfile? mine;
  final int grade;
  final String course;
  final void Function(int grade, String course) onPick;
  const _ClassList({
    required this.info,
    required this.mine,
    required this.grade,
    required this.course,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    bool isHome(int g, String c) => mine?.homeroomGrade == g && mine?.homeroomCourse == c;
    final classes = [
      for (final g in info.grades)
        for (final c in info.courses) (grade: g, course: c),
    ]..sort((a, b) => (isHome(b.grade, b.course) ? 1 : 0) - (isHome(a.grade, a.course) ? 1 : 0));
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 16),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: Text(AppStrings.t('teacher_classes'),
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
        ),
        for (final k in classes)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Material(
              color: k.grade == grade && k.course == course ? AppColors.glassBg : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => onPick(k.grade, k.course),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${AppStrings.t('teacher_grade', {'n': k.grade})}・${k.course}',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: k.grade == grade && k.course == course ? FontWeight.w800 : FontWeight.w500,
                            color: k.grade == grade && k.course == course ? AppColors.accentText : AppColors.textPrimary,
                          ),
                        ),
                      ),
                      if (isHome(k.grade, k.course))
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.warningLight,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(AppStrings.t('teacher_homeroom_badge'),
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.warning)),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  final String text;
  const _Message(this.text);

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(text,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
        ),
      );
}

class _WeekBar extends StatelessWidget {
  final DateTime weekStart;
  final bool isCurrent;
  final VoidCallback onPrevious, onNext, onToday;
  const _WeekBar({
    required this.weekStart,
    required this.isCurrent,
    required this.onPrevious,
    required this.onNext,
    required this.onToday,
  });

  @override
  Widget build(BuildContext context) {
    final end = weekStart.add(const Duration(days: 4));
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
            onPressed: onPrevious,
            icon: const Icon(Icons.chevron_left),
            tooltip: AppStrings.t('teacher_prev_week')),
        Text('${weekStart.month}/${weekStart.day} - ${end.month}/${end.day}',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
        IconButton(
            onPressed: onNext,
            icon: const Icon(Icons.chevron_right),
            tooltip: AppStrings.t('teacher_next_week')),
        // Hidden on this week, so the bar doesn't jump while browsing it.
        Visibility.maintain(
          visible: !isCurrent,
          child: TextButton(onPressed: onToday, child: Text(AppStrings.t('teacher_today'))),
        ),
      ],
    );
  }
}

/// Five day columns side by side on wide screens, stacked on phones.
class _WeekView extends StatelessWidget {
  final SchoolInfo info;
  final Map<String, SchoolDay> week;
  final DateTime weekStart, today;
  final void Function(DateTime date, SchoolPeriod period, SchoolSlot? slot) onTap;
  const _WeekView({
    required this.info,
    required this.week,
    required this.weekStart,
    required this.today,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final dates = [
      for (var i = 0; i < 5; i++) DateTime(weekStart.year, weekStart.month, weekStart.day + i)
    ];
    SchoolSlot? slotAt(DateTime d, SchoolPeriod p) =>
        week[DateHelper.dayKey(d)]?.slots.where((s) => s.period == p.key).firstOrNull;

    return LayoutBuilder(builder: (context, constraints) {
    if (constraints.maxWidth < 640) {
      return Column(children: [
        for (var i = 0; i < 5; i++)
          _DayColumn(
            info: info,
            date: dates[i],
            weekday: _kWeekdays[i],
            slotAt: slotAt,
            today: today,
            onTap: onTap,
          ),
      ]);
    }

    // Wide: periods as rows so every lesson lines up with its 限 label.
    const gutter = 84.0;
    return Column(
      children: [
        Row(children: [
          const SizedBox(width: gutter),
          for (var i = 0; i < 5; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
                child: _DayLabel(date: dates[i], weekday: _kWeekdays[i], today: today),
              ),
            ),
        ]),
        for (final p in info.periods)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: gutter,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 6, right: 6),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(p.label,
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.accentText)),
                      Text(schoolPeriodTimes(p), style: TextStyle(fontSize: 10, color: AppColors.textSecondary)),
                    ]),
                  ),
                ),
                for (final d in dates)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: _SlotTile(
                        period: p,
                        slot: slotAt(d, p),
                        compact: true,
                        past: d.isBefore(today),
                        onTap: () => onTap(d, p, slotAt(d, p)),
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
    });
  }
}

class _DayLabel extends StatelessWidget {
  final DateTime date, today;
  final String weekday;
  const _DayLabel({required this.date, required this.weekday, required this.today});

  @override
  Widget build(BuildContext context) => Text(
        '${date.month}/${date.day}（${DateHelper.localizedWeekday(weekday)}）',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w800,
          color: date == today ? AppColors.accentText : AppColors.textPrimary,
        ),
      );
}

class _DayColumn extends StatelessWidget {
  final SchoolInfo info;
  final DateTime date, today;
  final String weekday;
  final SchoolSlot? Function(DateTime, SchoolPeriod) slotAt;
  final void Function(DateTime date, SchoolPeriod period, SchoolSlot? slot) onTap;
  const _DayColumn({
    required this.info,
    required this.date,
    required this.weekday,
    required this.slotAt,
    required this.today,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
            child: _DayLabel(date: date, weekday: weekday, today: today),
          ),
          for (final p in info.periods)
            _SlotTile(
              period: p,
              slot: slotAt(date, p),
              compact: false,
              past: date.isBefore(today),
              onTap: () => onTap(date, p, slotAt(date, p)),
            ),
        ],
      );
}

class _SlotTile extends StatelessWidget {
  final SchoolPeriod period;
  final SchoolSlot? slot;
  final bool compact, past;
  final VoidCallback onTap;
  const _SlotTile({
    required this.period,
    required this.slot,
    required this.compact,
    required this.past,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final s = slot;
    final tile = Semantics(
      button: true,
      child: InkWell(
        onTap: past ? () => _toast(context, AppStrings.t('teacher_past_note'), error: true) : onTap,
        borderRadius: BorderRadius.circular(compact ? 10 : 18),
        child: s != null
            ? SchoolSlotCard(slot: s, period: period, compact: compact)
            : Container(
                margin: EdgeInsets.only(bottom: compact ? 4 : 14),
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: compact ? 10 : 16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(compact ? 10 : 18),
                  border: Border.all(color: AppColors.cardStroke),
                ),
                child: Row(
                  children: [
                    Icon(Icons.add, size: 16, color: AppColors.textMuted),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        compact
                            ? AppStrings.t('teacher_empty_slot')
                            : '${period.label} · ${AppStrings.t('teacher_empty_slot')}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
    return past ? Opacity(opacity: 0.5, child: tile) : tile;
  }
}

/// Live 既読 count of the announcement already published for this slot.
class _ReadCount extends ConsumerStatefulWidget {
  final int grade;
  final String course, period;
  final DateTime date;
  const _ReadCount({required this.grade, required this.course, required this.date, required this.period});

  @override
  ConsumerState<_ReadCount> createState() => _ReadCountState();
}

class _ReadCountState extends ConsumerState<_ReadCount> {
  Stream<int>? _count;

  @override
  void initState() {
    super.initState();
    final domain = ref.read(schoolDomainProvider);
    if (domain != null) {
      _count = ref.read(schoolRepositoryProvider).watchReadCount(
          domain: domain, grade: widget.grade, course: widget.course, date: widget.date, period: widget.period);
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<int>(
        stream: _count,
        builder: (_, snap) => Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Row(
            children: [
              Icon(Icons.done_all_rounded, size: 16, color: AppColors.accentText),
              const SizedBox(width: 6),
              Text(AppStrings.t('teacher_read_count', {'n': snap.data ?? 0}),
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.accentText)),
            ],
          ),
        ),
      );
}

/// Public entry point to open the override sheet for a slot (§9.2-2).
Future<void> showOverrideSheet(
  BuildContext context, {
  required int grade,
  required String course,
  required DateTime date,
  required SchoolPeriod period,
  required SchoolSlot? slot,
  SchoolOverrideKind? initialKind,
  VoidCallback? onDone,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.bgLayer,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => _OverrideSheet(
      grade: grade,
      course: course,
      date: date,
      period: period,
      slot: slot,
      initialKind: initialKind,
      onDone: onDone,
    ),
  );
}

/// 休講・教室変更・補講・メモ input for one slot (§9.2-2).
class _OverrideSheet extends StatefulWidget {
  final int grade;
  final String course;
  final DateTime date;
  final SchoolPeriod period;
  final SchoolSlot? slot;
  final SchoolOverrideKind? initialKind;

  /// Desktop side panel: called after a publish instead of popping a sheet.
  final VoidCallback? onDone;
  const _OverrideSheet({
    super.key,
    required this.grade,
    required this.course,
    required this.date,
    required this.period,
    required this.slot,
    this.initialKind,
    this.onDone,
  });

  @override
  State<_OverrideSheet> createState() => _OverrideSheetState();
}

class _OverrideSheetState extends State<_OverrideSheet> {
  late SchoolOverrideKind _kind = widget.initialKind ??
      (widget.slot == null ? SchoolOverrideKind.makeup : SchoolOverrideKind.cancelled);
  final _room = TextEditingController();
  final _subject = TextEditingController();
  final _teacher = TextEditingController();
  final _note = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // The preview below repeats the typed room/subject live.
    for (final c in [_room, _subject, _note]) {
      c.addListener(() => setState(() {}));
    }
  }

  /// Mirrors the server's push body (describeOverride in overrides.js), which
  /// is Japanese-only, so the preview is too.
  String _previewLine() {
    final d = widget.date;
    final slot = widget.slot;
    final head = const {
      SchoolOverrideKind.cancelled: '【休講】',
      SchoolOverrideKind.room: '【教室変更】',
      SchoolOverrideKind.makeup: '【補講】',
    }[_kind] ?? '';
    final subject = _kind == SchoolOverrideKind.makeup ? _subject.text.trim() : (slot?.subject ?? '');
    final oldRoom = (slot?.room.isNotEmpty ?? false) ? slot!.room : '—';
    final tail = _kind == SchoolOverrideKind.room ? '：$oldRoom → ${_room.text.trim()}' : '';
    final note = _note.text.trim().isEmpty ? '' : '（${_note.text.trim()}）';
    return '$head${d.month}/${d.day}（${_kWeekdays[d.weekday - 1]}）${widget.period.label} $subject$tail$note';
  }

  @override
  void dispose() {
    _room.dispose();
    _subject.dispose();
    _teacher.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _send(String kind) async {
    if (_busy) return;
    // Same required fields as validateOverride on the server, checked here so
    // the teacher sees a clear message instead of the server's English one.
    final missing = switch (kind) {
      'room' when _room.text.trim().isEmpty => 'teacher_field_room',
      'makeup' when _subject.text.trim().isEmpty => 'teacher_field_subject',
      'memo' when _note.text.trim().isEmpty => 'teacher_field_memo',
      _ => null,
    };
    if (missing != null) {
      _toast(context, AppStrings.t('teacher_field_required', {'field': AppStrings.t(missing)}), error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final res = await FunctionsService.callable('publishSchoolOverride').call<Map>({
        'grade': widget.grade,
        'course': widget.course,
        'date': DateHelper.dayKey(widget.date),
        'period': widget.period.key,
        'kind': kind,
        'subject': _subject.text,
        'teacher': _teacher.text,
        'room': _room.text,
        'note': _note.text,
      });
      if (!mounted) return;
      final pushed = (res.data['pushed'] as num?)?.toInt() ?? 0;
      _toast(context,
          kind == 'clear' ? AppStrings.t('teacher_cleared') : AppStrings.t('teacher_published', {'n': pushed}));
      if (widget.onDone != null) {
        widget.onDone!();
      } else {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _toast(context, _callError(e), error: true);
    }
  }

  String _kindLabel(SchoolOverrideKind k) => AppStrings.t('teacher_kind_${k.name}');

  Widget _field(TextEditingController c, String labelKey, {int maxLength = 100}) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: TextField(
          controller: c,
          maxLength: maxLength,
          decoration: InputDecoration(labelText: AppStrings.t(labelKey), counterText: ''),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final slot = widget.slot;
    final kinds = slot == null
        ? const [SchoolOverrideKind.makeup]
        : SchoolOverrideKind.values;
    final d = widget.date;
    final weekday = DateHelper.localizedWeekday(_kWeekdays[d.weekday - 1]);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${AppStrings.t('teacher_grade', {'n': widget.grade})}・${widget.course}  '
              '${d.month}/${d.day}（$weekday）${widget.period.label}',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 4),
            Text(
              slot?.subject.isNotEmpty ?? false ? slot!.subject : AppStrings.t('teacher_empty_slot'),
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final k in kinds)
                  ChoiceChip(
                    label: Text(_kindLabel(k)),
                    selected: k == _kind,
                    onSelected: (_) => setState(() => _kind = k),
                  ),
              ],
            ),
            if (_kind == SchoolOverrideKind.room) _field(_room, 'teacher_field_room'),
            if (_kind == SchoolOverrideKind.makeup) ...[
              _field(_subject, 'teacher_field_subject'),
              _field(_teacher, 'teacher_field_teacher'),
              _field(_room, 'teacher_field_room'),
            ],
            _field(_note, _kind == SchoolOverrideKind.memo ? 'teacher_field_memo' : 'teacher_field_note',
                maxLength: 200),
            const SizedBox(height: 16),
            Text(AppStrings.t('teacher_preview_title'),
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.cardSurface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.cardStroke),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_previewLine(),
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                  const SizedBox(height: 4),
                  Text(
                    AppStrings.t(_kind == SchoolOverrideKind.memo ? 'teacher_preview_memo' : 'teacher_preview_push'),
                    style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
            if (slot?.byTeacher ?? false)
              _ReadCount(grade: widget.grade, course: widget.course, date: widget.date, period: widget.period.key),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _busy ? null : () => _send(_kind.name),
              child: Text(_kind == SchoolOverrideKind.memo
                  ? AppStrings.t('teacher_save_memo')
                  : AppStrings.t('teacher_publish')),
            ),
            if (slot?.byTeacher ?? false) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: _busy ? null : () => _send('clear'),
                child: Text(AppStrings.t('teacher_clear'), style: const TextStyle(color: AppColors.danger)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Admin-only teacher registration (§5.3) plus a link to the file-link page.
class _TeacherRegistry extends StatefulWidget {
  final SchoolInfo info;
  const _TeacherRegistry({required this.info});

  @override
  State<_TeacherRegistry> createState() => _TeacherRegistryState();
}

class _TeacherRegistryState extends State<_TeacherRegistry> {
  final _email = TextEditingController();
  final _name = TextEditingController();
  ({int grade, String course})? _homeroom;
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _call(String fn, Map<String, Object?> data, String okKey) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await FunctionsService.callable(fn).call(data);
      if (!mounted) return;
      _toast(context, AppStrings.t(okKey));
    } catch (e) {
      if (mounted) _toast(context, _callError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add() async {
    if (_email.text.trim().isEmpty) return;
    final h = _homeroom;
    await _call('setSchoolTeacher', {
      'email': _email.text.trim(),
      'add': true,
      'name': _name.text.trim(),
      'homeroom': h == null ? null : {'grade': h.grade, 'course': h.course},
    }, 'teacher_admin_added');
    if (!mounted) return;
    _email.clear();
    _name.clear();
    setState(() => _homeroom = null);
  }

  /// Tapping a registered teacher loads them into the form to edit.
  void _edit(String email, TeacherProfile? p) => setState(() {
        _email.text = email;
        _name.text = p?.name ?? '';
        final g = p?.homeroomGrade, c = p?.homeroomCourse;
        _homeroom = g != null && c != null ? (grade: g, course: c) : null;
      });

  String _cls(int grade, String course) => '${AppStrings.t('teacher_grade', {'n': grade})}・$course';

  @override
  Widget build(BuildContext context) {
    final info = widget.info;
    final teachers = info.teachers;
    final classes = [
      for (final g in info.grades)
        for (final c in info.courses) (grade: g, course: c),
    ];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.cardStroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(AppStrings.t('teacher_admin_section'),
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
          const SizedBox(height: 12),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            maxLength: 200,
            decoration: InputDecoration(
              hintText: AppStrings.t('teacher_admin_hint', {'domain': info.domain}),
              counterText: '',
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _name,
            maxLength: 50,
            decoration: InputDecoration(hintText: AppStrings.t('teacher_admin_name_hint'), counterText: ''),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<({int grade, String course})?>(
                  // Keyed by value: the form field keeps its own state otherwise.
                  key: ValueKey(_homeroom),
                  initialValue: _homeroom,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: AppStrings.t('teacher_admin_homeroom')),
                  items: [
                    DropdownMenuItem(value: null, child: Text(AppStrings.t('teacher_admin_homeroom_none'))),
                    for (final c in classes) DropdownMenuItem(value: c, child: Text(_cls(c.grade, c.course))),
                  ],
                  onChanged: (v) => setState(() => _homeroom = v),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _busy ? null : _add,
                child: Text(AppStrings.t('teacher_admin_add')),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (teachers.isEmpty)
            Text(AppStrings.t('teacher_admin_empty'), style: TextStyle(fontSize: 12, color: AppColors.textMuted))
          else
            for (final t in teachers)
              Builder(builder: (context) {
                final p = info.profileOf(t);
                final g = p?.homeroomGrade, c = p?.homeroomCourse;
                final sub = [
                  if (p?.name.isNotEmpty ?? false) p!.name,
                  if (g != null && c != null) AppStrings.t('teacher_admin_homeroom_of', {'cls': _cls(g, c)}),
                ].join(' · ');
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  onTap: () => _edit(t, p),
                  leading: Icon(Icons.person_outline, color: AppColors.textSecondary),
                  title: Text(t, style: TextStyle(fontSize: 13, color: AppColors.textPrimary)),
                  subtitle: sub.isEmpty ? null : Text(sub, style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  trailing: IconButton(
                    tooltip: AppStrings.t('teacher_admin_remove'),
                    icon: const Icon(Icons.delete_outline, color: AppColors.danger),
                    onPressed: _busy ? null : () => _call('setSchoolTeacher', {'email': t, 'add': false}, 'teacher_admin_removed'),
                  ),
                );
              }),
          const Divider(height: 24),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: info.allowStudentEdit,
            onChanged: _busy
                ? null
                : (v) => _call('setSchoolStudentEdit', {'allow': v}, v ? 'teacher_admin_allow_student_edit' : 'teacher_admin_allow_student_edit_sub'),
            title: Text(AppStrings.t('teacher_admin_allow_student_edit'),
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            subtitle: Text(AppStrings.t('teacher_admin_allow_student_edit_sub'),
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ),
          const Divider(height: 24),
          TextButton.icon(
            onPressed: () => launchUrl(Uri.parse(_kLinkPage), mode: LaunchMode.externalApplication),
            icon: const Icon(Icons.open_in_new, size: 16),
            label: Text(AppStrings.t('teacher_link_page')),
          ),
        ],
      ),
    );
  }
}
