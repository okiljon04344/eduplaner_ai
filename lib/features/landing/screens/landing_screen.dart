import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/language_picker_button.dart';

class LandingScreen extends StatefulWidget {
  const LandingScreen({super.key});

  @override
  State<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends State<LandingScreen>
    with TickerProviderStateMixin {
  late final AnimationController _bgCtrl;
  late final AnimationController _floatCtrl;
  late final AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _bgCtrl =
        AnimationController(vsync: this, duration: const Duration(seconds: 12));
    _floatCtrl =
        AnimationController(vsync: this, duration: const Duration(seconds: 4));
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1800));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reduce-motion: leave the controllers stopped at their resting value (0).
    if (MediaQuery.disableAnimationsOf(context)) {
      _bgCtrl.stop();
      _floatCtrl.stop();
      _pulseCtrl.stop();
    } else {
      if (!_bgCtrl.isAnimating) _bgCtrl.repeat();
      if (!_floatCtrl.isAnimating) _floatCtrl.repeat(reverse: true);
      if (!_pulseCtrl.isAnimating) _pulseCtrl.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _bgCtrl.dispose();
    _floatCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isDesktop = width >= 860;

    return Scaffold(
      backgroundColor: const Color(0xFF100C08),
      body: Stack(
        children: [
          _AnimatedBg(ctrl: _bgCtrl),
          // SafeArea keeps the nav bar clear of the status bar/notch on phones.
          SafeArea(
            bottom: false,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _NavBar(isDesktop: isDesktop),
                  _HeroSection(
                    isDesktop: isDesktop,
                    floatCtrl: _floatCtrl,
                    pulseCtrl: _pulseCtrl,
                  ),
                  _FeaturesSection(isDesktop: isDesktop),
                  _CtaSection(pulseCtrl: _pulseCtrl),
                  _Footer(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AnimatedBg extends StatelessWidget {
  final AnimationController ctrl;
  const _AnimatedBg({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ctrl,
      builder: (_, __) => CustomPaint(
        painter: _OrbPainter(ctrl.value),
        size: Size.infinite,
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _OrbPainter extends CustomPainter {
  final double t;
  const _OrbPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    void orb(double cx, double cy, double r, Color c, double phase) {
      final dx = math.sin((t + phase) * math.pi * 2) * size.width * 0.08;
      final dy = math.cos((t * 0.7 + phase) * math.pi * 2) * size.height * 0.06;
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [c.withValues(alpha: 0.28), c.withValues(alpha: 0)],
        ).createShader(Rect.fromCircle(
          center: Offset(size.width * cx + dx, size.height * cy + dy),
          radius: r,
        ));
      canvas.drawCircle(
        Offset(size.width * cx + dx, size.height * cy + dy),
        r,
        paint,
      );
    }

    orb(0.15, 0.2, size.width * 0.38, const Color(0xFF06D6A0), 0.0);
    orb(0.85, 0.15, size.width * 0.32, const Color(0xFF34D399), 0.33);
    orb(0.7, 0.7, size.width * 0.28, const Color(0xFF5EEAD4), 0.66);
    orb(0.1, 0.75, size.width * 0.22, const Color(0xFF059669), 0.15);
  }

  @override
  bool shouldRepaint(_OrbPainter old) => old.t != t;
}

class _NavBar extends StatelessWidget {
  final bool isDesktop;
  const _NavBar({required this.isDesktop});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      padding: EdgeInsets.symmetric(horizontal: isDesktop ? 48 : 20),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.2),
        border: Border(
            bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06))),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF059669), Color(0xFF06D6A0)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                    color: const Color(0xFF06D6A0).withValues(alpha: 0.6),
                    blurRadius: 12)
              ],
            ),
            child:
                const Icon(Icons.auto_awesome, size: 18, color: Colors.white),
          )
              .animate(
                  onPlay: (c) => MediaQuery.disableAnimationsOf(context)
                      ? c.stop()
                      : c.repeat(reverse: true))
              .shimmer(
                  duration: 2400.ms,
                  color: Colors.white.withValues(alpha: 0.15)),
          const SizedBox(width: 10),
          // Expanded + scaleDown (not ellipsis) keeps the wordmark whole when a
          // long localized CTA (de/ru/vi) leaves less room on phones.
          const Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                'EduPlanner AI',
                maxLines: 1,
                softWrap: false,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  fontFamily: 'Plus Jakarta Sans',
                  fontFamilyFallback: ['NotoSansJP'],
                ),
              ),
            ),
          ),
          const LanguagePickerButton(color: Colors.white),
          const SizedBox(width: 12),
          // The hero repeats both CTAs, so narrow phones keep only the signup
          // button here to leave room for the wordmark.
          if (isDesktop) ...[
            TextButton(
              onPressed: () => context.push('/login'),
              child: Text(
                AppStrings.t('landing_cta_login'),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: 0.7),
                  fontFamily: 'Plus Jakarta Sans',
                  fontFamilyFallback: const ['NotoSansJP'],
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          // Capped on phones so a long translation shrinks the button instead of
          // squeezing the wordmark; dropped under 360dp (the hero CTAs suffice).
          if (isDesktop || MediaQuery.sizeOf(context).width >= 360)
            ConstrainedBox(
              constraints:
                  BoxConstraints(maxWidth: isDesktop ? double.infinity : 140),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: _GlowButton(
                  label: AppStrings.t('landing_cta_signup'),
                  small: !isDesktop,
                  onTap: () => context.push('/login'),
                ),
              ),
            ),
        ],
      ),
    ).animate().fadeIn(duration: 500.ms).slideY(begin: -0.05, end: 0);
  }
}

