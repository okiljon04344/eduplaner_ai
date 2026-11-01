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
import '../widgets/desktop_login_layout.dart';
import '../widgets/google_signin_area.dart';
import '../widgets/login_orbs.dart';

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
    // web SDK button (see GoogleSignInArea) is ready to render, rather
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
      return DesktopLoginLayout(loading: loading, onSignInWithGoogle: _signInWithGoogle);
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
                              const FloatingOrbs(),
                              CustomPaint(painter: DotPatternPainter(), size: Size.infinite),
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                        top: 16,
                        right: 16,
                        child: LanguagePickerButton(color: AppColors.textOnHero),
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
                              )
                                  .animate()
                                  .moveY(begin: 8, end: 0, duration: 800.ms, curve: Curves.easeOut),
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
                                      style: TextStyle(
                                        fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.accentText,
                                        fontFamily: 'Plus Jakarta Sans', fontFamilyFallback: const ['NotoSansJP'],
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
                    padding: const EdgeInsets.only(top: 28, left: 24, right: 24, bottom: 32),
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
                        GoogleSignInArea(loading: loading, onTap: _signInWithGoogle),
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
