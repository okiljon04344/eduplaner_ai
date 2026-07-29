import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../models/assignment_model.dart';
import '../providers/assignments_provider.dart';
import '../widgets/add_edit_assignment_sheet.dart';
import '../widgets/assignment_card.dart';
import '../widgets/filter_chips_row.dart';

class AssignmentsScreen extends ConsumerWidget {
  const AssignmentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assignments = ref.watch(filteredAssignmentsProvider);
    final all = ref.watch(assignmentsStreamProvider).valueOrNull ?? [];
    final doneCount = all.where((a) => a.status == AssignmentStatus.completed).length;
    final totalCount = all.length;
    final progressPct = totalCount == 0 ? 0.0 : doneCount / totalCount;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: _TasksHeader(doneCount: doneCount, totalCount: totalCount, progressPct: progressPct),
            ),
            const SliverToBoxAdapter(child: FilterChipsRow()),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              sliver: SliverList.separated(
                itemCount: assignments.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) {
                  final assignment = assignments[i];
                  return AssignmentCard(key: ValueKey(assignment.id), assignment: assignment);
                },
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                child: _AddTaskButton(onTap: () => showAddEditAssignmentSheet(context, ref)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TasksHeader extends StatelessWidget {
  final int doneCount;
  final int totalCount;
  final double progressPct;
  const _TasksHeader({required this.doneCount, required this.totalCount, required this.progressPct});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0x2622D3EE))),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -60,
            right: -40,
            child: Container(
              width: 180,
              height: 180,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [Color(0x2E22D3EE), Color(0x0022D3EE)],
                  stops: [0.0, 0.7],
                ),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('TASK MANAGER', style: AppTextStyles.overline.copyWith(color: const Color(0x8C22D3EE))),
              const SizedBox(height: 6),
              Text('📝 課題一覧', style: AppTextStyles.headLG.copyWith(fontSize: 24)),
              const SizedBox(height: 5),
              Text(
                '$doneCount件完了 · 全$totalCount件',
                style: const TextStyle(
                  fontFamily: 'Plus Jakarta Sans', fontFamilyFallback: ['NotoSansJP'],
                  fontSize: 13, fontWeight: FontWeight.w500, color: Color(0x8022D3EE),
                ),
              ),
              const SizedBox(height: 16),
              Container(
                height: 8,
                decoration: BoxDecoration(
                  color: const Color(0x12FFFFFF),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: const Color(0x1A22D3EE)),
                ),
                clipBehavior: Clip.hardEdge,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: progressPct.clamp(0.0, 1.0)),
                  duration: const Duration(milliseconds: 600),
                  curve: Curves.easeOutExpo,
                  builder: (context, value, child) => FractionallySizedBox(
                    widthFactor: value,
                    alignment: Alignment.centerLeft,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: AppColors.gradientCyan,
                        borderRadius: BorderRadius.circular(4),
                        boxShadow: const [BoxShadow(color: Color(0x9922D3EE), blurRadius: 14)],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AddTaskButton extends StatelessWidget {
  final VoidCallback onTap;
  const _AddTaskButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0x3322D3EE), Color(0x1A06B6D4)],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0x4D22D3EE)),
          boxShadow: const [BoxShadow(color: Color(0x2622D3EE), blurRadius: 20)],
        ),
        child: const Text(
          '＋ 新しい課題を追加',
          style: TextStyle(
            fontFamily: 'Plus Jakarta Sans', fontFamilyFallback: ['NotoSansJP'],
            fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.cyan,
          ),
        ),
      ),
    );
  }
}
