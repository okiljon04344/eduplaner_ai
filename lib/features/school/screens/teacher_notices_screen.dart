import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toastification/toastification.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/services/functions_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/responsive.dart';
import '../../../shared/widgets/app_sheet.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../models/school.dart';
import '../models/school_notice.dart';
import '../school_providers.dart';
import '../widgets/school_notices_card.dart';
import '../widgets/teacher_scaffold.dart';

const _kMaxTitle = 60;
const _kMaxBody = 1000;

void _toast(BuildContext context, String msg, {bool error = false}) => toastification.show(
      context: context,
      type: error ? ToastificationType.error : ToastificationType.success,
      style: ToastificationStyle.flat,
      title: Text(msg),
      autoCloseDuration: const Duration(seconds: 3),
    );

String _callError(Object e) => switch (e) {
      FirebaseFunctionsException(code: 'permission-denied') => AppStrings.t('notice_no_permission'),
      FirebaseFunctionsException(code: 'invalid-argument', :final message?) => message,
      FirebaseFunctionsException() => FunctionsService.describeError(e),
      _ => AppStrings.t('notice_failed'),
    };

/// "2年 全コース" / "2年 観光".
///
/// UZ: "2年 全コース" / "2年 観光".
String noticeTargetLabel(int grade, String? course) => course == null
    ? AppStrings.t('notice_target_grade', {'grade': grade})
    : AppStrings.t('notice_target_class', {'grade': grade, 'course': course});

/// お知らせボード for teachers (§9.2-4): send a notice to a class or a whole
/// grade, see sent notices with their 既読 count, delete your own.
///
/// UZ: O'qituvchilar uchun お知らせボード (§9.2-4): sinfga yoki butun bir bosqichga e'lon
/// yuborish, yuborilgan e'lonlarni ularning 既読 soni bilan ko'rish, o'zingiznikini o'chirish.
class TeacherNoticesScreen extends ConsumerWidget {
  const TeacherNoticesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(schoolInfoProvider).valueOrNull;
    final role = ref.watch(schoolRoleProvider);
    final notices = ref.watch(schoolNoticesProvider).valueOrNull ?? const <SchoolNotice>[];
    final isDesktop = MediaQuery.sizeOf(context).width >= 1100;

    final sentList = <Widget>[
      Text(AppStrings.t('notice_sent_list'),
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
      const SizedBox(height: 8),
      if (notices.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Text(AppStrings.t('notice_empty'),
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
        ),
      for (final n in notices)
        _SentNotice(
          notice: n,
          canDelete: role.admin || n.createdBy == FirebaseAuth.instance.currentUser?.uid,
        ),
    ];

    Widget body;
    if (info == null || !role.teacher) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(AppStrings.t('teacher_no_access'),
              textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
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
                  AppStrings.t('notice_board_title'),
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
                          child: _NoticeForm(info: info),
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
            _NoticeForm(info: info),
            const SizedBox(height: 24),
            ...sentList,
          ],
        ),
      );
    }

    return TeacherScaffold(
      section: TeacherSection.notices,
      title: AppStrings.t('notice_board_title'),
      body: body,
    );
  }
}

class _NoticeForm extends ConsumerStatefulWidget {
  final SchoolInfo info;

  /// A sent notice to correct (訂正); null composes a new one.
  ///
  /// UZ: Tahrirlash (訂正) uchun yuborilgan e'lon; null bo'lsa yangisini tuzadi.
  final SchoolNotice? existing;
  const _NoticeForm({required this.info, this.existing});

  @override
  ConsumerState<_NoticeForm> createState() => _NoticeFormState();
}

