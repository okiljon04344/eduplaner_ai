import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:toastification/toastification.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/responsive.dart';
import '../../../shared/widgets/language_picker_button.dart';
import '../../../shared/widgets/lottie_helpers.dart';
import '../providers/auth_provider.dart';
import '../widgets/google_signin_button.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  @override
  void initState() {
    super.initState();
    // Initialise Google Sign-In now so the web SDK button (see
    // _GoogleSignInArea) is ready to render.
    if (kIsWeb) {
      unawaited(ref.read(authRepositoryProvider).ensureGoogleSignInReady());
    }
  }

  Future<void> _signInWithGoogle() async {
    try {
      await ref.read(authNotifierProvider.notifier).signInWithGoogle();
      final state = ref.read(authNotifierProvider);
      if (state.hasError && mounted) {
        _showErrorToast(state.error.toString().replaceAll('Exception: ', ''));
      }
    } catch (e) {
      if (mounted) _showErrorToast(e.toString().replaceAll('Exception: ', ''));
    }
  }

  void _showErrorToast(String message) {
    toastification.show(
      context: context,
      type: ToastificationType.error,
      style: ToastificationStyle.flat,
      title: Text(AppStrings.t('login_error')),
      description: Text(message),
      autoCloseDuration: const Duration(seconds: 3),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loading = ref.watch(authNotifierProvider).isLoading;
    final size = MediaQuery.sizeOf(context);

    final isDesktop = size.width >= 800;

    if (isDesktop) {
      return _DesktopLoginLayout(
          loading: loading, onSignInWithGoogle: _signInWithGoogle);
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: ResponsiveBody(
          maxWidth: 480,
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: size.height * 0.42,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            gradient: AppColors.brandPanelGradient,
                            borderRadius: const BorderRadius.only(
                              bottomLeft: Radius.circular(40),
                              bottomRight: Radius.circular(40),
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: const BorderRadius.only(
                              bottomLeft: Radius.circular(40),
                              bottomRight: Radius.circular(40),
                            ),
                            child: Stack(
                              children: [
                                const _FloatingOrbs(),
                                CustomPaint(
                                    painter: _DotPatternPainter(),
                                    size: Size.infinite),
                              ],
                            ),
                          ),
                        ),
                        Positioned(
                          top: 16,
                          right: 16,
                          child:
                              LanguagePickerButton(color: AppColors.textOnHero),
                        ),
                        Positioned.fill(
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 56,
                                  height: 56,
                                  decoration: BoxDecoration(
                                    gradient: AppColors.gradientPrimary,
                                    borderRadius: BorderRadius.circular(18),
                                    boxShadow: [
                                      BoxShadow(
                                          color: AppColors.primaryMid
                                              .withValues(alpha: 0.6),
                                          blurRadius: 24)
                                    ],
                                  ),
                                  child: const Icon(Icons.auto_awesome,
                                      size: 28, color: Colors.white),
                                ).animate().moveY(
                                    begin: 8,
                                    end: 0,
                                    duration: 800.ms,
                                    curve: Curves.easeOut),
                                const SizedBox(height: 14),
                                Text(
                                  'EduPlanner AI',
                                  style: TextStyle(
                                    fontSize: 26,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.4,
                                    color: AppColors.textOnHero,
                                    fontFamily: 'Plus Jakarta Sans',
                                    fontFamilyFallback: const ['NotoSansJP'],
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  AppStrings.t('login_welcome_sub'),
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: AppColors.textSecondary,
                                    fontFamily: 'Plus Jakarta Sans',
                                    fontFamilyFallback: const ['NotoSansJP'],
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 4),
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                        color: AppColors.primaryMid
                                            .withValues(alpha: 0.35)),
                                    color: AppColors.primaryMid
                                        .withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 6,
                                        height: 6,
                                        decoration: BoxDecoration(
                                          color: AppColors.success,
                                          shape: BoxShape.circle,
                                          boxShadow: [
                                            BoxShadow(
                                                color: AppColors.success
                                                    .withValues(alpha: 0.8),
                                                blurRadius: 6)
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        AppStrings.t('login_ai_online'),
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.accentText,
                                          fontFamily: 'Plus Jakarta Sans',
                                          fontFamilyFallback: const [
                                            'NotoSansJP'
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(
                          top: 28, left: 24, right: 24, bottom: 32),
                      child: Column(
                        children: [
                          Text(
                            AppStrings.t('login_subtitle'),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondary,
                              fontFamily: 'Plus Jakarta Sans',
                              fontFamilyFallback: const ['NotoSansJP'],
                            ),
                          ),
                          const SizedBox(height: 20),
                          _GoogleSignInArea(
                              loading: loading, onTap: _signInWithGoogle),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              const Expanded(child: Divider()),
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 12),
                                child: Text(AppStrings.t('login_or'),
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: AppColors.textMuted)),
                              ),
                              const Expanded(child: Divider()),
                            ],
                          ),
                          const SizedBox(height: 14),
                          ElevatedButton(
                            onPressed: () => context.push('/login/signup'),
                            child: Text(AppStrings.t('login_email_register')),
                          ),
                          const SizedBox(height: 16),
                          TextButton(
                            onPressed: () => context.push('/login/email'),
                            child: Text(AppStrings.t('login_have_account')),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              if (loading)
                Positioned.fill(
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.5),
                    child: Center(child: AppLottie.loading(size: 72)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DesktopLoginLayout extends StatelessWidget {
  final bool loading;
  final VoidCallback onSignInWithGoogle;
  const _DesktopLoginLayout(
      {required this.loading, required this.onSignInWithGoogle});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Row(
        children: [
          Expanded(
            flex: 5,
            child: Container(
              decoration: BoxDecoration(gradient: AppColors.brandPanelGradient),
              clipBehavior: Clip.hardEdge,
              child: Stack(
                children: [
                  const Positioned.fill(child: _FloatingOrbs()),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 56, vertical: 48),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            gradient: AppColors.gradientPrimary,
                            borderRadius: BorderRadius.circular(18),
                            boxShadow: [
                              BoxShadow(
                                  color: AppColors.primaryMid
                                      .withValues(alpha: 0.6),
                                  blurRadius: 24)
                            ],
                          ),
                          child: const Icon(Icons.auto_awesome,
                              size: 28, color: Colors.white),
                        ).animate().moveY(
                            begin: 8,
                            end: 0,
                            duration: 800.ms,
                            curve: Curves.easeOut),
                        const SizedBox(height: 24),
                        Text(
                          'EduPlanner AI',
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.w900,
                            color: AppColors.textOnHero,
                            letterSpacing: -0.5,
                            fontFamily: 'Plus Jakarta Sans',
                            fontFamilyFallback: const ['NotoSansJP'],
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          AppStrings.t('login_welcome_sub'),
                          style: TextStyle(
                            fontSize: 16,
                            height: 1.5,
                            color: AppColors.textSecondary,
                            fontFamily: 'Plus Jakarta Sans',
                            fontFamilyFallback: const ['NotoSansJP'],
                          ),
                        ),
                        const SizedBox(height: 48),
                        ..._desktopFeatures.map((f) => Padding(
                              padding: const EdgeInsets.only(bottom: 20),
                              child: Row(
                                children: [
                                  Container(
                                    width: 38,
                                    height: 38,
                                    decoration: BoxDecoration(
                                      color: f.$3.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(11),
                                    ),
                                    child: Icon(f.$2, size: 18, color: f.$3),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(f.$1,
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w700,
                                              color: AppColors.textOnHero,
                                              fontFamily: 'Plus Jakarta Sans',
                                              fontFamilyFallback: const [
                                                'NotoSansJP'
                                              ],
                                            )),
                                        Text(f.$4,
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: AppColors.textMuted,
                                              fontFamily: 'Plus Jakarta Sans',
                                              fontFamilyFallback: const [
                                                'NotoSansJP'
                                              ],
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
                                    fontSize: 26,
                                    fontWeight: FontWeight.w900,
                                    color: AppColors.textPrimary,
                                    letterSpacing: -0.4,
                                    fontFamily: 'Plus Jakarta Sans',
                                    fontFamilyFallback: const ['NotoSansJP'],
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  AppStrings.t('login_subtitle'),
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: AppColors.textSecondary,
                                    fontFamily: 'Plus Jakarta Sans',
                                    fontFamilyFallback: const ['NotoSansJP'],
                                  ),
                                ),
                                const SizedBox(height: 32),
                                _GoogleSignInArea(
                                    loading: loading,
                                    onTap: onSignInWithGoogle),
                                const SizedBox(height: 16),
                                Row(
                                  children: [
                                    const Expanded(child: Divider()),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12),
                                      child: Text(AppStrings.t('login_or'),
                                          style: TextStyle(
                                              fontSize: 12,
                                              color: AppColors.textMuted)),
                                    ),
                                    const Expanded(child: Divider()),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                ElevatedButton(
                                  onPressed: () =>
                                      context.push('/login/signup'),
                                  child: Text(
                                      AppStrings.t('login_email_register')),
                                ),
                                const SizedBox(height: 14),
                                TextButton(
                                  onPressed: () => context.push('/login/email'),
                                  child:
                                      Text(AppStrings.t('login_have_account')),
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
                                style: TextButton.styleFrom(
                                    foregroundColor: AppColors.textMuted),
                              ),
                            ),
                          ),
                        ],
                      ),
                      Positioned(
                        top: -80,
                        right: 0,
                        child:
                            LanguagePickerButton(color: AppColors.textPrimary),
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

// A getter, not a top-level final, so the strings follow locale changes.
List<(String, IconData, Color, String)> get _desktopFeatures => [
      (
        AppStrings.t('feat_timetable'),
        Icons.calendar_month_outlined,
        const Color(0xFF06B6D4),
        AppStrings.t('feat_timetable_desc')
      ),
      (
        AppStrings.t('feat_assignments'),
        Icons.assignment_outlined,
        const Color(0xFF10B981),
        AppStrings.t('feat_assignments_desc')
      ),
      (
        AppStrings.t('feat_ai_chat'),
        Icons.smart_toy_outlined,
        const Color(0xFFA855F7),
        AppStrings.t('feat_ai_chat_desc')
      ),
      (
        AppStrings.t('feat_quiz'),
        Icons.quiz_outlined,
        const Color(0xFFF59E0B),
        AppStrings.t('feat_quiz_desc')
      ),
    ];

/// Google sign-in entry point for the mobile and desktop layouts.
///
/// Web has no `authenticate()`, so it shows the SDK-rendered button (see
/// `google_signin_button.dart`), which completes sign-in through
/// `AuthRepository`'s `authenticationEvents` listener rather than [onTap].
/// Other platforms use the app's own button wired to [onTap].
class _GoogleSignInArea extends StatelessWidget {
  final bool loading;
  final VoidCallback onTap;
  const _GoogleSignInArea({required this.loading, required this.onTap});

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return SizedBox(
          height: 52, child: Center(child: renderGoogleSignInButton()));
    }
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: AppColors.surfaceVar,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'assets/images/google_logo.png',
              width: 20,
              height: 20,
              errorBuilder: (context, error, stackTrace) => Container(
                width: 20,
                height: 20,
                decoration: const BoxDecoration(
                    color: Color(0xFF4285F4), shape: BoxShape.circle),
                alignment: Alignment.center,
                child: const Text(
                  'G',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.white),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              AppStrings.t('login_google'),
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
                fontFamily: 'Plus Jakarta Sans',
                fontFamilyFallback: const ['NotoSansJP'],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Slowly pulsing radial-gradient blobs behind the brand panel.
class _FloatingOrbs extends StatelessWidget {
  const _FloatingOrbs();

  @override
  Widget build(BuildContext context) {
    Widget orb(
        {required double top,
        required double left,
        required double size,
        required Color color,
        required int delayMs}) {
      return Positioned(
        top: top,
        left: left,
        child: IgnorePointer(
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [
                color.withValues(alpha: 0.32),
                color.withValues(alpha: 0)
              ]),
            ),
          )
              .animate(delay: delayMs.ms)
              .scale(
                  begin: const Offset(0.9, 0.9),
                  end: const Offset(1, 1),
                  duration: 1600.ms,
                  curve: Curves.easeOut)
              .fadeIn(duration: 1000.ms),
        ),
      );
    }

    return Stack(
      children: [
        orb(
            top: -60,
            left: -40,
            size: 220,
            color: AppColors.primary,
            delayMs: 0),
        orb(
            top: 120,
            left: 260,
            size: 160,
            color: AppColors.primaryLight,
            delayMs: 400),
        orb(
            top: 320,
            left: -20,
            size: 180,
            color: AppColors.primaryMid,
            delayMs: 800),
      ],
    );
  }
}

class _DotPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.primaryLight.withValues(alpha: 0.08);
    const spacing = 24.0;
    const radius = 3.0;
    for (double y = 0; y < size.height; y += spacing) {
      for (double x = 0; x < size.width; x += spacing) {
        canvas.drawCircle(Offset(x, y), radius, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