class _HeroSection extends StatelessWidget {
  final bool isDesktop;
  final AnimationController floatCtrl;
  final AnimationController pulseCtrl;

  const _HeroSection({
    required this.isDesktop,
    required this.floatCtrl,
    required this.pulseCtrl,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(minHeight: isDesktop ? 520 : 460),
      padding: EdgeInsets.symmetric(
        horizontal: isDesktop ? 72 : 28,
        vertical: isDesktop ? 80 : 52,
      ),
      child: isDesktop
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(flex: 5, child: _HeroText(pulseCtrl: pulseCtrl)),
                const SizedBox(width: 56),
                Expanded(flex: 4, child: _FloatingMockup(ctrl: floatCtrl)),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _HeroText(pulseCtrl: pulseCtrl),
                const SizedBox(height: 44),
                _FloatingMockup(ctrl: floatCtrl),
              ],
            ),
    );
  }
}

class _HeroText extends StatelessWidget {
  final AnimationController pulseCtrl;
  const _HeroText({required this.pulseCtrl});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            border: Border.all(
                color: const Color(0xFF06D6A0).withValues(alpha: 0.5)),
            gradient: LinearGradient(
              colors: [
                const Color(0xFF06D6A0).withValues(alpha: 0.15),
                const Color(0xFF34D399).withValues(alpha: 0.1),
              ],
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedBuilder(
                animation: pulseCtrl,
                builder: (_, __) => Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF10B981)
                            .withValues(alpha: 0.5 + 0.5 * pulseCtrl.value),
                        blurRadius: 4 + 6 * pulseCtrl.value,
                      )
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 7),
              Text(
                AppStrings.t('landing_badge'),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFA7F3D0),
                  fontFamily: 'Plus Jakarta Sans',
                  fontFamilyFallback: ['NotoSansJP'],
                ),
              ),
            ],
          ),
        )
            .animate()
            .fadeIn(delay: 200.ms, duration: 600.ms)
            .slideX(begin: -0.08, end: 0, curve: Curves.easeOut),

        const SizedBox(height: 24),

        // Each word animates in.
        _GradientTitle()
            .animate()
            .fadeIn(delay: 400.ms, duration: 700.ms)
            .slideY(begin: 0.12, end: 0, curve: Curves.easeOut),

        const SizedBox(height: 18),

        Text(
          AppStrings.t('landing_subtitle'),
          style: TextStyle(
            fontSize: 15,
            height: 1.75,
            color: Colors.white.withValues(alpha: 0.55),
            fontFamily: 'Plus Jakarta Sans',
            fontFamilyFallback: const ['NotoSansJP'],
          ),
        )
            .animate()
            .fadeIn(delay: 600.ms, duration: 600.ms)
            .slideY(begin: 0.1, end: 0),

        const SizedBox(height: 36),

        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _GlowButton(
              label: AppStrings.t('landing_cta_start'),
              onTap: () => context.push('/login'),
              pulseCtrl: pulseCtrl,
            ),
            const SizedBox(width: 16),
            OutlinedButton(
              onPressed: () => context.push('/login'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white.withValues(alpha: 0.75),
                side: BorderSide(color: Colors.white.withValues(alpha: 0.18)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: Text(
                AppStrings.t('landing_cta_login'),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Plus Jakarta Sans',
                  fontFamilyFallback: ['NotoSansJP'],
                ),
              ),
            ),
          ],
        )
            .animate()
            .fadeIn(delay: 800.ms, duration: 600.ms)
            .slideY(begin: 0.08, end: 0),

        const SizedBox(height: 28),

        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ...List.generate(
                5,
                (i) => const Padding(
                      padding: EdgeInsets.only(right: 2),
                      child:
                          Icon(Icons.star, size: 14, color: Color(0xFFFBBF24)),
                    )),
            const SizedBox(width: 8),
            // Flexible: long translations wrap instead of being clipped.
            Flexible(
              child: Text(
                AppStrings.t('social_proof'),
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.white.withValues(alpha: 0.4),
                  fontFamily: 'Plus Jakarta Sans',
                  fontFamilyFallback: const ['NotoSansJP'],
                ),
              ),
            ),
          ],
        ).animate().fadeIn(delay: 1000.ms, duration: 600.ms),
      ],
    );
  }
}

