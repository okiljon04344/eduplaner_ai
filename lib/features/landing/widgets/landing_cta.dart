import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../../core/l10n/app_strings.dart';
import 'glow_button.dart';

// ─── CTA section ──────────────────────────────────────────────────────────────

class CtaSection extends StatelessWidget {
  final AnimationController pulseCtrl;
  const CtaSection({super.key, required this.pulseCtrl});

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
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFF06D6A0).withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF06D6A0).withValues(alpha: 0.25),
            blurRadius: 40, offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          const Text('✦', style: TextStyle(fontSize: 28))
              .animate().fadeIn(duration: 500.ms)
              .animate(onPlay: (c) => MediaQuery.disableAnimationsOf(context) ? c.stop() : c.repeat(reverse: true))
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
                fontSize: 30, fontWeight: FontWeight.w900, color: Colors.white,
                letterSpacing: -0.6,
                fontFamily: 'Plus Jakarta Sans', fontFamilyFallback: ['NotoSansJP'],
              ),
            ),
          ).animate().fadeIn(delay: 150.ms, duration: 600.ms).slideY(begin: 0.1, end: 0),

          const SizedBox(height: 10),

          Text(
            AppStrings.t('landing_cta_subtitle'),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withValues(alpha: 0.5),
              fontFamily: 'Plus Jakarta Sans', fontFamilyFallback: const ['NotoSansJP'],
            ),
          ).animate().fadeIn(delay: 250.ms, duration: 500.ms),

          const SizedBox(height: 32),

          GlowButton(
            label: AppStrings.t('landing_cta_button'),
            onTap: () => context.push('/login'),
            pulseCtrl: pulseCtrl,
            large: true,
          ).animate().fadeIn(delay: 380.ms).scale(
            begin: const Offset(0.88, 0.88), end: const Offset(1, 1),
            curve: Curves.easeOutBack, duration: 500.ms,
          ),
        ],
      ),
    );
  }
}

// ─── Footer ───────────────────────────────────────────────────────────────────

class Footer extends StatelessWidget {
  const Footer({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 32),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.07))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('© 2026 EduPlanner AI',
              style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.25))),
          Text('Powered by Google Gemini AI',
              style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.25))),
        ],
      ),
    );
  }
}
