import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../assignments/providers/assignments_provider.dart';
import 'assignment_row_item.dart';

/// Glass card containing up to 3 upcoming-assignment rows separated by
/// hairline dividers, matching the design's "UPCOMING TASKS" card.
class UpcomingAssignmentsList extends ConsumerWidget {
  const UpcomingAssignmentsList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assignments = ref.watch(upcomingAssignmentsProvider);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
        borderRadius: BorderRadius.circular(22),
      ),
      child: assignments.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Text(
                  '提出期限が近い課題はありません',
                  style: TextStyle(fontSize: 13, color: AppColors.textMuted, fontFamily: 'Plus Jakarta Sans', fontFamilyFallback: ['NotoSansJP']),
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
