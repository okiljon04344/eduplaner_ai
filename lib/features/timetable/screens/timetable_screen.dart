import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../providers/timetable_provider.dart';
import '../widgets/add_edit_class_sheet.dart';
import '../widgets/day_tab_row.dart';
import '../widgets/schedule_timeline.dart';

/// Schedule tab — a day-tab row (月火水木金) + a vertical timeline of that
/// day's classes, matching the dark-neon design reference.
class TimetableScreen extends ConsumerStatefulWidget {
  const TimetableScreen({super.key});

  @override
  ConsumerState<TimetableScreen> createState() => _TimetableScreenState();
}

class _TimetableScreenState extends ConsumerState<TimetableScreen> {
  late int _selectedDay;

  @override
  void initState() {
    super.initState();
    final weekday = DateTime.now().weekday; // 1=Mon .. 7=Sun
    _selectedDay = (weekday >= 1 && weekday <= 5) ? weekday - 1 : 0;
  }

  @override
  Widget build(BuildContext context) {
    final classCount = ref.watch(timetableStreamProvider).valueOrNull?.length ?? 0;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _Header(classCount: classCount),
            DayTabRow(
              selectedDay: _selectedDay,
              onSelect: (index) => setState(() => _selectedDay = index),
            ),
            Expanded(child: ScheduleTimeline(selectedDay: _selectedDay)),
          ],
        ),
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  final int classCount;
  const _Header({required this.classCount});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0x26A855F7))), // rgba(168,85,247,.15)
      ),
      child: Stack(
        children: [
          Positioned(
            top: -60,
            right: -40,
            child: IgnorePointer(
              child: Container(
                width: 180,
                height: 180,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [AppColors.primaryMid.withValues(alpha: 0.25), AppColors.primaryMid.withValues(alpha: 0)],
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 26),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'TIME TABLE',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                          color: AppColors.primaryMid.withValues(alpha: 0.6),
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text('📅 時間割', style: AppTextStyles.headLG),
                      const SizedBox(height: 4),
                      Text(
                        '今週 $classCount コマ登録済み',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textSecondary.withValues(alpha: 0.7)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: () => showAddEditClassSheet(context, ref),
                  child: Container(
                    width: 44,
                    height: 44,
                    margin: const EdgeInsets.only(top: 2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: AppColors.gradientPrimary,
                      boxShadow: [BoxShadow(color: AppColors.primaryMid.withValues(alpha: 0.5), blurRadius: 20)],
                    ),
                    child: const Icon(Icons.add, color: Colors.white, size: 22),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
