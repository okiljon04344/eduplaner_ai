import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toastification/toastification.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../groups/providers/groups_provider.dart';

/// "クラス全体での共有" — lets a student create or join a class-wide study
/// group by a 6-character code. Once joined, timetable classes created while
/// in a group are shared with every member (see `TimetableNotifier`).
class GroupShareSection extends ConsumerWidget {
  const GroupShareSection({super.key});

  Future<void> _createGroup(BuildContext context, WidgetRef ref) async {
    final name = await _promptText(context, title: 'グループを作成', hintText: '例：3年A組', confirmLabel: '作成');
    if (name == null || name.trim().isEmpty || !context.mounted) return;
    final error = await ref.read(groupsNotifierProvider.notifier).createGroup(name.trim());
    if (!context.mounted) return;
    _showToast(context, error ?? 'グループを作成しました', isError: error != null);
  }

  Future<void> _joinGroup(BuildContext context, WidgetRef ref) async {
    final code = await _promptText(context, title: 'コードで参加', hintText: '例：AB12CD', confirmLabel: '参加');
    if (code == null || code.trim().isEmpty || !context.mounted) return;
    final error = await ref.read(groupsNotifierProvider.notifier).joinGroup(code.trim());
    if (!context.mounted) return;
    _showToast(context, error ?? 'グループに参加しました', isError: error != null);
  }

  Future<void> _leaveGroup(BuildContext context, WidgetRef ref, String groupId) async {
    final ok = await showConfirmDialog(context, title: 'グループから退出', message: 'このグループから退出しますか？共有された時間割は表示されなくなります。', confirmLabel: '退出');
    if (!ok) return;
    await ref.read(groupsNotifierProvider.notifier).leaveGroup(groupId);
    if (!context.mounted) return;
    _showToast(context, 'グループから退出しました');
  }

  void _showToast(BuildContext context, String message, {bool isError = false}) {
    toastification.show(
      context: context,
      type: isError ? ToastificationType.error : ToastificationType.success,
      style: ToastificationStyle.flat,
      title: Text(message),
      autoCloseDuration: const Duration(seconds: 2),
    );
  }

  Future<String?> _promptText(BuildContext context, {required String title, required String hintText, required String confirmLabel}) {
    return showDialog<String>(
      context: context,
      builder: (_) => _TextPromptDialog(title: title, hintText: hintText, confirmLabel: confirmLabel),
    );
  }

  void _copyCode(BuildContext context, String code) {
    Clipboard.setData(ClipboardData(text: code));
    _showToast(context, 'コードをコピーしました');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupAsync = ref.watch(myGroupProvider);

    return groupAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      error: (_, __) => const SizedBox.shrink(),
      data: (group) {
        if (group == null) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _createGroup(context, ref),
                    child: const Text('グループを作成', style: TextStyle(fontSize: 12)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _joinGroup(context, ref),
                    child: const Text('コードで参加', style: TextStyle(fontSize: 12)),
                  ),
                ),
              ],
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surfaceVar,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.groups_outlined, size: 18, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(group.name, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                    ),
                    Text('${group.memberIds.length}人', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                  ],
                ),
                const SizedBox(height: 10),
                GestureDetector(
                  onTap: () => _copyCode(context, group.code),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        Text(group.code, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: 2, color: AppColors.primary)),
                        const Spacer(),
                        const Icon(Icons.copy_rounded, size: 15, color: AppColors.primary),
                        const SizedBox(width: 4),
                        const Text('コピー', style: TextStyle(fontSize: 11, color: AppColors.primary)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => _leaveGroup(context, ref, group.id),
                    child: const Text('グループから退出', style: TextStyle(color: AppColors.danger, fontSize: 12)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _TextPromptDialog extends StatefulWidget {
  final String title;
  final String hintText;
  final String confirmLabel;
  const _TextPromptDialog({required this.title, required this.hintText, required this.confirmLabel});

  @override
  State<_TextPromptDialog> createState() => _TextPromptDialogState();
}

class _TextPromptDialogState extends State<_TextPromptDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.characters,
        decoration: InputDecoration(hintText: widget.hintText),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('キャンセル')),
        FilledButton(onPressed: () => Navigator.pop(context, _controller.text), child: Text(widget.confirmLabel)),
      ],
    );
  }
}
