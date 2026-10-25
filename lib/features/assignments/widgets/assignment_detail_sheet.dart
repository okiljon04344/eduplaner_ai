import 'dart:typed_data';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toastification/toastification.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/services/functions_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_helper.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/widgets/donut_chart.dart';
import '../../../shared/widgets/star_rating.dart';
import '../../../shared/widgets/subject_pill.dart';
import '../models/assignment_model.dart';
import '../providers/assignments_provider.dart';
import 'add_edit_assignment_sheet.dart';
import 'assignment_actions.dart';

const _kSupportedSubmissionExtensions = [
  'jpg',
  'jpeg',
  'png',
  'pdf',
  'docx',
  'txt'
];
const _kMaxSubmissionBytes = 10 * 1024 * 1024;

String? _mimeTypeForExtension(String? extension) {
  switch (extension?.toLowerCase()) {
    case 'jpg':
    case 'jpeg':
      return 'image/jpeg';
    case 'png':
      return 'image/png';
    case 'pdf':
      return 'application/pdf';
    case 'docx':
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    case 'txt':
      return 'text/plain';
    default:
      return null;
  }
}

Future<void> showAssignmentDetailSheet(
    BuildContext context, WidgetRef ref, AssignmentModel assignment) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    // backgroundColor and shape come from bottomSheetTheme.
    builder: (_) => _AssignmentDetailSheet(assignment: assignment),
  );
}

class _AssignmentDetailSheet extends ConsumerStatefulWidget {
  final AssignmentModel assignment;
  const _AssignmentDetailSheet({required this.assignment});

  @override
  ConsumerState<_AssignmentDetailSheet> createState() =>
      _AssignmentDetailSheetState();
}

