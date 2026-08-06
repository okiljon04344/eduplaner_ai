import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../providers/assignments_provider.dart';

class FilterChipsRow extends ConsumerWidget {
  const FilterChipsRow({super.key});

  static const _filters = ['すべて', '未着手', '進行中', '完了'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedFilterProvider);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      decoration: BoxDecoration(
        color: AppColors.isDark ? const Color(0x05FFFFFF) : AppColors.background,
        border: Border(bottom: BorderSide(color: AppColors.dividerSubtle)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: _filters.map((f) {
            final isSelected = f == selected;
            final activeColor = AppColors.isDark ? AppColors.cyan : AppColors.primaryIndigo;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => ref.read(selectedFilterProvider.notifier).state = f,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? (AppColors.isDark ? activeColor.withValues(alpha: 0.15) : activeColor)
                        : (AppColors.isDark ? AppColors.surfaceVar : AppColors.surfaceVar),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSelected
                          ? (AppColors.isDark ? activeColor.withValues(alpha: 0.3) : Colors.transparent)
                          : AppColors.border,
                    ),
                  ),
                  child: Text(
                    f,
                    style: TextStyle(
                      fontFamily: 'Plus Jakarta Sans',
                      fontFamilyFallback: const ['NotoSansJP'],
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: isSelected
                          ? (AppColors.isDark ? activeColor : Colors.white)
                          : (AppColors.isDark ? AppColors.textSecondary : const Color(0xFF374151)),
                    ),
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
