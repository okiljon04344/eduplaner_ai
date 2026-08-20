import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toastification/toastification.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/services/functions_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/widgets/donut_chart.dart';
import '../../../shared/widgets/subject_pill.dart';
import '../models/assignment_model.dart';
import '../providers/assignments_provider.dart';
import 'add_edit_assignment_sheet.dart';

const _kSupportedSubmissionExtensions = ['jpg', 'jpeg', 'png', 'pdf', 'docx', 'txt'];
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

Future<void> showAssignmentDetailSheet(BuildContext context, WidgetRef ref, AssignmentModel assignment) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    // backgroundColor/shape inherited from the app's dark bottomSheetTheme.
    builder: (_) => _AssignmentDetailSheet(assignment: assignment),
  );
}

class _AssignmentDetailSheet extends ConsumerStatefulWidget {
  final AssignmentModel assignment;
  const _AssignmentDetailSheet({required this.assignment});

  @override
  ConsumerState<_AssignmentDetailSheet> createState() => _AssignmentDetailSheetState();
}

class _AssignmentDetailSheetState extends ConsumerState<_AssignmentDetailSheet> {
  late double _progress;
  late AssignmentStatus _status;
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
              'due': a.dueDateLabel,
              'difficulty': a.difficulty,
            }) +
            (a.description?.isNotEmpty == true ? AppStrings.t('ai_plan_prompt_detail', {'description': a.description ?? ''}) : ''),
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(AppStrings.t('ai_plan_title', {'title': a.title})),
          content: SingleChildScrollView(child: Text(reply)),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(AppStrings.t('common_close')))],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _aiLoading = false);
      _showAiError(AppStrings.t('ai_plan_failed'));
    }
  }

  void _showAiError(String message) {
    toastification.show(
      context: context,
      type: ToastificationType.error,
      style: ToastificationStyle.flat,
      title: Text(message),
      autoCloseDuration: const Duration(seconds: 3),
    );
  }

  /// 課題の自動チェック — picks an image/PDF/Word/text file and reads its
  /// bytes via `PlatformFile.readAsBytes()` (file_picker 12's API — the
  /// platform-agnostic way to get bytes on web, desktop, and mobile alike,
  /// replacing the old synchronous `.bytes` getter + `withData` param),
  /// sends it for AI review, and shows the result inline.
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
    final extension = file.name.contains('.') ? file.name.split('.').last : null;
    final mimeType = _mimeTypeForExtension(extension);
    if (mimeType == null) {
      _showAiError(AppStrings.t('file_unsupported'));
      return;
    }

    setState(() => _aiCheckLoading = true);
    final outcome = await ref.read(assignmentsNotifierProvider.notifier).checkWithAi(_current, fileBytes: bytes, mimeType: mimeType);
    if (!mounted) return;
    setState(() => _aiCheckLoading = false);
    if (outcome.model == null) {
      _showAiError(outcome.error ?? AppStrings.t('err_assignment_check_failed'));
      return;
    }
    setState(() => _current = outcome.model!);
  }

  void _onProgressChanged(double value) {
    setState(() => _progress = value);
  }

  // Committing on drag-end (not every `onChanged` tick) avoids firing a
  // Firestore write per pixel of drag while the slider is being dragged.
  void _onProgressChangeEnd(double value) {
    ref.read(assignmentsNotifierProvider.notifier).updateProgress(widget.assignment.id, value);
  }

  void _onStatusChanged(AssignmentStatus status) {
    setState(() => _status = status);
    ref.read(assignmentsNotifierProvider.notifier).updateStatus(widget.assignment.id, status);
  }

  Future<void> _edit() async {
    Navigator.pop(context);
    await showAddEditAssignmentSheet(context, ref, existing: widget.assignment);
  }

  Future<void> _delete() async {
    final ok = await showConfirmDialog(context, title: AppStrings.t('as_delete_title'), message: AppStrings.t('as_delete_confirm', {'title': widget.assignment.title}));
    if (!ok) return;
    await ref.read(assignmentsNotifierProvider.notifier).delete(widget.assignment.id);
    if (!mounted) return;
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
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom + 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 12),
              decoration: BoxDecoration(color: AppColors.textMuted, borderRadius: BorderRadius.circular(2)),
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
                    decoration: BoxDecoration(color: AppColors.surfaceVar, shape: BoxShape.circle),
                    child: Icon(Icons.close, size: 18, color: AppColors.textPrimary),
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
                Text(assignment.title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(AppStrings.t('as_due_prefix', {'date': assignment.dueDateLabel}), style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(color: assignment.dueDateBgColor, borderRadius: BorderRadius.circular(20)),
                      child: Text(assignment.dueDateLabel, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: assignment.dueDateColor)),
                    ),
                  ],
                ),
                if (assignment.description != null && assignment.description!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(assignment.description ?? '', style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
                ],
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(AppStrings.t('fld_progress'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                    Text('${(_progress * 100).round()}%', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.primary)),
                  ],
                ),
                Slider(value: _progress, min: 0, max: 1, divisions: 10, activeColor: AppColors.primary, onChanged: _onProgressChanged, onChangeEnd: _onProgressChangeEnd),
                const SizedBox(height: 12),
                Text(AppStrings.t('fld_status'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                const SizedBox(height: 8),
                Row(
                  children: AssignmentStatus.values.map((s) {
                    final selected = s == _status;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(s.label),
                        selected: selected,
                        onSelected: (_) => _onStatusChanged(s),
                        selectedColor: AppColors.primary,
                        labelStyle: TextStyle(color: selected ? Colors.white : AppColors.textPrimary, fontWeight: FontWeight.w500),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _aiLoading ? null : _askAiToPlan,
                    style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                    icon: _aiLoading
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('🎯'),
                    label: Text(_aiLoading ? AppStrings.t('ai_thinking') : AppStrings.t('ai_plan_btn')),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _aiCheckLoading ? null : _pickAndCheckSubmission,
                    icon: _aiCheckLoading
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.upload_file_outlined, size: 18),
                    label: Text(_aiCheckLoading ? AppStrings.t('ai_checking') : AppStrings.t('ai_check_btn')),
                  ),
                ),
                if (assignment.hasAiAnalysis) ...[
                  const SizedBox(height: 14),
                  _AiCheckResult(assignment: assignment),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: OutlinedButton(onPressed: _edit, child: Text(AppStrings.t('common_edit')))),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _delete,
                        style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.danger), foregroundColor: AppColors.danger),
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
    final percent = (assignment.aiCompletionPercent ?? 0).clamp(0, 100).toDouble();
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
                child: Text(AppStrings.t('ai_check_result'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
              ),
            ],
          ),
          if (assignment.aiMissingParts.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(AppStrings.t('ai_missing_parts'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.warning)),
            const SizedBox(height: 6),
            ...assignment.aiMissingParts.map(
              (m) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('• $m', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              ),
            ),
          ],
          if (assignment.aiAdvice != null && assignment.aiAdvice!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: AppColors.primaryLight.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
              child: Text(assignment.aiAdvice!, style: TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.4)),
            ),
          ],
        ],
      ),
    );
  }
}
