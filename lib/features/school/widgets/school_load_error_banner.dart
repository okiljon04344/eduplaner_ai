import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../school_providers.dart';

/// Banner alerting students when school-data synchronization fails.
///
/// UZ: Maktab ma'lumotlarini sinxronlashtirish muvaffaqiyatsiz bo'lganda talabalarni ogohlantiruvchi banner.
class SchoolLoadErrorBanner extends ConsumerWidget {
  final EdgeInsets? margin;
  const SchoolLoadErrorBanner({super.key, this.margin});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final failed = ref.watch(schoolLoadFailedProvider);
    if (!failed) return const SizedBox.shrink();

    return Semantics(
      liveRegion: true,
      child: Container(
        margin: margin,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.warningLight,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.warning, width: 1),
        ),
        child: Row(
          children: [
            const Icon(Icons.cloud_off_outlined, color: AppColors.warning),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                AppStrings.t('school_load_error'),
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
