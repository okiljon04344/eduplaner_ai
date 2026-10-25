import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../assignments/models/assignment_model.dart';
import '../../assignments/providers/assignments_provider.dart';
import '../providers/home_provider.dart';
import '../../../core/l10n/app_strings.dart';

// Same fallback strings as home_provider.dart, used for comparison. Getters so
// they follow the current locale.
String get _fallbackWeakArea => AppStrings.t('weak_fallback');
String get _noAssignmentsWeakArea => AppStrings.t('weak_no_assignments');

/// Local summary from [assignmentsStreamProvider], shown while the AI analysis
/// loads so the card is never just a spinner. Empty when there are no assignments.
final _localWeakSummaryProvider = Provider<String>((ref) {
  final all = ref.watch(assignmentsStreamProvider).valueOrNull ?? [];
  final incomplete = all.where((a) => a.status != AssignmentStatus.completed).toList();
  if (incomplete.isEmpty) return '';

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final overdue = incomplete.where((a) {
    final due = DateTime(a.dueDate.year, a.dueDate.month, a.dueDate.day);
    return due.isBefore(today);
  }).toList();

  final countBySubject = <String, int>{};
  final sourceList = overdue.isNotEmpty ? overdue : incomplete;
  for (final a in sourceList) {
    countBySubject[a.subject] = (countBySubject[a.subject] ?? 0) + 1;
  }
  final worst = countBySubject.entries.reduce((a, b) => a.value > b.value ? a : b);
  final template = overdue.isNotEmpty
      ? AppStrings.t('weak_overdue_msg')
      : AppStrings.t('weak_pending_msg');
  return template.replaceAll('{subject}', worst.key).replaceAll('{n}', '${worst.value}');
});

/// Weak-area analysis card. Tapping it opens `/assignments` when there are no
/// assignments, otherwise a bottom sheet with the full text and a shortcut to
/// the AI chat.
class WeakAreaCard extends ConsumerWidget {
  const WeakAreaCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final analysis = ref.watch(weakAreaProvider);
    final localSummary = ref.watch(_localWeakSummaryProvider);
    final hasAssignments = localSummary.isNotEmpty;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          if (!hasAssignments) {
            context.go('/assignments');
            return;
          }
          final text = analysis.valueOrNull;
          if (text != null && text != _noAssignmentsWeakArea && text != _fallbackWeakArea) {
            _showDetailSheet(context, ref, text);
          } else if (localSummary.isNotEmpty) {
            _showDetailSheet(context, ref, localSummary);
          }
        },
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surfaceVar,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.primaryMid.withValues(alpha: 0.25)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.primaryMid.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: const Text('📊', style: TextStyle(fontSize: 18)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppStrings.t('home_weak_area_title'),
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 4),
                    _AnalysisText(analysis: analysis, localSummary: localSummary),
                  ],
                ),
              ),
              // Re-runs today's analysis.
              if (hasAssignments)
                GestureDetector(
                  onTap: () => ref.invalidate(weakAreaProvider),
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Icon(Icons.refresh_rounded, size: 18, color: AppColors.textMuted),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDetailSheet(BuildContext context, WidgetRef ref, String text) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                const Text('📊', style: TextStyle(fontSize: 22)),
                const SizedBox(width: 10),
                Text(AppStrings.t('home_weak_area_title'), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.primaryMid.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.primaryMid.withValues(alpha: 0.18)),
              ),
              child: Text(text, style: TextStyle(fontSize: 13, height: 1.6, color: AppColors.textPrimary)),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  context.go('/ai');
                },
                icon: const Icon(Icons.smart_toy_outlined, size: 18),
                label: Text(AppStrings.t('weak_consult_ai')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shows the AI text, the local summary while loading, or the error state.
class _AnalysisText extends StatelessWidget {
  final AsyncValue<String> analysis;
  final String localSummary;
  const _AnalysisText({required this.analysis, required this.localSummary});

  @override
  Widget build(BuildContext context) {
    return analysis.when(
      data: (text) => Text(
        text,
        style: TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.4),
      ),
      loading: () => localSummary.isNotEmpty
          // Local summary while the AI result loads.
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    localSummary,
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.4),
                  ),
                ),
                const SizedBox(width: 6),
                const SizedBox(
                  width: 12, height: 12,
                  child: CircularProgressIndicator(strokeWidth: 1.5, color: AppColors.primaryMid),
                ),
              ],
            )
          : Text(
              AppStrings.t('weak_analyze_loading'),
              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
      error: (_, __) => Text(
        localSummary.isNotEmpty ? localSummary : AppStrings.t('weak_no_data'),
        style: TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.4),
      ),
    );
  }
}
