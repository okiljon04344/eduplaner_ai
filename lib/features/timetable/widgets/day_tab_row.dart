import 'package:flutter/material.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion.dart';
import '../../../shared/widgets/pressable.dart';

/// Horizontal tab selector for weekdays Monday through Friday, highlighting alert days with badges.
///
/// UZ: Dushanbadan jumagacha bo'lgan hafta kunlari uchun gorizontal tab tanlagich,
/// ogohlantirish kunlarini nishonlar bilan ajratib ko'rsatadi.
class DayTabRow extends StatelessWidget {
  /// Localized weekday labels (Mon–Fri), resolved at read time.
  ///
  /// UZ: Mahalliylashtirilgan hafta kuni yorliqlari (Dush–Jum), o'qish vaqtida aniqlanadi.
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
  ///
  /// UZ: Bekor qilish yoki o'zgarish mavjud bo'lgan kun indekslari (0 = Dush): qizil nuqta.
  final Set<int> alertDays;

  /// Outer padding, defaults to zero when rendered inside the top glass panel.
  ///
  /// UZ: Tashqi padding, yuqori shisha panel ichida chizilganda standart bo'yicha nolga teng.
  final EdgeInsetsGeometry padding;

  const DayTabRow({
    super.key,
    required this.selectedDay,
    required this.onSelect,
    required this.weekStart,
    this.alertDays = const {},
    this.padding = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    final isReduced = reduceMotion(context);
    final row = Row(
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
              child: Pressable(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onSelect(index),
                  child: AnimatedContainer(
                    duration: isReduced ? Duration.zero : const Duration(milliseconds: 200),
                    curve: AppMotion.strongEaseOut,
                    height: 64,
                    decoration: BoxDecoration(
                      color: active ? AppColors.primary : AppColors.statGlassFill,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: active ? AppColors.primary : AppColors.statGlassBorder),
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
          ),
        );
      }),
    );

    if (padding != EdgeInsets.zero) {
      return Padding(padding: padding, child: row);
    }
    return row;
  }
}
