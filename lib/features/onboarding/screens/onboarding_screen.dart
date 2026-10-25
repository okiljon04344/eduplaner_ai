import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../providers/onboarding_provider.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  // A getter, not a const, so titles and subtitles follow the current locale.
  static List<_PageData> get _pages => [
        _PageData(
          icon: Icons.auto_awesome,
          color: AppColors.blue,
          accentColor: const Color(0xFF2563EB),
          title: AppStrings.t('onboard_1_title'),
          subtitle: AppStrings.t('onboard_1_sub'),
        ),
        _PageData(
          icon: Icons.calendar_month_outlined,
          color: const Color(0xFF06B6D4),
          accentColor: const Color(0xFF0891B2),
          title: AppStrings.t('onboard_2_title'),
          subtitle: AppStrings.t('onboard_2_sub'),
        ),
        _PageData(
          icon: Icons.assignment_outlined,
          color: const Color(0xFF10B981),
          accentColor: const Color(0xFF059669),
          title: AppStrings.t('onboard_3_title'),
          subtitle: AppStrings.t('onboard_3_sub'),
        ),
        _PageData(
          icon: Icons.smart_toy_outlined,
          color: AppColors.amber,
          accentColor: AppColors.amberDeep,
          title: AppStrings.t('onboard_4_title'),
          subtitle: AppStrings.t('onboard_4_sub'),
        ),
      ];

  void _next() {
    if (_page < _pages.length - 1) {
      _controller.nextPage(
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeInOut,
      );
    } else {
      _finish();
    }
  }

  Future<void> _finish() async {
    await ref.read(onboardingProvider.notifier).markDone();
    // The router redirects to /home once onboarding is marked done.
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            SizedBox(
              height: 52,
              child: Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: AnimatedOpacity(
                    opacity: _page < _pages.length - 1 ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: TextButton(
                      onPressed: _page < _pages.length - 1 ? _finish : null,
                      child: Text(
                        AppStrings.t('onboard_skip'),
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textMuted,
                          fontFamily: 'Plus Jakarta Sans',
                          fontFamilyFallback: const ['NotoSansJP'],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _pages.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (context, i) => _PageContent(
                  data: _pages[i],
                  key: ValueKey(i),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 20, 32, 44),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(_pages.length, (i) {
                      final active = i == _page;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 280),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: active ? 28 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color:
                              active ? _pages[_page].color : AppColors.border,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 28),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 280),
                    width: double.infinity,
                    height: 54,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          _pages[_page].color,
                          _pages[_page].accentColor
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: _pages[_page].color.withValues(alpha: 0.4),
                          blurRadius: 20,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: _next,
                        child: Center(
                          child: Text(
                            _page < _pages.length - 1
                                ? AppStrings.t('onboard_next')
                                : AppStrings.t('onboard_start'),
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: _onColor(_pages[_page].accentColor),
                              letterSpacing: 0.3,
                              fontFamily: 'Plus Jakarta Sans',
                              fontFamilyFallback: const ['NotoSansJP'],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PageData {
  final IconData icon;
  final Color color;
  final Color accentColor;
  final String title;
  final String subtitle;
  const _PageData({
    required this.icon,
    required this.color,
    required this.accentColor,
    required this.title,
    required this.subtitle,
  });
}

class _PageContent extends StatelessWidget {
  final _PageData data;
  const _PageContent({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 36),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 180,
                height: 180,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      data.color.withValues(alpha: 0.18),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      data.color.withValues(alpha: 0.12),
                      Colors.transparent,
                    ],
                  ),
                  border: Border.all(
                    color: data.color.withValues(alpha: 0.15),
                    width: 1,
                  ),
                ),
              ),
              Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      data.color,
                      data.accentColor,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(26),
                  boxShadow: [
                    BoxShadow(
                      color: data.color.withValues(alpha: 0.55),
                      blurRadius: 28,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Icon(data.icon,
                    size: 42, color: _onColor(data.accentColor)),
              ),
            ],
          )
              .animate()
              .scale(
                begin: const Offset(0.6, 0.6),
                end: const Offset(1.0, 1.0),
                duration: 600.ms,
                curve: Curves.elasticOut,
              )
              .fadeIn(duration: 400.ms),
          const SizedBox(height: 44),
          Text(
            data.title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
              height: 1.3,
              letterSpacing: -0.4,
              fontFamily: 'Plus Jakarta Sans',
              fontFamilyFallback: const ['NotoSansJP'],
            ),
          )
              .animate()
              .slideY(
                begin: 0.25,
                end: 0,
                duration: 500.ms,
                delay: 180.ms,
                curve: Curves.easeOut,
              )
              .fadeIn(duration: 400.ms, delay: 180.ms),
          const SizedBox(height: 16),
          Text(
            data.subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              height: 1.7,
              color: AppColors.textSecondary,
              fontFamily: 'Plus Jakarta Sans',
              fontFamilyFallback: const ['NotoSansJP'],
            ),
          )
              .animate()
              .slideY(
                begin: 0.25,
                end: 0,
                duration: 500.ms,
                delay: 300.ms,
                curve: Curves.easeOut,
              )
              .fadeIn(duration: 400.ms, delay: 300.ms),
        ],
      ),
    );
  }
}

/// Label/icon color on a page's accent fill. Pages use different hues (blue,
/// cyan, green, amber), so choose white or dark ink by luminance.
Color _onColor(Color fill) =>
    ThemeData.estimateBrightnessForColor(fill) == Brightness.dark
        ? Colors.white
        : AppColors.onPrimary;