class _GradientTitle extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (bounds) => const LinearGradient(
        colors: [
          Color(0xFFD1FAE5),
          Color(0xFF34D399),
          Color(0xFF60A5FA),
          Color(0xFFD1FAE5)
        ],
        stops: [0.0, 0.35, 0.7, 1.0],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(bounds),
      child: Text(
        AppStrings.t('landing_title'),
        style: TextStyle(
          // 28 under 360dp: ja's first line (学習をスマートに、) must fit a 320dp phone.
          fontSize: switch (MediaQuery.sizeOf(context).width) {
            < 360 => 28,
            < 600 => 34,
            _ => 46
          },
          fontWeight: FontWeight.w900,
          color: Colors.white, height: 1.15, letterSpacing: -1.2,
          fontFamily: 'Plus Jakarta Sans',
          fontFamilyFallback: const ['NotoSansJP'],
        ),
      ),
    );
  }
}

class _FloatingMockup extends StatelessWidget {
  final AnimationController ctrl;
  const _FloatingMockup({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ctrl,
      builder: (_, child) {
        final offset = Offset(0, -10 * ctrl.value + 5);
        return Transform.translate(offset: offset, child: child);
      },
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF06D6A0).withValues(alpha: 0.25),
              blurRadius: 40,
              spreadRadius: 0,
              offset: const Offset(0, 20),
            ),
          ],
        ),
        child: Column(
          children: [
            _MockupHeader(),
            const SizedBox(height: 12),
            ..._mockupItems.asMap().entries.map((e) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _MockupRow(data: e.value)
                      .animate()
                      .fadeIn(delay: (500 + e.key * 130).ms, duration: 500.ms)
                      .slideX(begin: 0.08, end: 0),
                )),
          ],
        ),
      ).animate().fadeIn(delay: 500.ms, duration: 800.ms).scale(
          begin: const Offset(0.92, 0.92),
          end: const Offset(1, 1),
          curve: Curves.easeOutBack),
    );
  }
}

