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

  /// Day indexes (0 = Mon) that carry a cancellation or change: red dot.
  final Set<int> alertDays;

  const DayTabRow({
    super.key,
    required this.selectedDay,
    required this.onSelect,
    required this.weekStart,
    this.alertDays = const {},
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: Row(
        children: List.generate(days.length, (index) {
          final active = index == selectedDay;
          final date = weekStart.add(Duration(days: index));
          final fg = active ? AppColors.onPrimary : AppColors.textPrimary;
          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: index == days.length - 1 ? 0 : 8),
              child: Semantics(
                button: true,
                selected: active,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onSelect(index),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    height: 64,
                    decoration: BoxDecoration(
                      color: active ? AppColors.primary : AppColors.cardSurface,
                      borderRadius: BorderRadius.circular(16),
                      border: active ? null : Border.all(color: AppColors.cardStroke),
                    ),
                    child: Stack(
                      children: [
                        Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(days[index],
                                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: fg)),
                              const SizedBox(height: 2),
                              Text(
                                '${date.day}',
                                style: TextStyle(
                                  fontFamily: 'Space Grotesk',
                                  fontFamilyFallback: const ['Plus Jakarta Sans'],
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: fg,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (alertDays.contains(index))
                          Positioned(
                            top: 8,
                            right: 10,
                            child: Container(
                              width: 7,
                              height: 7,
                              decoration: const BoxDecoration(color: AppColors.danger, shape: BoxShape.circle),
                            ),
                          ),
                      ],
                    ),
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
