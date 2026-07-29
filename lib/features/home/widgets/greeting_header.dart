import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../assignments/providers/assignments_provider.dart';
import '../../auth/providers/auth_provider.dart';

/// Hero header top row: "online" badge + greeting + department line on the
/// left, settings/notification icon buttons + gradient avatar on the right.
class GreetingHeader extends ConsumerWidget {
  const GreetingHeader({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final urgentCount = ref.watch(urgentAssignmentsCountProvider);
    final initial = (user?.name.isNotEmpty ?? false) ? user!.name.substring(0, 1) : 'U';

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
                  color: AppColors.primaryMid.withValues(alpha: 0.12),
                  border: Border.all(color: AppColors.primaryMid.withValues(alpha: 0.25)),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: AppColors.primaryMid,
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(color: AppColors.primaryMid.withValues(alpha: 0.8), blurRadius: 6)],
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'Online',
                      style: TextStyle(
                        fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.8,
                        color: AppColors.primaryLight,
                        fontFamily: 'Plus Jakarta Sans', fontFamilyFallback: ['NotoSansJP'],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'やあ、${user?.name ?? 'ゲスト'}さん 👋',
                style: const TextStyle(
                  fontSize: 25, fontWeight: FontWeight.w800, letterSpacing: -0.5, height: 1.1,
                  color: Colors.white,
                  fontFamily: 'Plus Jakarta Sans', fontFamilyFallback: ['NotoSansJP'],
                ),
              ),
              const SizedBox(height: 5),
              const Text(
                '今日も一日、頑張ろう！',
                style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary,
                  fontFamily: 'Plus Jakarta Sans', fontFamilyFallback: ['NotoSansJP'],
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
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.08), shape: BoxShape.circle),
            child: const Icon(Icons.settings_outlined, size: 18, color: Colors.white),
          ),
        ),
        const SizedBox(width: 8),
        Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.08), shape: BoxShape.circle),
              child: const Icon(Icons.notifications_outlined, size: 18, color: Colors.white),
            ),
            if (urgentCount > 0)
              Positioned(
                top: -2,
                right: -2,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(color: AppColors.danger, shape: BoxShape.circle, border: Border.all(color: AppColors.bgDeep, width: 1.5)),
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
          margin: const EdgeInsets.only(top: 0),
          decoration: BoxDecoration(
            gradient: AppColors.gradientAvatar,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: AppColors.pink.withValues(alpha: 0.4), blurRadius: 18)],
          ),
          alignment: Alignment.center,
          child: Text(
            initial,
            style: const TextStyle(
              fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white,
              fontFamily: 'Plus Jakarta Sans', fontFamilyFallback: ['NotoSansJP'],
            ),
          ),
        ),
      ],
    );
  }
}
