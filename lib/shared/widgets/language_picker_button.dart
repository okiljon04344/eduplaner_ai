import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/providers/locale_provider.dart';
import '../../../core/theme/app_colors.dart';

/// A reusable language picker button that shows a modal bottom sheet.
///
/// Designed to be used in nav bars or hero sections where a full [ListTile]
/// is too large. Displays the current language's flag emoji by default.
class LanguagePickerButton extends ConsumerWidget {
  final Color? color;
  final bool showLabel;

  const LanguagePickerButton({
    super.key,
    this.color,
    this.showLabel = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentLocale = ref.watch(localeProvider);
    final currentEntry = AppStrings.locales.where((l) => l.$1 == currentLocale).firstOrNull;
    final flag = currentEntry?.$3 ?? '🌐';
    final name = currentEntry?.$2 ?? currentLocale;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _showLanguagePicker(context, ref, currentLocale),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: (color ?? Colors.white).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: (color ?? Colors.white).withValues(alpha: 0.15)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(flag, style: const TextStyle(fontSize: 16)),
              if (showLabel) ...[
                const SizedBox(width: 8),
                Text(
                  name,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: color ?? Colors.white,
                    fontFamily: 'Plus Jakarta Sans',
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showLanguagePicker(BuildContext context, WidgetRef ref, String currentLocale) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, sc) => Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              AppStrings.t('settings_language'),
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                controller: sc,
                itemCount: AppStrings.locales.length,
                itemBuilder: (_, i) {
                  final (code, name, flag) = AppStrings.locales[i];
                  final isSelected = code == currentLocale;
                  return ListTile(
                    leading: Text(flag, style: const TextStyle(fontSize: 24)),
                    title: Text(name, style: TextStyle(
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
                      color: isSelected ? AppColors.primary : AppColors.textPrimary,
                    )),
                    trailing: isSelected ? const Icon(Icons.check_rounded, color: AppColors.primary) : null,
                    onTap: () {
                      Navigator.pop(ctx);
                      ref.read(localeProvider.notifier).setLocale(code);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
