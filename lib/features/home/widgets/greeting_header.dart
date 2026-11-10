import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/providers/clock_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../assignments/providers/assignments_provider.dart';
import '../../auth/providers/auth_provider.dart';

/// Home header: today's date, a time-of-day greeting, and one bell button
/// (red dot while assignments are overdue or due within 3 days).
class GreetingHeader extends ConsumerWidget {
  const GreetingHeader({super.key});

  static String greetingKey(DateTime now) => now.hour < 11
      ? 'home_greet_morning'
      : now.hour < 17
          ? 'home_greet_day'
          : 'home_greet_evening';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final urgent = ref.watch(urgentAssignmentsCountProvider);
    final now = ref.watch(minuteTickProvider).valueOrNull ?? DateTime.now();
    final name = (user?.name.isNotEmpty ?? false) ? user!.name : AppStrings.t('home_guest');

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                DateFormat.MMMEd(AppStrings.currentLocale).format(now),
                style: TextStyle(fontSize: 13, height: 1.5, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 2),
              // One line; long names shrink instead of wrapping a lone 「ん」.
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  AppStrings.t(greetingKey(now), {'name': name}),
                  maxLines: 1,
                  style: TextStyle(fontSize: 24, height: 1.4, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Tooltip(
          message: AppStrings.t('home_notifications'),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () => context.go('/assignments'),
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.statGlassFill,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.statGlassBorder),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(Icons.notifications_none_rounded, size: 22, color: AppColors.textPrimary),
                  if (urgent > 0)
                    Positioned(
                      top: 11,
                      right: 12,
                      child: Container(
                        key: const ValueKey('urgent-dot'),
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          color: AppColors.danger,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.statGlassFill, width: 2),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
