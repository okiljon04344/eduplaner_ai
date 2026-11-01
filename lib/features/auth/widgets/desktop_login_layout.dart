import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/language_picker_button.dart';
import '../../../shared/widgets/lottie_helpers.dart';
import 'google_signin_area.dart';
import 'login_orbs.dart';

// ─── Desktop 2-column login layout ───────────────────────────────────────────

class DesktopLoginLayout extends StatelessWidget {
  final bool loading;
  final VoidCallback onSignInWithGoogle;
  const DesktopLoginLayout({super.key, required this.loading, required this.onSignInWithGoogle});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Row(
        children: [
          // Left: brand panel
          Expanded(
            flex: 5,
            child: Container(
              decoration: BoxDecoration(gradient: AppColors.brandPanelGradient),
              clipBehavior: Clip.hardEdge,
              child: Stack(
                children: [
                  const Positioned.fill(child: FloatingOrbs()),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 56, vertical: 48),
                    child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 56, height: 56,
                    decoration: BoxDecoration(
                      gradient: AppColors.gradientPrimary,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [BoxShadow(color: AppColors.primaryMid.withValues(alpha: 0.6), blurRadius: 24)],
                    ),
                    child: const Icon(Icons.auto_awesome, size: 28, color: Colors.white),
                  )
                      .animate()
                      .moveY(begin: 8, end: 0, duration: 800.ms, curve: Curves.easeOut),
                  const SizedBox(height: 24),
                  Text(
                    'EduPlanner AI',
                    style: TextStyle(
                      fontSize: 32, fontWeight: FontWeight.w900, color: AppColors.textOnHero,
                      letterSpacing: -0.5,
                      fontFamily: 'Plus Jakarta Sans', fontFamilyFallback: const ['NotoSansJP'],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    AppStrings.t('login_welcome_sub'),
                    style: TextStyle(
                      fontSize: 16, height: 1.5, color: AppColors.textSecondary,
                      fontFamily: 'Plus Jakarta Sans', fontFamilyFallback: const ['NotoSansJP'],
                    ),
                  ),
                  const SizedBox(height: 48),
                  ..._desktopFeatures.map((f) => Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: Row(
                      children: [
                        Container(
                          width: 38, height: 38,
                          decoration: BoxDecoration(
                            color: f.$3.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(11),
                          ),
                          child: Icon(f.$2, size: 18, color: f.$3),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(f.$1, style: TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textOnHero,
                                fontFamily: 'Plus Jakarta Sans', fontFamilyFallback: const ['NotoSansJP'],
                              )),
                              Text(f.$4, style: TextStyle(
                                fontSize: 11, color: AppColors.textMuted,
                                fontFamily: 'Plus Jakarta Sans', fontFamilyFallback: const ['NotoSansJP'],
                              )),
                            ],
                          ),
                        ),
                      ],
                    ),
                  )),
                ],
              ),
                  ),
                ],
              ),
            ),
          ),

          // Right: login form
          Expanded(
            flex: 4,
            child: Container(
              color: AppColors.background,
              padding: const EdgeInsets.symmetric(horizontal: 56),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 380),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                      Container(
                        padding: const EdgeInsets.all(32),
                        decoration: BoxDecoration(
                          color: AppColors.cardSurface,
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(color: AppColors.cardStroke),
                          boxShadow: AppColors.cardShadow,
                        ),
                        child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            AppStrings.t('login_title'),
                            style: TextStyle(
                              fontSize: 26, fontWeight: FontWeight.w900,
                              color: AppColors.textPrimary, letterSpacing: -0.4,
                              fontFamily: 'Plus Jakarta Sans', fontFamilyFallback: const ['NotoSansJP'],
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            AppStrings.t('login_subtitle'),
                            style: TextStyle(
                              fontSize: 13, color: AppColors.textSecondary,
                              fontFamily: 'Plus Jakarta Sans', fontFamilyFallback: const ['NotoSansJP'],
                            ),
                          ),
                          const SizedBox(height: 32),
                          GoogleSignInArea(loading: loading, onTap: onSignInWithGoogle),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              const Expanded(child: Divider()),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                child: Text(AppStrings.t('login_or'), style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                              ),
                              const Expanded(child: Divider()),
                            ],
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: () => context.push('/login/signup'),
                            child: Text(AppStrings.t('login_email_register')),
                          ),
                          const SizedBox(height: 14),
                          TextButton(
                            onPressed: () => context.push('/login/email'),
                            child: Text(AppStrings.t('login_have_account')),
                          ),
                        ],
                      ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Center(
                          child: TextButton.icon(
                            onPressed: () => context.go('/'),
                            icon: const Icon(Icons.arrow_back, size: 14),
                            label: Text(AppStrings.t('login_back_to_top')),
                            style: TextButton.styleFrom(foregroundColor: AppColors.textMuted),
                          ),
                        ),
                      ),
                        ],
                      ),
                      Positioned(
                        top: -80,
                        right: 0,
                        child: LanguagePickerButton(color: AppColors.textPrimary),
                      ),
                      if (loading)
                        Positioned.fill(
                          child: Container(
                            color: AppColors.background.withValues(alpha: 0.7),
                            child: Center(child: AppLottie.loading(size: 72)),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Getter (not a top-level const/final) so it re-resolves in the currently
// loaded locale — a plain `final` would freeze these strings at first
// access and never update when the user switches language.
List<(String, IconData, Color, String)> get _desktopFeatures => [
  (AppStrings.t('feat_timetable'), Icons.calendar_month_outlined, const Color(0xFF06B6D4), AppStrings.t('feat_timetable_desc')),
  (AppStrings.t('feat_assignments'), Icons.assignment_outlined, const Color(0xFF10B981), AppStrings.t('feat_assignments_desc')),
  (AppStrings.t('feat_ai_chat'), Icons.smart_toy_outlined, const Color(0xFFA855F7), AppStrings.t('feat_ai_chat_desc')),
  (AppStrings.t('feat_quiz'), Icons.quiz_outlined, const Color(0xFFF59E0B), AppStrings.t('feat_quiz_desc')),
];
