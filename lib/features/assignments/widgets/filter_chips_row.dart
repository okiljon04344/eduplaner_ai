import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../models/assignment_model.dart';
import '../providers/assignments_provider.dart';

/// Horizontal selector of filter chips displaying assignment status categories along with count badges.
///
/// UZ: Topshiriq holati toifalarini hisoblagich nishonlari bilan birga ko'rsatadigan filtr chiplarining gorizontal tanlagichi.
class FilterChipsRow extends ConsumerWidget {
  const FilterChipsRow({super.key});

  /// Stable filter ids stored in [selectedFilterProvider]; labels are
  /// resolved per-locale in [_labelFor].
  ///
  /// UZ: [selectedFilterProvider] da saqlanadigan barqaror filtr identifikatorlari;
  /// yorliqlar [_labelFor] da har bir tilga qarab aniqlanadi.
  static const _filters = ['all', 'notStarted', 'inProgress', 'completed'];

  static String _labelFor(String id) {
    switch (id) {
      case 'notStarted':
        return AppStrings.t('status_not_started');
      case 'inProgress':
        return AppStrings.t('status_in_progress');
      case 'completed':
        return AppStrings.t('status_completed');
      default:
        return AppStrings.t('as_filter_all');
    }
  }

  static int _countFor(String id, List<AssignmentModel> assignments) {
    switch (id) {
      case 'notStarted':
        return assignments.where((a) => a.status == AssignmentStatus.notStarted).length;
      case 'inProgress':
        return assignments.where((a) => a.status == AssignmentStatus.inProgress).length;
      case 'completed':
        return assignments.where((a) => a.status == AssignmentStatus.completed).length;
      case 'all':
      default:
        return assignments.length;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedFilterProvider);
    final assignments = ref.watch(assignmentsStreamProvider).valueOrNull ?? const [];

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: _filters.map((f) {
            final isSelected = f == selected;
            final textColor = isSelected ? AppColors.onPrimary : AppColors.textSecondary;

            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => ref.read(selectedFilterProvider.notifier).state = f,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  height: 40,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.primary : AppColors.cardSurface,
                    borderRadius: BorderRadius.circular(999),
                    border: isSelected ? null : Border.all(color: AppColors.cardStroke),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _labelFor(f),
                        style: TextStyle(
                          fontFamily: 'Plus Jakarta Sans',
                          fontFamilyFallback: const ['NotoSansJP'],
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: textColor,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${_countFor(f, assignments)}',
                        style: TextStyle(
                          fontFamily: 'Plus Jakarta Sans',
                          fontFamilyFallback: const ['NotoSansJP'],
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: textColor.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}
