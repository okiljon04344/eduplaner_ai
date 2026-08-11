import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:toastification/toastification.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/responsive.dart';
import '../../../shared/widgets/language_picker_button.dart';
import '../../../shared/widgets/lottie_helpers.dart';
import '../../timetable/providers/timetable_provider.dart';
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
    // Kick off Google Sign-In init as soon as this screen appears so the
    // web SDK button (see _GoogleSignInArea) is ready to render, rather
    // than only starting once the user taps something.
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
      return _DesktopLoginLayout(loading: loading, onSignInWithGoogle: _signInWithGoogle);
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
                        decoration: const BoxDecoration(
                          gradient: AppColors.gradientDark,
                          borderRadius: BorderRadius.only(
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
                              Positioned(
                                top: -60,
                                right: -40,
                                child: Container(
                                  width: 220,
                                  height: 220,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: RadialGradient(colors: [AppColors.primaryMid.withValues(alpha: 0.3), Colors.transparent]),
                                  ),
                                ),
                              ),
                              CustomPaint(painter: _DotPatternPainter(), size: Size.infinite),
                            ],
                          ),
                        ),
                      ),
                      const Positioned(
                        top: 16,
                        right: 16,
                        child: LanguagePickerButton(),
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
                                  boxShadow: [BoxShadow(color: AppColors.primaryMid.withValues(alpha: 0.6), blurRadius: 24)],
                                ),
                                child: const Icon(Icons.auto_awesome, size: 28, color: Colors.white),
                              ),
                              const SizedBox(height: 14),
                              const Text(
                                'EduPlanner AI',
                                style: TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.4,
                                  color: Colors.white,
                                  fontFamily: 'Plus Jakarta Sans',
                                  fontFamilyFallback: ['NotoSansJP'],
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
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                decoration: BoxDecoration(
                                  border: Border.all(color: AppColors.primaryMid.withValues(alpha: 0.35)),
                                  color: AppColors.primaryMid.withValues(alpha: 0.15),
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
                                        boxShadow: [BoxShadow(color: AppColors.success.withValues(alpha: 0.8), blurRadius: 6)],
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      AppStrings.t('login_ai_online'),
                                      style: const TextStyle(
                                        fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.primaryLight,
                                        fontFamily: 'Plus Jakarta Sans', fontFamilyFallback: ['NotoSansJP'],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: -20,
                        left: 0,
                        right: 0,
                        child: Center(child: _TodayClassesPill()),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 44, left: 24, right: 24, bottom: 32),
                    child: Column(
                      children: [
                        Text(
                          AppStrings.t('login_subtitle'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13, color: AppColors.textSecondary,
                            fontFamily: 'Plus Jakarta Sans', fontFamilyFallback: const ['NotoSansJP'],
                          ),
                        ),
                        const SizedBox(height: 20),
                        _GoogleSignInArea(loading: loading, onTap: _signInWithGoogle),
                        const SizedBox(height: 14),
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

// ─── Desktop 2-column login layout ───────────────────────────────────────────

class _DesktopLoginLayout extends StatelessWidget {
  final bool loading;
  final VoidCallback onSignInWithGoogle;
  const _DesktopLoginLayout({required this.loading, required this.onSignInWithGoogle});

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
              decoration: const BoxDecoration(gradient: AppColors.gradientDark),
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
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'EduPlanner AI',
                    style: TextStyle(
                      fontSize: 32, fontWeight: FontWeight.w900, color: Colors.white,
                      letterSpacing: -0.5,
                      fontFamily: 'Plus Jakarta Sans', fontFamilyFallback: ['NotoSansJP'],
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
                              Text(f.$1, style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white,
                                fontFamily: 'Plus Jakarta Sans', fontFamilyFallback: ['NotoSansJP'],
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
                      Positioned(
                        top: -80,
                        right: 0,
                        child: LanguagePickerButton(color: AppColors.textPrimary),
                      ),
                      Column(
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
                          _GoogleSignInArea(loading: loading, onTap: onSignInWithGoogle),
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
                          const SizedBox(height: 24),
                          TextButton.icon(
                            onPressed: () => context.go('/'),
                            icon: const Icon(Icons.arrow_back, size: 14),
                            label: Text(AppStrings.t('login_back_to_top')),
                            style: TextButton.styleFrom(foregroundColor: AppColors.textMuted),
                          ),
                        ],
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

final _desktopFeatures = [
  (AppStrings.t('feat_timetable'), Icons.calendar_month_outlined, const Color(0xFF06B6D4), AppStrings.t('feat_timetable_desc')),
  (AppStrings.t('feat_assignments'), Icons.assignment_outlined, const Color(0xFF10B981), AppStrings.t('feat_assignments_desc')),
  (AppStrings.t('feat_ai_chat'), Icons.smart_toy_outlined, const Color(0xFFA855F7), AppStrings.t('feat_ai_chat_desc')),
  (AppStrings.t('feat_quiz'), Icons.quiz_outlined, const Color(0xFFF59E0B), AppStrings.t('feat_quiz_desc')),
];

class _TodayClassesPill extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(todayClassesProvider).length;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.bgLayer,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.borderPrimary),
        boxShadow: [BoxShadow(color: AppColors.primaryMid.withValues(alpha: 0.35), blurRadius: 16, offset: const Offset(0, 4))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.calendar_today_outlined, size: 16, color: AppColors.primaryLight),
          const SizedBox(width: 6),
          Text(
            AppStrings.t('login_today_classes', {'n': count}),
            style: const TextStyle(
              fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primaryLight,
              fontFamily: 'Plus Jakarta Sans', fontFamilyFallback: ['NotoSansJP'],
            ),
          ),
        ],
      ),
    );
  }
}

/// Google sign-in entry point, shared by the mobile and desktop layouts.
///
/// Web has no `authenticate()` support — `GoogleSignIn` on web requires a
/// button rendered by Google's own SDK (see `google_signin_button.dart`),
/// which handles the click internally and completes sign-in via
/// `AuthRepository`'s `authenticationEvents` listener, not [onTap]. Other
/// platforms keep the app's own styled button wired to [onTap].
class _GoogleSignInArea extends StatelessWidget {
  final bool loading;
  final VoidCallback onTap;
  const _GoogleSignInArea({required this.loading, required this.onTap});

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return SizedBox(height: 52, child: Center(child: renderGoogleSignInButton()));
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
                decoration: const BoxDecoration(color: Color(0xFF4285F4), shape: BoxShape.circle),
                alignment: Alignment.center,
                child: const Text(
                  'G',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              AppStrings.t('login_google'),
              style: TextStyle(
                fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary,
                fontFamily: 'Plus Jakarta Sans', fontFamilyFallback: const ['NotoSansJP'],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DotPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = AppColors.primaryLight.withValues(alpha: 0.08);
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

