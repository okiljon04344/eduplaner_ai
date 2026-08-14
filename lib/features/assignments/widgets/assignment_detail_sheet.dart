import 'package:cloud_functions/cloud_functions.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toastification/toastification.dart';
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
      final callable = FirebaseFunctions.instance.httpsCallable('chatWithTutor');
      final result = await callable.call<Map<String, dynamic>>({
        'botId': 'planner',
        'message':
            '次の課題を完了までの具体的なステップに分解し、番号付きの短い学習プランを作ってください。'
            '課題名: ${a.title}／科目: ${a.subject}／締め切り: ${a.dueDateLabel}／難易度(1-5): ${a.difficulty}'
            '${a.description?.isNotEmpty == true ? '／詳細: ${a.description}' : ''}',
      });
      final reply = (result.data['reply'] as String?)?.trim();
      if (!mounted) return;
      setState(() => _aiLoading = false);
      if (reply == null || reply.isEmpty) {
        _showAiError('AIプランを取得できませんでした。もう一度お試しください。');
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('🎯 AI学習プラン — ${a.title}'),
          content: SingleChildScrollView(child: Text(reply)),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('閉じる'))],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _aiLoading = false);
      _showAiError('AIプランを取得できませんでした。もう一度お試しください。');
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

  /// 課題の自動チェック — picks an image/PDF/Word/text file (using
  /// `withData: true` so bytes are available on web, desktop, and mobile
  /// alike, since only web guarantees bytes by default), sends it for
  /// AI review, and shows the result inline.
  Future<void> _pickAndCheckSubmission() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: _kSupportedSubmissionExtensions,
      withData: true,
    );
    if (result == null || result.files.isEmpty || !mounted) return;

    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) {
      _showAiError('ファイルを読み込めませんでした。もう一度お試しください。');
      return;
    }
    if (bytes.lengthInBytes > _kMaxSubmissionBytes) {
      _showAiError('ファイルサイズが大きすぎます（10MB以下にしてください）。');
      return;
    }
    final mimeType = _mimeTypeForExtension(file.extension);
    if (mimeType == null) {
      _showAiError('対応していないファイル形式です（jpg, png, pdf, docx, txtのみ）。');
      return;
    }

    setState(() => _aiCheckLoading = true);
    final outcome = await ref.read(assignmentsNotifierProvider.notifier).checkWithAi(_current, fileBytes: bytes, mimeType: mimeType);
    if (!mounted) return;
    setState(() => _aiCheckLoading = false);
    if (outcome.model == null) {
      _showAiError(outcome.error ?? '課題のチェックに失敗しました。もう一度お試しください。');
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
    final ok = await showConfirmDialog(context, title: '課題を削除', message: '${widget.assignment.title}を削除しますか？');
    if (!ok) return;
    await ref.read(assignmentsNotifierProvider.notifier).delete(widget.assignment.id);
    if (!mounted) return;
    Navigator.pop(context);
    toastification.show(
      context: context,
      type: ToastificationType.success,
      style: ToastificationStyle.flat,
      title: const Text('課題を削除しました'),
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
                    Text('提出: ${assignment.dueDateLabel}', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
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
                    Text('進捗', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                    Text('${(_progress * 100).round()}%', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.primary)),
                  ],
                ),
                Slider(value: _progress, min: 0, max: 1, divisions: 10, activeColor: AppColors.primary, onChanged: _onProgressChanged, onChangeEnd: _onProgressChangeEnd),
                const SizedBox(height: 12),
                Text('ステータス', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
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
                    label: Text(_aiLoading ? 'AIが考えています...' : 'AIで学習プランを作成'),
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
                    label: Text(_aiCheckLoading ? 'AIがチェックしています...' : '課題をアップロードしてAIチェック'),
                  ),
                ),
                if (assignment.hasAiAnalysis) ...[
                  const SizedBox(height: 14),
                  _AiCheckResult(assignment: assignment),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: OutlinedButton(onPressed: _edit, child: const Text('編集'))),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _delete,
                        style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.danger), foregroundColor: AppColors.danger),
                        child: const Text('削除'),
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
                child: Text('AIチェック結果', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
              ),
            ],
          ),
          if (assignment.aiMissingParts.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text('不足している部分', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.warning)),
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