class _MockupHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
                colors: [Color(0xFF059669), Color(0xFF06D6A0)]),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.auto_awesome, size: 15, color: Colors.white),
        ),
        const SizedBox(width: 8),
        Text(
          'EduPlanner AI',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Colors.white.withValues(alpha: 0.9),
            fontFamily: 'Plus Jakarta Sans',
          ),
        ),
        const Spacer(),
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: const Color(0xFF10B981),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                  color: const Color(0xFF10B981).withValues(alpha: 0.8),
                  blurRadius: 6)
            ],
          ),
        ),
        const SizedBox(width: 4),
        Text(AppStrings.t('home_online'),
            style: TextStyle(
                fontSize: 10, color: Colors.white.withValues(alpha: 0.4))),
      ],
    );
  }
}

final _mockupItems = [
  (
    Icons.calendar_today_outlined,
    const Color(0xFF06B6D4),
    'login_today_classes',
    'mock_subjects'
  ),
  (
    Icons.assignment_outlined,
    const Color(0xFF10B981),
    'mock_due_soon',
    'mock_assignment'
  ),
  (
    Icons.smart_toy_outlined,
    const Color(0xFFA855F7),
    'feat_analytics',
    'mock_weakness'
  ),
  (
    Icons.quiz_outlined,
    const Color(0xFFF59E0B),
    'mock_quiz_gen',
    'mock_quiz_status'
  ),
];

class _MockupRow extends StatelessWidget {
  final (IconData, Color, String, String) data;
  const _MockupRow({required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: data.$2.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(9),
              boxShadow: [
                BoxShadow(color: data.$2.withValues(alpha: 0.3), blurRadius: 8)
              ],
            ),
            child: Icon(data.$1, size: 16, color: data.$2),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data.$3 == 'login_today_classes'
                      ? AppStrings.t(data.$3, {'n': 3})
                      : AppStrings.t(data.$3),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    fontFamily: 'Plus Jakarta Sans',
                    fontFamilyFallback: ['NotoSansJP'],
                  ),
                ),
                const SizedBox(height: 1),
                Text(AppStrings.t(data.$4),
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.white.withValues(alpha: 0.38),
                      fontFamily: 'Plus Jakarta Sans',
                      fontFamilyFallback: const ['NotoSansJP'],
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

const _features = [
  (
    Icons.calendar_month_outlined,
    Color(0xFF06B6D4),
    'feat_timetable',
    'feat_timetable_desc'
  ),
  (
    Icons.assignment_outlined,
    Color(0xFF10B981),
    'feat_assignments',
    'feat_assignments_desc'
  ),
  (
    Icons.smart_toy_outlined,
    Color(0xFFA855F7),
    'feat_ai_chat',
    'feat_ai_chat_desc'
  ),
  (
    Icons.analytics_outlined,
    Color(0xFFF59E0B),
    'feat_analytics',
    'feat_analytics_desc'
  ),
  (Icons.quiz_outlined, Color(0xFFEC4899), 'feat_quiz', 'feat_quiz_desc'),
  (
    Icons.notifications_outlined,
    Color(0xFF60A5FA),
    'feat_alerts',
    'feat_alerts_desc'
  ),
];

class _FeaturesSection extends StatelessWidget {
  final bool isDesktop;
  const _FeaturesSection({required this.isDesktop});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isDesktop ? 72 : 24,
        vertical: isDesktop ? 88 : 56,
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            decoration: BoxDecoration(
              border: Border.all(
                  color: const Color(0xFF06D6A0).withValues(alpha: 0.4)),
              color: const Color(0xFF06D6A0).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              '✦',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Color(0xFFA7F3D0),
                fontFamily: 'Plus Jakarta Sans',
              ),
            ),
          ).animate().fadeIn(duration: 500.ms),
          const SizedBox(height: 16),
          ShaderMask(
            shaderCallback: (b) => const LinearGradient(
              colors: [Colors.white, Color(0xFFA7F3D0)],
            ).createShader(b),
            child: Text(
              AppStrings.t('landing_features_title'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: isDesktop ? 36 : 28,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: -0.8,
                fontFamily: 'Plus Jakarta Sans',
                fontFamilyFallback: const ['NotoSansJP'],
              ),
            ),
          )
              .animate()
              .fadeIn(delay: 100.ms, duration: 600.ms)
              .slideY(begin: 0.1, end: 0),
          const SizedBox(height: 10),
          Text(
            AppStrings.t('landing_features_subtitle'),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              height: 1.7,
              color: Colors.white.withValues(alpha: 0.4),
              fontFamily: 'Plus Jakarta Sans',
              fontFamilyFallback: const ['NotoSansJP'],
            ),
          ).animate().fadeIn(delay: 200.ms, duration: 500.ms),
          const SizedBox(height: 52),
          isDesktop
              ? Wrap(
                  spacing: 18,
                  runSpacing: 18,
                  alignment: WrapAlignment.center,
                  children: _features
                      .asMap()
                      .entries
                      .map(
                        (e) => SizedBox(
                          width: 340,
                          child: _FeatureCard(data: e.value)
                              .animate()
                              .fadeIn(
                                  delay: (300 + e.key * 90).ms,
                                  duration: 500.ms)
                              .slideY(
                                  begin: 0.12,
                                  end: 0,
                                  curve: Curves.easeOutCubic)
                              .scale(
                                  begin: const Offset(0.96, 0.96),
                                  end: const Offset(1, 1)),
                        ),
                      )
                      .toList(),
                )
              : Column(
                  children: _features
                      .asMap()
                      .entries
                      .map(
                        (e) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _FeatureCard(data: e.value)
                              .animate()
                              .fadeIn(
                                  delay: (200 + e.key * 80).ms,
                                  duration: 500.ms)
                              .slideY(begin: 0.1, end: 0),
                        ),
                      )
                      .toList(),
                ),
        ],
      ),
    );
  }
}

