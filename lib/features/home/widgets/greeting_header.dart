import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../assignments/providers/assignments_provider.dart';
import '../../auth/providers/auth_provider.dart';
import '../../../core/l10n/app_strings.dart';

class GreetingHeader extends ConsumerWidget {
  const GreetingHeader({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final urgentCount = ref.watch(urgentAssignmentsCountProvider);
    final initial = (user?.name.isNotEmpty ?? false) ? user!.name.substring(0, 1) : 'U';
    final onHero = AppColors.isDark ? AppColors.textOnHero : AppColors.textOnHero;
    final heroSub = AppColors.isDark
        ? AppColors.textSecondary
        : Colors.white.withValues(alpha: 0.75);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.isDark
                      ? AppColors.primaryMid.withValues(alpha: 0.12)
                      : Colors.white.withValues(alpha: 0.13),
                  border: Border.all(
                    color: AppColors.isDark
                        ? AppColors.primaryMid.withValues(alpha: 0.25)
                        : Colors.white.withValues(alpha: 0.15),
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: AppColors.isDark ? AppColors.primaryMid : AppColors.success,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: (AppColors.isDark ? AppColors.primaryMid : AppColors.success)
                                .withValues(alpha: 0.8),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      AppStrings.t('home_online'),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                        color: AppColors.isDark ? AppColors.primaryLight : Colors.white,
                        fontFamily: 'Plus Jakarta Sans',
                        fontFamilyFallback: const ['NotoSansJP'],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Text(
                AppStrings.t('home_greeting').replaceAll('{name}', (user?.name.isNotEmpty ?? false) ? user!.name : AppStrings.t('home_guest')),
                style: TextStyle(
                  fontSize: 25,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                  height: 1.1,
                  color: onHero,
                  fontFamily: 'Plus Jakarta Sans',
                  fontFamilyFallback: const ['NotoSansJP'],
                ),
              ),
              const SizedBox(height: 5),
              Text(
                user?.school?.isNotEmpty == true
                    ? user!.school!
                    : AppStrings.t('home_greeting_sub'),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: heroSub,
                  fontFamily: 'Plus Jakarta Sans',
                  fontFamilyFallback: const ['NotoSansJP'],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        GestureDetector(
          onTap: () => context.push('/settings'),
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.iconButtonBg,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.settings_outlined,
              size: 18,
              color: AppColors.isDark ? AppColors.textOnHero : Colors.white,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppColors.iconButtonBg,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.notifications_outlined,
                size: 18,
                color: AppColors.isDark ? AppColors.textOnHero : Colors.white,
              ),
            ),
            if (urgentCount > 0)
              Positioned(
                top: -2,
                right: -2,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: AppColors.danger,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.bgDeep, width: 1.5),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    urgentCount > 9 ? '9+' : '$urgentCount',
                    style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w700, color: Colors.white),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(width: 10),
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            gradient: AppColors.avatarGradient,
            borderRadius: BorderRadius.circular(16),
            border: AppColors.isDark ? null : Border.all(color: Colors.white, width: 2.5),
            boxShadow: AppColors.isDark
                ? [BoxShadow(color: AppColors.pink.withValues(alpha: 0.4), blurRadius: 18)]
                : [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 12)],
          ),
          alignment: Alignment.center,
          child: Text(
            initial,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              fontFamily: 'Plus Jakarta Sans',
              fontFamilyFallback: ['NotoSansJP'],
            ),
          ),
        ),
      ],
    );
  }
}
