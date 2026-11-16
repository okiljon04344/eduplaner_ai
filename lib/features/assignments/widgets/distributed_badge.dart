import 'package:flutter/material.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_colors.dart';

/// Small badge indicating an assignment was handed out by a teacher
/// ("先生から" or "{name}先生から").
///
/// UZ: Topshiriq o'qituvchi tomonidan berilganligini bildiruvchi kichik nishon
/// ("先生から" yoki "{name}先生から").
class DistributedBadge extends StatelessWidget {
  final String? teacherName;
  final double fontSize;

  const DistributedBadge({
    super.key,
    this.teacherName,
    this.fontSize = 10,
  });

  @override
  Widget build(BuildContext context) {
    var rawName = teacherName?.trim() ?? '';
    if (rawName.endsWith('先生')) {
      rawName = rawName.substring(0, rawName.length - 2).trim();
    }
    final text = rawName.isNotEmpty
        ? AppStrings.t('sas_from_named_teacher', {'name': rawName})
        : AppStrings.t('sas_from_teacher');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontFamily: 'Plus Jakarta Sans',
          fontFamilyFallback: const ['NotoSansJP'],
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          color: AppColors.accentText,
        ),
      ),
    );
  }
}