class _FeatureCard extends StatefulWidget {
  final (IconData, Color, String, String) data;
  const _FeatureCard({required this.data});

  @override
  State<_FeatureCard> createState() => _FeatureCardState();
}

class _FeatureCardState extends State<_FeatureCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.data.$2;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: _hovered
              ? color.withValues(alpha: 0.08)
              : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: _hovered
                ? color.withValues(alpha: 0.35)
                : Colors.white.withValues(alpha: 0.08),
          ),
          boxShadow: _hovered
              ? [BoxShadow(color: color.withValues(alpha: 0.2), blurRadius: 24)]
              : null,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: color.withValues(alpha: _hovered ? 0.22 : 0.12),
                borderRadius: BorderRadius.circular(14),
                boxShadow: _hovered
                    ? [
                        BoxShadow(
                            color: color.withValues(alpha: 0.4), blurRadius: 14)
                      ]
                    : null,
              ),
              child: Icon(widget.data.$1, size: 22, color: color),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppStrings.t(widget.data.$3),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      fontFamily: 'Plus Jakarta Sans',
                      fontFamilyFallback: ['NotoSansJP'],
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    AppStrings.t(widget.data.$4),
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.6,
                      color: Colors.white.withValues(alpha: 0.45),
                      fontFamily: 'Plus Jakarta Sans',
                      fontFamilyFallback: const ['NotoSansJP'],
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

