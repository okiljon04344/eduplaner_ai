import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toastification/toastification.dart';
import '../../../core/theme/app_colors.dart';
import '../../timetable/providers/timetable_provider.dart';
import '../providers/auth_provider.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
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
      title: const Text('ログインエラー'),
      description: Text(message),
      autoCloseDuration: const Duration(seconds: 3),
    );
  }

  void _showComingSoonToast() {
    toastification.show(
      context: context,
      type: ToastificationType.info,
      style: ToastificationStyle.flat,
      title: const Text('準備中'),
      description: const Text('この機能は近日公開予定です'),
      autoCloseDuration: const Duration(seconds: 2),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loading = ref.watch(authNotifierProvider).isLoading;
    final size = MediaQuery.sizeOf(context);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
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
                              const Text(
                                '学習をスマートに管理しよう',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: AppColors.textSecondary,
                                  fontFamily: 'Plus Jakarta Sans',
                                  fontFamilyFallback: ['NotoSansJP'],
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
                                    const Text(
                                      'AI オンライン',
                                      style: TextStyle(
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
                        const Text(
                          '続けるには方法を選んでください',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13, color: AppColors.textSecondary,
                            fontFamily: 'Plus Jakarta Sans', fontFamilyFallback: ['NotoSansJP'],
                          ),
                        ),
                        const SizedBox(height: 20),
                        GestureDetector(
                          onTap: loading ? null : _signInWithGoogle,
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
                                const Text(
                                  'Googleでログイン',
                                  style: TextStyle(
                                    fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary,
                                    fontFamily: 'Plus Jakarta Sans', fontFamilyFallback: ['NotoSansJP'],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        const Row(
                          children: [
                            Expanded(child: Divider()),
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: 12),
                              child: Text('または', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                            ),
                            Expanded(child: Divider()),
                          ],
                        ),
                        const SizedBox(height: 14),
                        ElevatedButton(
                          onPressed: _showComingSoonToast,
                          child: const Text('メールで登録'),
                        ),
                        const SizedBox(height: 16),
                        TextButton(
                          onPressed: _showComingSoonToast,
                          child: const Text('すでにアカウントをお持ちの方はこちら'),
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
                  child: const Center(child: CircularProgressIndicator(color: AppColors.primaryLight)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

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
            '📅 今日の授業 $count件',
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

