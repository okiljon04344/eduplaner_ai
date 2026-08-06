import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../timetable/providers/timetable_provider.dart';
import 'home_class_card.dart';
import '../../../core/l10n/app_strings.dart';

/// Vertical stack of today's classes (the currently-live one gets a glowing
/// highlighted card), matching the dark-neon design's home layout.
class TodayClassesRow extends ConsumerWidget {
  const TodayClassesRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final classes = ref.watch(todayClassesProvider);
    if (classes.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Text(
          AppStrings.t('home_no_classes'),
          style: TextStyle(fontSize: 13, color: AppColors.textMuted, fontFamily: 'Plus Jakarta Sans', fontFamilyFallback: const ['NotoSansJP']),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [for (final c in classes) HomeClassCard(classModel: c)],
      ),
    );
  }
}