class _CtaSection extends StatelessWidget {
  final AnimationController pulseCtrl;
  const _CtaSection({required this.pulseCtrl});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 56),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF059669).withValues(alpha: 0.5),
            const Color(0xFF06D6A0).withValues(alpha: 0.5),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        border:
            Border.all(color: const Color(0xFF06D6A0).withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF06D6A0).withValues(alpha: 0.25),
            blurRadius: 40,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          const Text('✦', style: TextStyle(fontSize: 28))
              .animate()
              .fadeIn(duration: 500.ms)
              .animate(
                  onPlay: (c) => MediaQuery.disableAnimationsOf(context)
                      ? c.stop()
                      : c.repeat(reverse: true))
              .scaleXY(begin: 0.9, end: 1.1, duration: 1600.ms),
          const SizedBox(height: 14),
          ShaderMask(
            shaderCallback: (b) => const LinearGradient(
              colors: [Colors.white, Color(0xFFA7F3D0)],
            ).createShader(b),
            child: Text(
              AppStrings.t('landing_cta_title'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: -0.6,
                fontFamily: 'Plus Jakarta Sans',
                fontFamilyFallback: ['NotoSansJP'],
              ),
            ),
          )
              .animate()
              .fadeIn(delay: 150.ms, duration: 600.ms)
              .slideY(begin: 0.1, end: 0),
          const SizedBox(height: 10),
          Text(
            AppStrings.t('landing_cta_subtitle'),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withValues(alpha: 0.5),
              fontFamily: 'Plus Jakarta Sans',
              fontFamilyFallback: const ['NotoSansJP'],
            ),
          ).animate().fadeIn(delay: 250.ms, duration: 500.ms),
          const SizedBox(height: 32),
          _GlowButton(
            label: AppStrings.t('landing_cta_button'),
            onTap: () => context.push('/login'),
            pulseCtrl: pulseCtrl,
            large: true,
          ).animate().fadeIn(delay: 380.ms).scale(
                begin: const Offset(0.88, 0.88),
                end: const Offset(1, 1),
                curve: Curves.easeOutBack,
                duration: 500.ms,
              ),
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 32),
      decoration: BoxDecoration(
        border: Border(
            top: BorderSide(color: Colors.white.withValues(alpha: 0.07))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('© 2026 EduPlanner AI',
              style: TextStyle(
                  fontSize: 12, color: Colors.white.withValues(alpha: 0.25))),
          Text('Powered by Google Gemini AI',
              style: TextStyle(
                  fontSize: 12, color: Colors.white.withValues(alpha: 0.25))),
        ],
      ),
    );
  }
}

class _GlowButton extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  final bool small;
  final bool large;
  final AnimationController? pulseCtrl;
  const _GlowButton({
    required this.label,
    required this.onTap,
    this.small = false,
    this.large = false,
    this.pulseCtrl,
  });

  @override
  State<_GlowButton> createState() => _GlowButtonState();
}

class _GlowButtonState extends State<_GlowButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final px = widget.large
        ? 32.0
        : widget.small
            ? 14.0
            : 22.0;
    final py = widget.large
        ? 16.0
        : widget.small
            ? 9.0
            : 13.0;
    final fs = widget.large
        ? 16.0
        : widget.small
            ? 12.0
            : 14.0;

    final Widget btn = MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: EdgeInsets.symmetric(horizontal: px, vertical: py),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF059669), Color(0xFF06D6A0)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF06D6A0)
                    .withValues(alpha: _hovered ? 0.65 : 0.35),
                blurRadius: _hovered ? 28 : 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: fs,
              fontWeight: FontWeight.w700,
              color: AppColors.onPrimary,
              letterSpacing: 0.2,
              fontFamily: 'Plus Jakarta Sans',
              fontFamilyFallback: const ['NotoSansJP'],
            ),
          ),
        ),
      ),
    );

    if (widget.pulseCtrl != null) {
      return AnimatedBuilder(
        animation: widget.pulseCtrl!,
        builder: (_, child) => Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF06D6A0)
                    .withValues(alpha: 0.15 + 0.15 * widget.pulseCtrl!.value),
                blurRadius: 20 + 16 * widget.pulseCtrl!.value,
                spreadRadius: widget.pulseCtrl!.value * 2,
              ),
            ],
          ),
          child: child,
        ),
        child: btn,
      );
    }

    return btn;
  }
}
