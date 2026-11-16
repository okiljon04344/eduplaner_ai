import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../assignments/providers/assignments_provider.dart';
import 'assignment_row_item.dart';
import '../../../core/l10n/app_strings.dart';

/// Widget displaying a condensed list of upcoming pending assignments on the home screen.
///
/// UZ: Asosiy ekranda yaqinlashib kelayotgan kutilayotgan topshiriqlarning qisqacha ro'yxatini
/// ko'rsatadigan vidjet.
class UpcomingAssignmentsList extends ConsumerWidget {
  const UpcomingAssignmentsList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assignments = ref.watch(upcomingAssignmentsProvider);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        border: Border.all(color: AppColors.cardStroke),
        borderRadius: BorderRadius.circular(20),
      ),
      child: assignments.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Text(
                  AppStrings.t('home_no_upcoming'),
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textMuted,
                    fontFamily: 'Plus Jakarta Sans',
                    fontFamilyFallback: const ['NotoSansJP'],
                  ),
                ),
              ),
            )
          : Column(
              children: [
                for (var i = 0; i < assignments.length; i++)
                  AssignmentRowItem(assignment: assignments[i], showDivider: i != assignments.length - 1),
              ],
            ),
    );
  }
}
