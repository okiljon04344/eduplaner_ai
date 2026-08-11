import 'package:flutter/material.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/theme/app_colors.dart';

Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String? confirmLabel,
  Color confirmColor = AppColors.danger,
}) async {
  final label = confirmLabel ?? AppStrings.t('common_delete');
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.bgLayer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: AppColors.border)),
      title: Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, fontFamily: 'Plus Jakarta Sans', fontFamilyFallback: const ['NotoSansJP'], color: AppColors.textPrimary)),
      content: Text(message, style: TextStyle(fontSize: 14, color: AppColors.textSecondary, fontFamily: 'Plus Jakarta Sans', fontFamilyFallback: const ['NotoSansJP'])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(AppStrings.t('common_cancel'))),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(label, style: TextStyle(color: confirmColor, fontWeight: FontWeight.w600)),
        ),
      ],
    ),
  );
  return result ?? false;
}
