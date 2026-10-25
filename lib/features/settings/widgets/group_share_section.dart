import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toastification/toastification.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../groups/models/study_group_model.dart';
import '../../groups/providers/groups_provider.dart';

/// Lets a student create or join a study group by a 6-character code. Classes
/// created while in a group are shared with every member (see `TimetableNotifier`).
class GroupShareSection extends ConsumerWidget {
  const GroupShareSection({super.key});

  Future<void> _createGroup(BuildContext context, WidgetRef ref) async {
    final name = await _promptText(context,
        title: AppStrings.t('grp_create'),
        hintText: AppStrings.t('grp_create_hint'),
        confirmLabel: AppStrings.t('grp_create_btn'));
    if (name == null || name.trim().isEmpty || !context.mounted) return;
    final error = await ref
        .read(groupsNotifierProvider.notifier)
        .createGroup(name.trim());
    if (!context.mounted) return;
    _showToast(context, error ?? AppStrings.t('grp_created'),
        isError: error != null);
  }

  Future<void> _joinGroup(BuildContext context, WidgetRef ref) async {
    final code = await _promptText(context,
        title: AppStrings.t('grp_join'),
        hintText: AppStrings.t('grp_join_hint'),
        confirmLabel: AppStrings.t('grp_join_btn'));
    if (code == null || code.trim().isEmpty || !context.mounted) return;
    final error =
        await ref.read(groupsNotifierProvider.notifier).joinGroup(code.trim());
    if (!context.mounted) return;
    _showToast(context, error ?? AppStrings.t('grp_joined'),
        isError: error != null);
  }

  Future<void> _leaveGroup(
      BuildContext context, WidgetRef ref, StudyGroupModel group) async {
    final ok = await showConfirmDialog(context,
        title: AppStrings.t('grp_leave'),
        message: AppStrings.t('grp_leave_msg'),
        confirmLabel: AppStrings.t('grp_leave_btn'));
    if (!ok) return;
    final error =
        await ref.read(groupsNotifierProvider.notifier).leaveGroup(group);
    if (!context.mounted) return;
    _showToast(context, error ?? AppStrings.t('grp_left'),
        isError: error != null);
  }

  void _showToast(BuildContext context, String message,
      {bool isError = false}) {
    toastification.show(
      context: context,
      type: isError ? ToastificationType.error : ToastificationType.success,
      style: ToastificationStyle.flat,
      title: Text(message),
      autoCloseDuration: const Duration(seconds: 2),
    );
  }

  Future<String?> _promptText(BuildContext context,
      {required String title,
      required String hintText,
      required String confirmLabel}) {
    return showDialog<String>(
      context: context,
      builder: (_) => _TextPromptDialog(
          title: title, hintText: hintText, confirmLabel: confirmLabel),
    );
  }

  void _copyCode(BuildContext context, String code) {
    Clipboard.setData(ClipboardData(text: code));
    _showToast(context, AppStrings.t('grp_code_copied'));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupAsync = ref.watch(myGroupProvider);

    return groupAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: SizedBox(
            height: 18,
            width: 18,
            child: CircularProgressIndicator(strokeWidth: 2)),
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
                    child: Text(AppStrings.t('grp_create'),
                        style: const TextStyle(fontSize: 12)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _joinGroup(context, ref),
                    child: Text(AppStrings.t('grp_join'),
                        style: const TextStyle(fontSize: 12)),
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
                    Icon(Icons.groups_outlined,
                        size: 18, color: AppColors.accentText),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(group.name,
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary)),
                    ),
                    Text(
                        AppStrings.t('grp_members')
                            .replaceAll('{n}', '${group.memberIds.length}'),
                        style: TextStyle(
                            fontSize: 12, color: AppColors.textMuted)),
                  ],
                ),
                const SizedBox(height: 10),
                GestureDetector(
                  onTap: () => _copyCode(context, group.code),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        Text(group.code,
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 2,
                                color: AppColors.accentText)),
                        const Spacer(),
                        Icon(Icons.copy_rounded,
                            size: 15, color: AppColors.accentText),
                        const SizedBox(width: 4),
                        Text(AppStrings.t('common_copy'),
                            style: TextStyle(
                                fontSize: 11, color: AppColors.accentText)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => _leaveGroup(context, ref, group),
                    child: Text(AppStrings.t('grp_leave'),
                        style: const TextStyle(
                            color: AppColors.danger, fontSize: 12)),
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
  const _TextPromptDialog(
      {required this.title,
      required this.hintText,
      required this.confirmLabel});

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
        style: TextStyle(color: AppColors.textPrimary),
        decoration: InputDecoration(hintText: widget.hintText),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppStrings.t('common_cancel'))),
        FilledButton(
            onPressed: () => Navigator.pop(context, _controller.text),
            child: Text(widget.confirmLabel)),
      ],
    );
  }
}
