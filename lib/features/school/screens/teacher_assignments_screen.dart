import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toastification/toastification.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/services/functions_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_helper.dart';
import '../../../core/utils/responsive.dart';
import '../../../shared/widgets/app_sheet.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../assignments/models/assignment_model.dart';
import '../models/school.dart';
import '../models/school_assignment.dart';
import '../school_providers.dart';
import '../widgets/teacher_scaffold.dart';

const _kMaxSubject = 100;
const _kMaxTitle = 200;
const _kMaxDescription = 2000;

void _toast(BuildContext context, String msg, {bool error = false}) => toastification.show(
      context: context,
      type: error ? ToastificationType.error : ToastificationType.success,
      style: ToastificationStyle.flat,
      title: Text(msg),
      autoCloseDuration: const Duration(seconds: 3),
    );

String _callError(Object e) => switch (e) {
      FirebaseFunctionsException(code: 'permission-denied') => AppStrings.t('sas_no_permission'),
      FirebaseFunctionsException(code: 'invalid-argument', :final message?) => message,
      FirebaseFunctionsException() => FunctionsService.describeError(e),
      _ => AppStrings.t('sas_publish_failed'),
    };

/// "2年 全コース" / "2年 観光".
///
/// UZ: "2年 全コース" / "2年 観光".
String assignmentTargetLabel(int grade, String? course) => course == null
    ? AppStrings.t('notice_target_grade', {'grade': grade})
    : AppStrings.t('notice_target_class', {'grade': grade, 'course': course});

/// 課題配布 screen for teachers (§9.2-3): hand out an assignment to a class or
/// grade, monitor student progress, and delete previously distributed assignments.
///
/// UZ: O'qituvchilar uchun 課題配布 ekrani (§9.2-3): sinf yoki bosqichga topshiriq topshirish,
/// o'quvchilar natijalarini kuzatish va avval tarqatilgan topshiriqlarni o'chirish.
class TeacherAssignmentsScreen extends ConsumerWidget {
  const TeacherAssignmentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(schoolInfoProvider).valueOrNull;
    final role = ref.watch(schoolRoleProvider);
    final assignments = ref.watch(schoolAssignmentsProvider).valueOrNull ?? const <SchoolAssignment>[];
    final isDesktop = MediaQuery.sizeOf(context).width >= 1100;

    final sentList = <Widget>[
      Text(
        AppStrings.t('sas_sent_list'),
        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
      ),
      const SizedBox(height: 8),
      if (assignments.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Text(
            AppStrings.t('sas_empty_list'),
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
        ),
      for (final a in assignments)
        _DistributedAssignmentCard(
          assignment: a,
          canDelete: role.admin || a.createdBy == FirebaseAuth.instance.currentUser?.uid,
        ),
    ];

    Widget body;
    if (info == null || !role.teacher) {
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
      body = Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppStrings.t('sas_screen_title'),
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 460,
                        child: SingleChildScrollView(
                          child: _AssignmentForm(info: info),
                        ),
                      ),
                      const SizedBox(width: 24),
                      Expanded(
                        child: ListView(
                          children: sentList,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } else {
      body = ResponsiveBody(
        maxWidth: 720,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            _AssignmentForm(info: info),
            const SizedBox(height: 24),
            ...sentList,
          ],
        ),
      );
    }

    return TeacherScaffold(
      section: TeacherSection.assignments,
      title: AppStrings.t('sas_screen_title'),
      body: body,
    );
  }
}

class _AssignmentForm extends StatefulWidget {
  final SchoolInfo info;
  const _AssignmentForm({required this.info});

  @override
  State<_AssignmentForm> createState() => _AssignmentFormState();
}

class _AssignmentFormState extends State<_AssignmentForm> {
  final _subject = TextEditingController();
  final _title = TextEditingController();
  final _description = TextEditingController();

  late int _grade = widget.info.grades.isEmpty ? 1 : widget.info.grades.first;
  String? _course; // null = whole grade
  late DateTime _dueDay = DateTime.now().add(const Duration(days: 7));
  bool _busy = false;

