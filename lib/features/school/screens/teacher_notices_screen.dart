import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toastification/toastification.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/services/functions_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/responsive.dart';
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
String noticeTargetLabel(int grade, String? course) => course == null
    ? AppStrings.t('notice_target_grade', {'grade': grade})
    : AppStrings.t('notice_target_class', {'grade': grade, 'course': course});

/// お知らせボード for teachers (§9.2-4): send a notice to a class or a whole
/// grade, see sent notices with their 既読 count, delete your own.
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

class _NoticeForm extends StatefulWidget {
  final SchoolInfo info;
  const _NoticeForm({required this.info});

  @override
  State<_NoticeForm> createState() => _NoticeFormState();
}

class _NoticeFormState extends State<_NoticeForm> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  late int _grade = widget.info.grades.isEmpty ? 1 : widget.info.grades.first;
  String? _course; // null = whole grade
  bool _urgent = false;
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_busy) return;
    final title = _title.text.trim();
    if (title.isEmpty) {
      _toast(context, AppStrings.t('teacher_field_required', {'field': AppStrings.t('notice_field_title')}), error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final res = await FunctionsService.callable('publishSchoolNotice').call<Map>({
        'grade': _grade,
        'course': _course,
        'title': title,
        'body': _body.text.trim(),
        'priority': _urgent ? 'urgent' : 'normal',
      });
      if (!mounted) return;
      _toast(context, AppStrings.t('notice_sent', {'n': (res.data['pushed'] as num?)?.toInt() ?? 0}));
      _title.clear();
      _body.clear();
      setState(() {
        _urgent = false;
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
          Text(AppStrings.t('notice_new'),
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            initialValue: selected < 0 ? null : selected,
            decoration: InputDecoration(labelText: AppStrings.t('notice_target')),
            items: [
              for (var i = 0; i < targets.length; i++)
                DropdownMenuItem(value: i, child: Text(noticeTargetLabel(targets[i].grade, targets[i].course))),
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
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
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
                  [noticeTargetLabel(notice.grade, notice.course), noticeTime(notice.createdAt)]
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
              tooltip: AppStrings.t('common_delete'),
              icon: Icon(Icons.delete_outline_rounded, color: AppColors.textMuted),
              onPressed: () => _delete(context),
            ),
        ],
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
