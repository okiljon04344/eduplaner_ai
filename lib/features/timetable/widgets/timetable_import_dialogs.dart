import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_colors.dart';

/// Second confirmation dialog shown when `mode == 'replace'` or `removedCount > 0`.
///
/// Explicitly blocks the Enter / NumpadEnter keyboard shortcuts so destructive
/// changes can only be confirmed via an intentional pointer click or tap.
Future<bool> showDestructiveImportConfirmDialog(
  BuildContext context, {
  required int removedCount,
  required bool isReplaceMode,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (dialogContext) => _DestructiveConfirmDialog(
      removedCount: removedCount,
      isReplaceMode: isReplaceMode,
    ),
  );
  return result == true;
}

class _DestructiveConfirmDialog extends StatelessWidget {
  final int removedCount;
  final bool isReplaceMode;

  const _DestructiveConfirmDialog({
    required this.removedCount,
    required this.isReplaceMode,
  });

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.enter): DoNothingAndStopPropagationIntent(),
        SingleActivator(LogicalKeyboardKey.numpadEnter): DoNothingAndStopPropagationIntent(),
      },
      child: Focus(
        onKeyEvent: (node, event) {
          if (event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.numpadEnter) {
            return KeyEventResult.handled;
          }
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.escape) {
            Navigator.of(context).pop(false);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: AlertDialog(
          backgroundColor: AppColors.cardSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: AppColors.danger.withValues(alpha: 0.45)),
          ),
          icon: const Icon(
            Icons.warning_amber_rounded,
            color: AppColors.danger,
            size: 36,
          ),
          title: Text(
            AppStrings.t('tt_import_destructive_title'),
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppStrings.t('tt_import_destructive_body', {'n': removedCount}),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    height: 1.5,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (isReplaceMode) ...[
                  const SizedBox(height: 8),
                  Text(
                    AppStrings.t('tt_import_destructive_replace_note'),
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.45,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.warningLight,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.warning.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.keyboard_hide_rounded,
                        size: 16,
                        color: AppColors.warning,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          AppStrings.t('tt_import_destructive_no_enter'),
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.4,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              autofocus: false,
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(AppStrings.t('tt_import_cancel_btn')),
            ),
            Semantics(
              button: true,
              label: AppStrings.t('tt_import_destructive_confirm'),
              child: FilledButton(
                key: const Key('destructive_confirm_button'),
                autofocus: false,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.danger,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(AppStrings.t('tt_import_destructive_confirm')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
