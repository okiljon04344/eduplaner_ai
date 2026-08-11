import 'package:flutter/material.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_colors.dart';

class DayTabRow extends StatelessWidget {
  /// Localized weekday labels (Mon–Fri), resolved at read time.
  static List<String> get days => [
        AppStrings.t('day_mon'),
        AppStrings.t('day_tue'),
        AppStrings.t('day_wed'),
        AppStrings.t('day_thu'),
        AppStrings.t('day_fri'),
      ];

  final int selectedDay;
  final ValueChanged<int> onSelect;
  final DateTime weekStart;

  const DayTabRow({super.key, required this.selectedDay, required this.onSelect, required this.weekStart});

  bool _isToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year && date.month == now.month && date.day == now.day;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(
        color: AppColors.isDark ? const Color(0x05FFFFFF) : AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.dividerSubtle)),
      ),
      child: Row(
        children: List.generate(days.length, (index) {
          final active = index == selectedDay;
          final date = weekStart.add(Duration(days: index));
          final today = _isToday(date);

          final activeBg = AppColors.isDark
              ? const Color(0x40A855F7)
              : const Color(0xFF1A1035);
          final activeText = AppColors.isDark ? const Color(0xFFE879F9) : Colors.white;
          final inactiveBg = AppColors.surfaceVar;
          final inactiveText = AppColors.isDark
              ? const Color(0x66C8AAFF)
              : const Color(0xFF6B7280);

          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: index == days.length - 1 ? 0 : 8),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onSelect(index),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOutExpo,
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                  decoration: BoxDecoration(
                    color: active ? activeBg : inactiveBg,
                    borderRadius: BorderRadius.circular(AppColors.isDark ? 16 : 14),
                    border: Border.all(
                      color: active
                          ? (AppColors.isDark ? const Color(0x80A855F7) : Colors.transparent)
                          : (today ? AppColors.primaryMid.withValues(alpha: 0.5) : AppColors.border),
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOutExpo,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: active ? activeText : inactiveText,
                        ),
                        child: Text(days[index], textAlign: TextAlign.center),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${date.month}/${date.day}',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: today ? FontWeight.w700 : FontWeight.w500,
                          color: active
                              ? activeText.withValues(alpha: 0.8)
                              : (today ? AppColors.primaryMid : inactiveText.withValues(alpha: 0.7)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