  @override
  void dispose() {
    _subject.dispose();
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickDueDate() async {
    final now = DateTime.now();
    final initial = _dueDay.isBefore(now) ? now : _dueDay;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365)),
      locale: Locale(AppStrings.currentLocale),
    );
    if (picked != null) {
      setState(() => _dueDay = picked);
    }
  }

  Future<void> _publish() async {
    if (_busy) return;
    final subject = _subject.text.trim();
    final title = _title.text.trim();
    if (subject.isEmpty) {
      _toast(context, AppStrings.t('val_subject_required'), error: true);
      return;
    }
    if (title.isEmpty) {
      _toast(context, AppStrings.t('val_assign_title_required'), error: true);
      return;
    }
    setState(() => _busy = true);

    // dueAt = that day 23:59 local as epoch ms
    // UZ: dueAt = o'sha kunning mahalliy 23:59 vaqti epoch ms formatida
    final dueAtMs = DateTime(_dueDay.year, _dueDay.month, _dueDay.day, 23, 59).millisecondsSinceEpoch;

    try {
      final res = await FunctionsService.callable('publishSchoolAssignment').call<Map>({
        'grade': _grade,
        'course': _course,
        'subject': subject,
        'title': title,
        'description': _description.text.trim(),
        'dueAt': dueAtMs,
      });
      if (!mounted) return;
      final n = (res.data['students'] as num?)?.toInt() ?? 0;
      _toast(context, AppStrings.t('sas_published_toast', {'n': n}));
      _subject.clear();
      _title.clear();
      _description.clear();
      setState(() {
        _dueDay = DateTime.now().add(const Duration(days: 7));
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _toast(context, _callError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final targets = <({int grade, String? course})>[
      for (final g in widget.info.grades) ...[
        (grade: g, course: null),
        for (final c in widget.info.courses) (grade: g, course: c),
      ],
    ];
    final selected = targets.indexWhere((t) => t.grade == _grade && t.course == _course);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.cardStroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            AppStrings.t('sas_new_assignment'),
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            initialValue: selected < 0 ? null : selected,
            decoration: InputDecoration(labelText: AppStrings.t('notice_target')),
            items: [
              for (var i = 0; i < targets.length; i++)
                DropdownMenuItem(value: i, child: Text(assignmentTargetLabel(targets[i].grade, targets[i].course))),
            ],
            onChanged: _busy
                ? null
                : (i) {
                    if (i == null) return;
                    setState(() {
                      _grade = targets[i].grade;
                      _course = targets[i].course;
                    });
                  },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _subject,
            maxLength: _kMaxSubject,
            enabled: !_busy,
            decoration: InputDecoration(labelText: AppStrings.t('fld_subject')),
          ),
          TextField(
            controller: _title,
            maxLength: _kMaxTitle,
            enabled: !_busy,
            decoration: InputDecoration(labelText: AppStrings.t('fld_assign_title')),
          ),
          TextField(
            controller: _description,
            maxLength: _kMaxDescription,
            enabled: !_busy,
            minLines: 3,
            maxLines: 6,
            decoration: InputDecoration(
              labelText: AppStrings.t('fld_memo'),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 4),
          InkWell(
            onTap: _busy ? null : _pickDueDate,
            borderRadius: BorderRadius.circular(12),
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: AppStrings.t('sas_due_label'),
                suffixIcon: const Icon(Icons.calendar_today_outlined, size: 20),
              ),
              child: Text(
                '${DateHelper.formatJapaneseDate(_dueDay)} 23:59',
                style: TextStyle(fontSize: 14, color: AppColors.textPrimary),
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 48,
            child: FilledButton.icon(
              onPressed: _busy ? null : _publish,
              icon: _busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onPrimary))
                  : const Icon(Icons.send_rounded),
              label: Text(AppStrings.t('sas_publish_btn')),
            ),
          ),
        ],
      ),
    );
  }
}

class _DistributedAssignmentCard extends ConsumerWidget {
  final SchoolAssignment assignment;
  final bool canDelete;