class _NoticeFormState extends ConsumerState<_NoticeForm> {
  late final _title = TextEditingController(text: widget.existing?.title);
  late final _body = TextEditingController(text: widget.existing?.body);
  late final _link = TextEditingController(text: widget.existing?.link);
  late int _grade = widget.existing?.grade ?? (widget.info.grades.isEmpty ? 1 : widget.info.grades.first);
  late String? _course = widget.existing?.course; // null = whole grade
  late bool _urgent = widget.existing?.urgent ?? false;
  late NoticeCategory _category = widget.existing?.category ?? NoticeCategory.contact;
  late String _subject = widget.existing?.subject ?? '';
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _link.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_busy) return;
    final title = _title.text.trim();
    if (title.isEmpty) {
      _toast(context, AppStrings.t('teacher_field_required', {'field': AppStrings.t('notice_field_title')}), error: true);
      return;
    }
    final link = _link.text.trim();
    if (link.isNotEmpty && !link.startsWith('https://')) {
      _toast(context, AppStrings.t('notice_link_invalid'), error: true);
      return;
    }
    setState(() => _busy = true);
    final existing = widget.existing;
    try {
      final res = await FunctionsService.callable(existing == null ? 'publishSchoolNotice' : 'updateSchoolNotice')
          .call<Map>({
        if (existing != null) 'id': existing.id,
        'grade': _grade,
        'course': _course,
        'title': title,
        'body': _body.text.trim(),
        'priority': _urgent ? 'urgent' : 'normal',
        'category': _category.name,
        'subject': _course == null ? '' : _subject,
        'link': link,
      });
      if (!mounted) return;
      if (existing != null) {
        _toast(context, AppStrings.t('notice_updated'));
        Navigator.of(context).pop();
        return;
      }
      _toast(context, AppStrings.t('notice_sent', {'n': (res.data['pushed'] as num?)?.toInt() ?? 0}));
      _title.clear();
      _body.clear();
      _link.clear();
      setState(() {
        _urgent = false;
        _subject = '';
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
    final editing = widget.existing != null;
    // Subject tags come from the class's timetable, never typed, so a tag
    // always matches the lesson a student taps.
    // UZ: Fan teglari sinfning dars jadvalidan olinadi, hech qachon qo'lda yozilmaydi,
    // shuning uchun teg doimo talaba bosgan darsga mos keladi.
    final course = _course;
    final now = DateTime.now();
    final week = course == null
        ? const <String, SchoolDay>{}
        : ref.watch(schoolClassWeekProvider(
                (grade: _grade, course: course, weekStart: DateTime(now.year, now.month, now.day - (now.weekday - 1)))))
            .valueOrNull ??
            const <String, SchoolDay>{};
    final subjects = <String>{
      for (final d in week.values)
        for (final s in d.slots)
          if (s.subject.trim().isNotEmpty) s.subject.trim(),
      if (_subject.isNotEmpty) _subject,
    }.toList()
      ..sort();
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
          Text(AppStrings.t(editing ? 'notice_edit_title' : 'notice_new'),
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            initialValue: selected < 0 ? null : selected,
            decoration: InputDecoration(labelText: AppStrings.t('notice_target')),
            items: [
              for (var i = 0; i < targets.length; i++)
                DropdownMenuItem(value: i, child: Text(noticeTargetLabel(targets[i].grade, targets[i].course))),
            ],
            // 訂正 keeps the addressed class: another class would need its own push.
            // UZ: 訂正 murojaat qilingan sinfni saqlab qoladi: boshqa sinf uchun o'zining push xabari kerak bo'ladi.
            onChanged: _busy || editing
                ? null
                : (i) {
                    if (i == null) return;
                    setState(() {
                      _grade = targets[i].grade;
                      _course = targets[i].course;
                      _subject = '';
                    });
                  },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<NoticeCategory>(
            initialValue: _category,
            decoration: InputDecoration(labelText: AppStrings.t('notice_field_category')),
            items: [for (final c in NoticeCategory.values) DropdownMenuItem(value: c, child: Text(c.label))],
            onChanged: _busy ? null : (c) => setState(() => _category = c ?? _category),
          ),
          if (subjects.isNotEmpty) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: ValueKey('subject-$_grade-$_course-${subjects.length}'),
              initialValue: _subject,
              isExpanded: true,
              decoration: InputDecoration(labelText: AppStrings.t('notice_field_subject')),
              items: [
                DropdownMenuItem(value: '', child: Text(AppStrings.t('notice_subject_none'))),
                for (final s in subjects) DropdownMenuItem(value: s, child: Text(s, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: _busy ? null : (s) => setState(() => _subject = s ?? ''),
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _title,
            maxLength: _kMaxTitle,
            enabled: !_busy,
            decoration: InputDecoration(labelText: AppStrings.t('notice_field_title')),
          ),
          TextField(
            controller: _body,
            maxLength: _kMaxBody,
            enabled: !_busy,
            minLines: 3,
            maxLines: 8,
            decoration: InputDecoration(labelText: AppStrings.t('notice_field_body'), alignLabelWithHint: true),
          ),
          TextField(
            controller: _link,
            maxLength: 490,
            enabled: !_busy,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: InputDecoration(labelText: AppStrings.t('notice_field_link'), counterText: ''),
          ),
          Material(
            type: MaterialType.transparency,
            child: SwitchListTile.adaptive(
              value: _urgent,
              onChanged: _busy ? null : (v) => setState(() => _urgent = v),
              contentPadding: EdgeInsets.zero,
              activeThumbColor: AppColors.danger,
              title: Text(AppStrings.t('notice_urgent_switch'),
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              subtitle: Text(AppStrings.t('notice_urgent_hint'),
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 48,
            child: FilledButton.icon(
              onPressed: _busy ? null : _send,
              icon: _busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onPrimary))
                  : const Icon(Icons.send_rounded),
              label: Text(AppStrings.t('notice_send')),
            ),
          ),
        ],
      ),
    );
  }
}

class _SentNotice extends ConsumerWidget {
  final SchoolNotice notice;
  final bool canDelete;
  const _SentNotice({required this.notice, required this.canDelete});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reads = ref.watch(noticeReadCountProvider(notice.id)).valueOrNull ?? 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardStroke),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  if (notice.urgent) ...[const UrgentBadge(), const SizedBox(width: 6)],
                  Expanded(
                    child: Text(notice.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                  ),
                ]),
                const SizedBox(height: 4),
                Text(
                  [noticeTargetLabel(notice.grade, notice.course), noticeTags(notice), noticeTime(notice.createdAt)]
                      .where((s) => s.isNotEmpty)
                      .join(' · '),
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 4),
                Text(AppStrings.t('teacher_read_count', {'n': reads}),
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.accentText)),
              ],
            ),
          ),
          if (canDelete)
            IconButton(
              tooltip: AppStrings.t('common_edit'),
              icon: Icon(Icons.edit_outlined, color: AppColors.textMuted),
              onPressed: () => _edit(context, ref),
            ),
          if (canDelete)
            IconButton(
              tooltip: AppStrings.t('common_delete'),
              icon: Icon(Icons.delete_outline_rounded, color: AppColors.textMuted),
              onPressed: () => _delete(context),
            ),
        ],
      ),
    );
  }

  void _edit(BuildContext context, WidgetRef ref) {
    final info = ref.read(schoolInfoProvider).valueOrNull;
    if (info == null) return;
    showAppSheet<void>(
      context,
      (context) => SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(12, 12, 12, 12 + MediaQuery.viewInsetsOf(context).bottom),
          child: _NoticeForm(info: info, existing: notice),
        ),
      ),
    );
  }

  Future<void> _delete(BuildContext context) async {
    final ok = await showConfirmDialog(context,
        title: AppStrings.t('common_delete'), message: AppStrings.t('notice_delete_confirm'));
    if (!ok || !context.mounted) return;
    try {
      await FunctionsService.callable('deleteSchoolNotice').call({'id': notice.id});
      if (context.mounted) _toast(context, AppStrings.t('teacher_admin_removed'));
    } catch (e) {
      if (context.mounted) _toast(context, _callError(e), error: true);
    }
  }
}