class _AssignmentDetailSheetState
    extends ConsumerState<_AssignmentDetailSheet> {
  /// Live slider/chip values — may run ahead of [_current] while a write is
  /// in flight, and are reverted to it if the write fails.
  late double _progress;
  late AssignmentStatus _status;

  /// Last persisted state of the assignment (including AI-check results).
  late AssignmentModel _current;
  bool _aiLoading = false;
  bool _aiCheckLoading = false;

  @override
  void initState() {
    super.initState();
    _progress = widget.assignment.progress;
    _status = widget.assignment.status;
    _current = widget.assignment;
  }

  Future<void> _askAiToPlan() async {
    setState(() => _aiLoading = true);
    final a = widget.assignment;
    try {
      final callable = FunctionsService.callable('chatWithTutor');
      final result = await callable.call<Map<String, dynamic>>({
        'botId': 'planner',
        'message': AppStrings.t('ai_plan_prompt', {
              'title': a.title,
              'subject': a.subject,
              'due':
                  '${DateHelper.formatJapaneseDate(a.dueDate)} (${a.dueDateLabel})',
              'difficulty': a.difficulty,
            }) +
            (a.description?.isNotEmpty == true
                ? AppStrings.t('ai_plan_prompt_detail',
                    {'description': a.description ?? ''})
                : ''),
        'language': AppStrings.currentLocale,
      });
      final reply = (result.data['reply'] as String?)?.trim();
      if (!mounted) return;
      setState(() => _aiLoading = false);
      if (reply == null || reply.isEmpty) {
        _showAiError(AppStrings.t('ai_plan_failed'));
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(AppStrings.t('ai_plan_title', {'title': a.title})),
          content: SingleChildScrollView(child: Text(reply)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(AppStrings.t('common_close')))
          ],
        ),
      );
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      setState(() => _aiLoading = false);
      // Quota and login problems are actionable; show them instead of the generic failure.
      final actionable =
          e.code == 'resource-exhausted' || e.code == 'unauthenticated';
      _showAiError(actionable
          ? FunctionsService.describeError(e)
          : AppStrings.t('ai_plan_failed'));
    } catch (e) {
      if (!mounted) return;
      setState(() => _aiLoading = false);
      _showAiError(AppStrings.t('ai_plan_failed'));
    }
  }

  void _showAiError(String message) =>
      showAssignmentErrorToast(context, message);

  /// Picks an image/PDF/Word/text file, reads it with `readAsBytes()` (works on
  /// web, desktop and mobile alike), sends it for AI review and shows the result.
  Future<void> _pickAndCheckSubmission() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: _kSupportedSubmissionExtensions,
    );
    if (file == null || !mounted) return;

    final Uint8List bytes;
    try {
      bytes = await file.readAsBytes();
    } catch (_) {
      if (!mounted) return;
      _showAiError(AppStrings.t('file_read_failed'));
      return;
    }
    if (!mounted) return;
    if (bytes.lengthInBytes > _kMaxSubmissionBytes) {
      _showAiError(AppStrings.t('file_too_large'));
      return;
    }
    final extension =
        file.name.contains('.') ? file.name.split('.').last : null;
    final mimeType = _mimeTypeForExtension(extension);
    if (mimeType == null) {
      _showAiError(AppStrings.t('file_unsupported'));
      return;
    }

    setState(() => _aiCheckLoading = true);
    final outcome = await ref
        .read(assignmentsNotifierProvider.notifier)
        .checkWithAi(_current, fileBytes: bytes, mimeType: mimeType);
    if (!mounted) return;
    setState(() => _aiCheckLoading = false);
    if (outcome.model == null) {
      _showAiError(
          outcome.error ?? AppStrings.t('err_assignment_check_failed'));
      return;
    }
    // Merge only the AI fields: progress/status may have changed while the
    // check was running, and a whole-model replace would roll them back.
    final checked = outcome.model!;
    setState(() => _current = _current.copyWith(
          aiCompletionPercent: checked.aiCompletionPercent,
          aiMissingParts: checked.aiMissingParts,
          aiAdvice: checked.aiAdvice,
          aiAnalyzedAt: checked.aiAnalyzedAt,
        ));
  }

  /// Puts the live slider/chip values back to the last persisted state.
  void _revertToCurrent() {
    _progress = _current.progress;
    _status = _current.status;
  }

  void _onProgressChanged(double value) {
    setState(() {
      _progress = value;
      _status = AssignmentModel.statusForProgress(value);
    });
  }

  // Commit on drag end, not every `onChanged` tick, to avoid a Firestore write
  // per pixel of drag.
  Future<void> _onProgressChangeEnd(double value) async {
    if (value == _current.progress) return;
    final error = await ref
        .read(assignmentsNotifierProvider.notifier)
        .updateProgress(_current, value);
    if (!mounted) return;
    if (error != null) {
      setState(_revertToCurrent);
      showAssignmentErrorToast(context, error);
      return;
    }
    setState(() => _current = _current.withProgress(value));
  }

  Future<void> _onStatusChanged(AssignmentStatus status) async {
    if (status == _status) return;
    final next = _current.withStatus(status);
    setState(() {
      _status = next.status;
      _progress = next.progress;
    });
    final error = await ref
        .read(assignmentsNotifierProvider.notifier)
        .updateStatus(_current, status);
    if (!mounted) return;
    if (error != null) {
      setState(_revertToCurrent);
      showAssignmentErrorToast(context, error);
      return;
    }
    setState(() => _current = next);
  }

  Future<void> _edit() async {
    // Hand the edit sheet the current state (not the sheet's initial snapshot)
    // so progress/status changed here aren't overwritten on save.
    final existing = _current.copyWith(progress: _progress, status: _status);
    Navigator.pop(context);
    await showAddEditAssignmentSheet(context, ref, existing: existing);
  }

  Future<void> _delete() async {
    final ok = await showConfirmDialog(context,
        title: AppStrings.t('as_delete_title'),
        message: AppStrings.t(
            'as_delete_confirm', {'title': widget.assignment.title}));
    if (!ok) return;
    final error = await ref
        .read(assignmentsNotifierProvider.notifier)
        .delete(widget.assignment.id);
    if (!mounted) return;
    if (error != null) {
      showAssignmentErrorToast(context, error);
      return;
    }
    Navigator.pop(context);
    toastification.show(
      context: context,
      type: ToastificationType.success,
      style: ToastificationStyle.flat,
      title: Text(AppStrings.t('as_deleted')),
      autoCloseDuration: const Duration(seconds: 2),
    );
  }

  @override
  Widget build(BuildContext context) {
    final assignment = _current;
    return SingleChildScrollView(
      padding:
          EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom + 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 12),
              decoration: BoxDecoration(
                  color: AppColors.textMuted,
                  borderRadius: BorderRadius.circular(2)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                SubjectPill(subject: assignment.subject),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                        color: AppColors.surfaceVar, shape: BoxShape.circle),
                    child: Icon(Icons.close,
                        size: 18, color: AppColors.textPrimary),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 12),
                Text(assignment.title,
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 8),
                // Wrap so a long localized date can push the badge to the next line.
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      AppStrings.t('as_due_prefix', {
                        'date':
                            DateHelper.formatJapaneseDate(assignment.dueDate)
                      }),
                      style: TextStyle(
                          fontSize: 13, color: AppColors.textSecondary),
                    ),
                    // The full date is already in the prefix; a finished task needs no countdown badge.
                    if (_status != AssignmentStatus.completed)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 3),
                        decoration: BoxDecoration(
                            color: assignment.dueDateBgColor,
                            borderRadius: BorderRadius.circular(20)),
                        child: Text(assignment.dueDateLabel,
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: assignment.dueDateColor)),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(AppStrings.t('fld_difficulty'),
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary)),
                    StarRating(
                        initialRating: assignment.difficulty, readOnly: true),
                  ],
                ),
                if (assignment.description != null &&
                    assignment.description!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(assignment.description ?? '',
                      style: TextStyle(
                          fontSize: 14, color: AppColors.textSecondary)),
                ],
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(AppStrings.t('fld_progress'),
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary)),
                    Text('${(_progress * 100).round()}%',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.accentText)),
                  ],
                ),
                Slider(
                    value: _progress,
                    min: 0,
                    max: 1,
                    divisions: 10,
                    activeColor: AppColors.primary,
                    onChanged: _onProgressChanged,
                    onChangeEnd: _onProgressChangeEnd),
                const SizedBox(height: 12),
                Text(AppStrings.t('fld_status'),
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: AssignmentStatus.values.map((s) {
                    final selected = s == _status;
                    return ChoiceChip(
                      label: Text(s.label),
                      selected: selected,
                      onSelected: (_) => _onStatusChanged(s),
                      selectedColor: AppColors.primary,
                      checkmarkColor: AppColors.onPrimary,
                      labelStyle: TextStyle(
                          color: selected
                              ? AppColors.onPrimary
                              : AppColors.textPrimary,
                          fontWeight: FontWeight.w500),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _aiLoading ? null : _askAiToPlan,
                    style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary),
                    icon: _aiLoading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: AppColors.onPrimary))
                        : const Text('🎯'),
                    label: Text(_aiLoading
                        ? AppStrings.t('ai_thinking')
                        : AppStrings.t('ai_plan_btn')),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _aiCheckLoading ? null : _pickAndCheckSubmission,
                    icon: _aiCheckLoading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.upload_file_outlined, size: 18),
                    label: Text(_aiCheckLoading
                        ? AppStrings.t('ai_checking')
                        : AppStrings.t('ai_check_btn')),
                  ),
                ),
                if (assignment.hasAiAnalysis) ...[
                  const SizedBox(height: 14),
                  _AiCheckResult(assignment: assignment),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                        child: OutlinedButton(
                            onPressed: _edit,
                            child: Text(AppStrings.t('common_edit')))),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _delete,
                        style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: AppColors.danger),
                            foregroundColor: AppColors.danger),
                        child: Text(AppStrings.t('common_delete')),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AiCheckResult extends StatelessWidget {
  final AssignmentModel assignment;
  const _AiCheckResult({required this.assignment});

  @override
  Widget build(BuildContext context) {
    final percent =
        (assignment.aiCompletionPercent ?? 0).clamp(0, 100).toDouble();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceVar,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              DonutChart(
                progress: percent / 100,
                size: 44,
                strokeWidth: 5,
                trackColor: AppColors.border,
                fillColor: AppColors.primary,
                centerLabel: '${percent.round()}%',
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(AppStrings.t('ai_check_result'),
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary)),
              ),
            ],
          ),
          if (assignment.aiMissingParts.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(AppStrings.t('ai_missing_parts'),
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.warning)),
            const SizedBox(height: 6),
            ...assignment.aiMissingParts.map(
              (m) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('• $m',
                    style: TextStyle(
                        fontSize: 12, color: AppColors.textSecondary)),
              ),
            ),
          ],
          if (assignment.aiAdvice != null &&
              assignment.aiAdvice!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: AppColors.primaryLight.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10)),
              child: Text(assignment.aiAdvice!,
                  style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                      height: 1.4)),
            ),
          ],
        ],
      ),
    );
  }
}
