import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../../core/l10n/app_strings.dart';
import 'glow_button.dart';
import 'landing_mockup.dart';

// ─── Hero section ────────────────────────────────────────────────────────────

class HeroSection extends StatelessWidget {
  final bool isDesktop;
  final AnimationController floatCtrl;
  final AnimationController pulseCtrl;

  const HeroSection({
    super.key,
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
                Expanded(flex: 4, child: FloatingMockup(ctrl: floatCtrl)),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _HeroText(pulseCtrl: pulseCtrl),
                const SizedBox(height: 44),
                FloatingMockup(ctrl: floatCtrl),
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
        // Badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFF06D6A0).withValues(alpha: 0.5)),
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
                  width: 6, height: 6,
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981),
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(
                      color: const Color(0xFF10B981).withValues(alpha: 0.5 + 0.5 * pulseCtrl.value),
                      blurRadius: 4 + 6 * pulseCtrl.value,
                    )],
                  ),
                ),
              ),
              const SizedBox(width: 7),
              Text(
                AppStrings.t('landing_badge'),
                style: const TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w700,
                  color: Color(0xFFA7F3D0),
                  fontFamily: 'Plus Jakarta Sans', fontFamilyFallback: ['NotoSansJP'],
                ),
              ),
            ],
          ),
        )
            .animate().fadeIn(delay: 200.ms, duration: 600.ms)
            .slideX(begin: -0.08, end: 0, curve: Curves.easeOut),

        const SizedBox(height: 24),

        // Main title — each word animates in
        _GradientTitle()
            .animate()
            .fadeIn(delay: 400.ms, duration: 700.ms)
            .slideY(begin: 0.12, end: 0, curve: Curves.easeOut),

        const SizedBox(height: 18),

        Text(
          AppStrings.t('landing_subtitle'),
          style: TextStyle(
            fontSize: 15, height: 1.75,
            color: Colors.white.withValues(alpha: 0.55),
            fontFamily: 'Plus Jakarta Sans', fontFamilyFallback: const ['NotoSansJP'],
          ),
        )
            .animate()
            .fadeIn(delay: 600.ms, duration: 600.ms)
            .slideY(begin: 0.1, end: 0),

        const SizedBox(height: 36),

        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            GlowButton(
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
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: Text(
                AppStrings.t('landing_cta_login'),
                style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w600,
                  fontFamily: 'Plus Jakarta Sans', fontFamilyFallback: ['NotoSansJP'],
                ),
              ),
            ),
          ],
        )
            .animate()
            .fadeIn(delay: 800.ms, duration: 600.ms)
            .slideY(begin: 0.08, end: 0),

        const SizedBox(height: 28),

        // Social proof
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ...List.generate(5, (i) => const Padding(
              padding: EdgeInsets.only(right: 2),
              child: Icon(Icons.star, size: 14, color: Color(0xFFFBBF24)),
            )),
            const SizedBox(width: 8),
            // Flexible: long translations wrap instead of being clipped.
            Flexible(
              child: Text(
                AppStrings.t('social_proof'),
                style: TextStyle(
                  fontSize: 11, color: Colors.white.withValues(alpha: 0.4),
                  fontFamily: 'Plus Jakarta Sans', fontFamilyFallback: const ['NotoSansJP'],
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
        colors: [Color(0xFFD1FAE5), Color(0xFF34D399), Color(0xFF60A5FA), Color(0xFFD1FAE5)],
        stops: [0.0, 0.35, 0.7, 1.0],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(bounds),
      child: Text(
        AppStrings.t('landing_title'),
        style: TextStyle(
          // 28 under 360dp: ja's first line (学習をスマートに、) must fit a 320dp phone.
          fontSize: switch (MediaQuery.sizeOf(context).width) { < 360 => 28, < 600 => 34, _ => 46 }, fontWeight: FontWeight.w900,
          color: Colors.white, height: 1.15, letterSpacing: -1.2,
          fontFamily: 'Plus Jakarta Sans', fontFamilyFallback: const ['NotoSansJP'],
        ),
      ),
    );
  }
}
