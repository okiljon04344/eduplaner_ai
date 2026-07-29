import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

/// Day-of-week selector for the Schedule timeline — 5 equal-width pills
/// (月火水木金). The active pill gets a purple-tinted glass fill + border;
/// inactive pills stay plain glass. Switching animates via [AnimatedContainer].
class DayTabRow extends StatelessWidget {
  static const days = ['月', '火', '水', '木', '金'];

  final int selectedDay;
  final ValueChanged<int> onSelect;

  const DayTabRow({super.key, required this.selectedDay, required this.onSelect});

  static const _activeBg = Color(0x40A855F7); // rgba(168,85,247,.25)
  static const _activeBorder = Color(0x80A855F7); // rgba(168,85,247,.5)
  static const _activeText = Color(0xFFE879F9);
  static const _inactiveText = Color(0x66C8AAFF); // rgba(200,170,255,.4)

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: const BoxDecoration(
        color: Color(0x05FFFFFF), // rgba(255,255,255,.02)
        border: Border(bottom: BorderSide(color: Color(0x0AFFFFFF))), // rgba(255,255,255,.04)
      ),
      child: Row(
        children: List.generate(days.length, (index) {
          final active = index == selectedDay;
          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: index == days.length - 1 ? 0 : 8),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onSelect(index),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOutExpo,
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                  decoration: BoxDecoration(
                    color: active ? _activeBg : AppColors.surfaceVar,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: active ? _activeBorder : AppColors.border),
                  ),
                  alignment: Alignment.center,
                  child: AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOutExpo,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: active ? _activeText : _inactiveText,
                    ),
                    child: Text(days[index], textAlign: TextAlign.center),
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