  const _DistributedAssignmentCard({
    required this.assignment,
    required this.canDelete,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progressList = ref.watch(assignmentProgressProvider(assignment.id)).valueOrNull ?? const [];
    final summary = summarizeProgress(progressList);
    final total = summary.total > 0 ? summary.total : assignment.total;
    final rate = total > 0 ? (summary.completed / total).clamp(0.0, 1.0) : 0.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardStroke),
      ),
      child: Material(
        type: MaterialType.transparency,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _openProgressSheet(context),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            assignment.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            [
                              assignment.subject,
                              assignmentTargetLabel(assignment.grade, assignment.course),
                              '${AppStrings.t('sas_due_label')}: ${DateHelper.formatJapaneseDate(assignment.dueAt)}',
                            ].where((s) => s.isNotEmpty).join(' · '),
                            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    if (canDelete)
                      IconButton(
                        tooltip: AppStrings.t('common_delete'),
                        icon: Icon(Icons.delete_outline_rounded, color: AppColors.textMuted),
                        onPressed: () => _delete(context),
                      ),
                  ],
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
        ),
      ),
    );
  }

  void _openProgressSheet(BuildContext context) {
    showAppSheet(
      context,
      (ctx) => _StudentProgressSheet(assignment: assignment),
      useRootNavigator: true,
    );
  }

  Future<void> _delete(BuildContext context) async {
    final ok = await showConfirmDialog(
      context,
      title: AppStrings.t('common_delete'),
      message: AppStrings.t('sas_delete_confirm'),
    );
    if (!ok || !context.mounted) return;
    try {
      await FunctionsService.callable('deleteSchoolAssignment').call({'id': assignment.id});
      if (context.mounted) _toast(context, AppStrings.t('sas_deleted_toast'));
    } catch (e) {
      if (context.mounted) _toast(context, _callError(e), error: true);
    }
  }
}

class _StudentProgressSheet extends ConsumerWidget {
  final SchoolAssignment assignment;
  const _StudentProgressSheet({required this.assignment});

  int _statusRank(String s) => switch (s) {
        'notStarted' => 0,
        'inProgress' => 1,
        'completed' => 2,
        _ => 3,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progressList = ref.watch(assignmentProgressProvider(assignment.id)).valueOrNull ?? const [];
    final summary = summarizeProgress(progressList);

    final sorted = [...progressList]..sort((a, b) {
        final cmp = _statusRank(a.status).compareTo(_statusRank(b.status));
        if (cmp != 0) return cmp;
        return a.name.compareTo(b.name);
      });

    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.35,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 12),
                decoration: BoxDecoration(
                  color: AppColors.textMuted,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 16, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppStrings.t('sas_student_list_title'),
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          assignment.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Row(
                children: [
                  Text(
                    AppStrings.t('sas_progress_summary', {
                      'done': summary.completed,
                      'total': summary.total,
                    }),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.accentText,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    AppStrings.t('sas_progress_breakdown', {
                      'inProgress': summary.inProgress,
                      'notStarted': summary.notStarted,
                    }),
                    style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
            const Divider(height: 16),
            Expanded(
              child: sorted.isEmpty
                  ? Center(
                      child: Text(
                        AppStrings.t('sas_empty_list'),
                        style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                      ),
                    )
                  : ListView.separated(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                      itemCount: sorted.length,
                      separatorBuilder: (_, __) => Divider(height: 1, color: AppColors.cardStroke),
                      itemBuilder: (context, index) {
                        final item = sorted[index];
                        final name = item.name.trim().isNotEmpty ? item.name : AppStrings.t('sas_student_fallback');
                        final statusEnum = AssignmentStatus.fromString(item.status);

                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Row(
                            children: [
                              Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(alpha: 0.12),
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Text(
                                    name.isNotEmpty ? name.characters.first : '生',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.accentText,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  name,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: statusEnum.bgColor,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: statusEnum.borderColor),
                                ),
                                child: Text(
                                  statusEnum.label,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: statusEnum.textColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}
