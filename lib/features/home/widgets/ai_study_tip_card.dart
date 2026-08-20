import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../providers/home_provider.dart';
import '../../../core/l10n/app_strings.dart';

/// AI banner card at the bottom of Home — dark gradient, neon pulsing
/// border, floating bot emoji, and the day's Gemini-generated study tip as
/// the subtitle. Tapping it opens the AI chat tab.
class AiStudyTipCard extends ConsumerStatefulWidget {
  const AiStudyTipCard({super.key});

  @override
  ConsumerState<AiStudyTipCard> createState() => _AiStudyTipCardState();
}

class _AiStudyTipCardState extends ConsumerState<AiStudyTipCard> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tip = ref.watch(aiStudyTipProvider);
    return GestureDetector(
      onTap: () => context.go('/ai'),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: AppColors.aiBannerGradient,
          borderRadius: BorderRadius.circular(AppColors.isDark ? 24 : 22),
          border: Border.all(
            color: AppColors.isDark
                ? AppColors.primaryMid.withValues(alpha: 0.4)
                : AppColors.primaryIndigo.withValues(alpha: 0.3),
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.isDark
                  ? AppColors.primaryMid.withValues(alpha: 0.2)
                  : AppColors.primaryIndigo.withValues(alpha: 0.2),
              blurRadius: 32,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // RepaintBoundary isolates the 60fps floating-emoji animation so the
            // rest of the card (text, arrow, gradient decoration) is not repainted
            // every frame.
            RepaintBoundary(
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, child) => Transform.translate(
                  offset: Offset(0, -6 * Curves.easeInOut.transform(_controller.value)),
                  child: child,
                ),
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: AppColors.gradientPrimary,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [BoxShadow(color: AppColors.primaryMid.withValues(alpha: 0.7), blurRadius: 20)],
                  ),
                  alignment: Alignment.center,
                  child: const Text('🤖', style: TextStyle(fontSize: 22)),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppStrings.t('home_ai_title'),
                    style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: -0.2, color: AppColors.textOnHero,
                      fontFamily: 'Plus Jakarta Sans', fontFamilyFallback: const ['NotoSansJP'],
                    ),
                  ),
                  const SizedBox(height: 4),
                  tip.when(
                    data: (text) => Text(
                      text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w500, height: 1.4,
                        color: AppColors.textSecondary,
                        fontFamily: 'Plus Jakarta Sans', fontFamilyFallback: const ['NotoSansJP'],
                      ),
                    ),
                    loading: () => SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textSecondary),
                    ),
                    error: (_, __) => Text(
                      AppStrings.t('home_ai_fallback'),
                      style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 34,
              height: 34,
              margin: const EdgeInsets.only(top: 2),
              decoration: BoxDecoration(
                color: AppColors.primaryMid.withValues(alpha: 0.2),
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.primaryMid.withValues(alpha: 0.4)),
              ),
              child: const Icon(Icons.arrow_forward, size: 15, color: AppColors.primaryLight),
            ),
          ],
        ),
      ),
    );
  }
}
