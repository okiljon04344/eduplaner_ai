import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../core/l10n/app_strings.dart';

// ─── Features ─────────────────────────────────────────────────────────────────

const _features = [
  (Icons.calendar_month_outlined, Color(0xFF06B6D4), 'feat_timetable',  'feat_timetable_desc'),
  (Icons.assignment_outlined,     Color(0xFF10B981), 'feat_assignments',    'feat_assignments_desc'),
  (Icons.smart_toy_outlined,      Color(0xFFA855F7), 'feat_ai_chat',  'feat_ai_chat_desc'),
  (Icons.analytics_outlined,      Color(0xFFF59E0B), 'feat_analytics',    'feat_analytics_desc'),
  (Icons.quiz_outlined,           Color(0xFFEC4899), 'feat_quiz',  'feat_quiz_desc'),
  (Icons.notifications_outlined,  Color(0xFF60A5FA), 'feat_alerts','feat_alerts_desc'),
];

class FeaturesSection extends StatelessWidget {
  final bool isDesktop;
  const FeaturesSection({super.key, required this.isDesktop});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isDesktop ? 72 : 24,
        vertical: isDesktop ? 88 : 56,
      ),
      child: Column(
        children: [
          // Section label
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFF06D6A0).withValues(alpha: 0.4)),
              color: const Color(0xFF06D6A0).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              '✦',
              style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700,
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
                fontWeight: FontWeight.w900, color: Colors.white,
                letterSpacing: -0.8,
                fontFamily: 'Plus Jakarta Sans', fontFamilyFallback: const ['NotoSansJP'],
              ),
            ),
          ).animate().fadeIn(delay: 100.ms, duration: 600.ms).slideY(begin: 0.1, end: 0),

          const SizedBox(height: 10),

          Text(
            AppStrings.t('landing_features_subtitle'),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14, height: 1.7,
              color: Colors.white.withValues(alpha: 0.4),
              fontFamily: 'Plus Jakarta Sans', fontFamilyFallback: const ['NotoSansJP'],
            ),
          ).animate().fadeIn(delay: 200.ms, duration: 500.ms),

          const SizedBox(height: 52),

          isDesktop
              ? Wrap(
                  spacing: 18, runSpacing: 18,
                  alignment: WrapAlignment.center,
                  children: _features.asMap().entries.map((e) =>
                    SizedBox(
                      width: 340,
                      child: _FeatureCard(data: e.value)
                          .animate()
                          .fadeIn(delay: (300 + e.key * 90).ms, duration: 500.ms)
                          .slideY(begin: 0.12, end: 0, curve: Curves.easeOutCubic)
                          .scale(begin: const Offset(0.96, 0.96), end: const Offset(1, 1)),
                    ),
                  ).toList(),
                )
              : Column(
                  children: _features.asMap().entries.map((e) =>
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _FeatureCard(data: e.value)
                          .animate()
                          .fadeIn(delay: (200 + e.key * 80).ms, duration: 500.ms)
                          .slideY(begin: 0.1, end: 0),
                    ),
                  ).toList(),
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
            color: _hovered ? color.withValues(alpha: 0.35) : Colors.white.withValues(alpha: 0.08),
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
              width: 46, height: 46,
              decoration: BoxDecoration(
                color: color.withValues(alpha: _hovered ? 0.22 : 0.12),
                borderRadius: BorderRadius.circular(14),
                boxShadow: _hovered
                    ? [BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 14)]
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
                      fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white,
                      fontFamily: 'Plus Jakarta Sans', fontFamilyFallback: ['NotoSansJP'],
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    AppStrings.t(widget.data.$4),
                    style: TextStyle(
                      fontSize: 12, height: 1.6,
                      color: Colors.white.withValues(alpha: 0.45),
                      fontFamily: 'Plus Jakarta Sans', fontFamilyFallback: const ['NotoSansJP'],
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
