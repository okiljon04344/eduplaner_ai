import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/utils/responsive.dart';
import '../../../shared/widgets/pressable.dart';
import '../providers/onboarding_provider.dart';

/// First-run intro: three slides on what the app does for a school student,
/// then the router moves on to /profile-setup.
///
/// Motion follows the finger: icon and text are placed from the live
/// PageController offset (parallax, fade), so a swipe can be stopped or
/// reversed at any point. The screen itself fades in once on open.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  // Accents are theme-independent brand colors; strings resolve at build.
  static const _pages = [
    _PageData(Icons.event_note_outlined, AppColors.primary, 'onboard_1'),
    _PageData(Icons.campaign_outlined, AppColors.cyan, 'onboard_2'),
    _PageData(Icons.smart_toy_outlined, AppColors.amber, 'onboard_3'),
  ];

  bool get _isLast => _page == _pages.length - 1;

  double get _offset =>
      _controller.hasClients && _controller.position.haveDimensions ? _controller.page! : _page.toDouble();

  void _next() {
    if (_isLast) {
      _finish();
      return;
    }
    _controller.nextPage(duration: const Duration(milliseconds: 320), curve: AppMotion.sheetCurve);
  }

  // Router redirects to /profile-setup once the flag flips.
  Future<void> _finish() => ref.read(onboardingProvider.notifier).markDone();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = context.isTablet;
    final reduced = reduceMotion(context);
    const pages = _pages;

    Widget enter(Widget w, int i) => reduced
        ? w.animate().fadeIn(duration: AppMotion.fadeDuration)
        : w
            .animate(delay: AppMotion.enterStagger * i)
            .fadeIn(duration: AppMotion.enterDuration, curve: AppMotion.strongEaseOut)
            .moveY(begin: 10, end: 0, duration: AppMotion.enterDuration, curve: AppMotion.strongEaseOut);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: isDesktop ? 480 : double.infinity),
            child: Column(
              children: [
                SizedBox(
                  height: 52,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: AnimatedOpacity(
                        opacity: _isLast ? 0 : 1,
                        duration: AppMotion.fadeDuration,
                        child: TextButton(
                          onPressed: _isLast ? null : _finish,
                          child: Text(AppStrings.t('onboard_skip'),
                              style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: enter(
                    LayoutBuilder(
                      builder: (context, box) => PageView.builder(
                        controller: _controller,
                        itemCount: pages.length,
                        onPageChanged: (i) => setState(() => _page = i),
                        itemBuilder: (context, i) => AnimatedBuilder(
                          animation: _controller,
                          builder: (context, _) => _PageContent(
                            data: pages[i],
                            delta: (_offset - i).clamp(-1.0, 1.0),
                            width: box.maxWidth,
                            reduced: reduced,
                            isDesktop: isDesktop,
                            footnote: i == pages.length - 1 ? AppStrings.t('onboard_next_hint') : null,
                          ),
                        ),
                      ),
                    ),
                    0,
                  ),
                ),
                enter(
                  Padding(
                    padding: const EdgeInsets.fromLTRB(32, 20, 32, 36),
                    child: Column(
                      children: [
                        AnimatedBuilder(
                          animation: _controller,
                          builder: (context, _) => _Dots(count: pages.length, offset: _offset),
                        ),
                        const SizedBox(height: 28),
                        Pressable(
                          child: SizedBox(
                            width: double.infinity,
                            height: 54,
                            child: ElevatedButton(
                              onPressed: _next,
                              style: ElevatedButton.styleFrom(
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              ),
                              child: AnimatedSwitcher(
                                duration: AppMotion.fadeDuration,
                                child: Text(
                                  AppStrings.t(_isLast ? 'onboard_start' : 'onboard_next'),
                                  key: ValueKey(_isLast),
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  1,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PageData {
  final IconData icon;
  final Color color;
  final String key;
  const _PageData(this.icon, this.color, this.key);
}

/// Page indicator driven by the live scroll offset: the active pill
/// stretches and recolors as the finger moves, not after the page settles.
class _Dots extends StatelessWidget {
  final int count;
  final double offset;
  const _Dots({required this.count, required this.offset});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          Builder(builder: (context) {
            final t = (1 - (offset - i).abs()).clamp(0.0, 1.0);
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: 8 + 20 * t,
              height: 8,
              decoration: BoxDecoration(
                color: Color.lerp(AppColors.border, AppColors.primary, t),
                borderRadius: BorderRadius.circular(4),
              ),
            );
          }),
      ],
    );
  }
}

class _PageContent extends StatelessWidget {
  final _PageData data;

  /// Distance of this page from the viewport centre, -1..1 (0 = in view).
  final double delta;
  final double width;
  final bool reduced;
  final bool isDesktop;
  final String? footnote;

  const _PageContent({
    required this.data,
    required this.delta,
    required this.width,
    required this.reduced,
    required this.isDesktop,
    this.footnote,
  });

  @override
  Widget build(BuildContext context) {
    final dist = delta.abs();
    final iconBox = isDesktop ? 104.0 : 88.0;

    // Parallax: the page slides a full width, the icon drifts back 40% of it
    // and the text 15%, so layers separate during the swipe. Reduced motion
    // keeps only the fade.
    Widget layer(Widget child, double lag, {double shrink = 0}) => Opacity(
          opacity: (1 - dist * 1.4).clamp(0.0, 1.0),
          child: reduced
              ? child
              : Transform.translate(
                  offset: Offset(delta * width * lag, 0),
                  child: Transform.scale(scale: 1 - dist * shrink, child: child),
                ),
        );

    // Centered when it fits; scrolls on short screens (small phones, large
    // text) instead of overflowing.
    return Center(
      child: SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          layer(
            Container(
              width: iconBox * 2,
              height: iconBox * 2,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [data.color.withValues(alpha: 0.16), Colors.transparent]),
              ),
              child: Container(
                width: iconBox,
                height: iconBox,
                decoration: BoxDecoration(
                  color: data.color,
                  borderRadius: BorderRadius.circular(iconBox * 0.3),
                  boxShadow: [
                    BoxShadow(color: data.color.withValues(alpha: 0.35), blurRadius: 24, offset: const Offset(0, 8)),
                  ],
                ),
                child: Icon(data.icon, size: iconBox * 0.48, color: AppColors.onPrimary),
              ),
            ),
            0.4,
            shrink: 0.12,
          ),
          SizedBox(height: isDesktop ? 32 : 24),
          layer(
            Column(
              children: [
                Text(
                  AppStrings.t('${data.key}_title'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: isDesktop ? 28 : 24,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                    height: 1.3,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  AppStrings.t('${data.key}_sub'),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: isDesktop ? 16 : 15, height: 1.7, color: AppColors.textSecondary),
                ),
                if (footnote != null) ...[
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceVar,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.mark_email_unread_outlined, size: 18, color: AppColors.textSecondary),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(footnote!,
                              style: TextStyle(fontSize: 13, height: 1.5, color: AppColors.textSecondary)),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
            0.15,
          ),
        ],
      ),
      ),
    );
  }
}
