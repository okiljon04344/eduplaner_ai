import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../core/l10n/app_strings.dart';

// ─── Floating mockup card ─────────────────────────────────────────────────────

class FloatingMockup extends StatelessWidget {
  final AnimationController ctrl;
  const FloatingMockup({super.key, required this.ctrl});

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
              blurRadius: 40, spreadRadius: 0, offset: const Offset(0, 20),
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
      )
          .animate()
          .fadeIn(delay: 500.ms, duration: 800.ms)
          .scale(begin: const Offset(0.92, 0.92), end: const Offset(1, 1), curve: Curves.easeOutBack),
    );
  }
}

class _MockupHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 28, height: 28,
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFF059669), Color(0xFF06D6A0)]),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.auto_awesome, size: 15, color: Colors.white),
        ),
        const SizedBox(width: 8),
        Text(
          'EduPlanner AI',
          style: TextStyle(
            fontSize: 13, fontWeight: FontWeight.w700,
            color: Colors.white.withValues(alpha: 0.9),
            fontFamily: 'Plus Jakarta Sans',
          ),
        ),
        const Spacer(),
        Container(
          width: 6, height: 6,
          decoration: BoxDecoration(
            color: const Color(0xFF10B981), shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: const Color(0xFF10B981).withValues(alpha: 0.8), blurRadius: 6)],
          ),
        ),
        const SizedBox(width: 4),
        Text(AppStrings.t('home_online'), style: TextStyle(fontSize: 10, color: Colors.white.withValues(alpha: 0.4))),
      ],
    );
  }
}

final _mockupItems = [
  (Icons.calendar_today_outlined, const Color(0xFF06B6D4), 'login_today_classes', 'mock_subjects'),
  (Icons.assignment_outlined,     const Color(0xFF10B981), 'mock_due_soon', 'mock_assignment'),
  (Icons.smart_toy_outlined,      const Color(0xFFA855F7), 'feat_analytics', 'mock_weakness'),
  (Icons.quiz_outlined,           const Color(0xFFF59E0B), 'mock_quiz_gen', 'mock_quiz_status'),
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
            width: 34, height: 34,
            decoration: BoxDecoration(
              color: data.$2.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(9),
              boxShadow: [BoxShadow(color: data.$2.withValues(alpha: 0.3), blurRadius: 8)],
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
                    fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white,
                    fontFamily: 'Plus Jakarta Sans', fontFamilyFallback: ['NotoSansJP'],
                  ),
                ),
                const SizedBox(height: 1),
                Text(AppStrings.t(data.$4), style: TextStyle(
                  fontSize: 10, color: Colors.white.withValues(alpha: 0.38),
                  fontFamily: 'Plus Jakarta Sans', fontFamilyFallback: const ['NotoSansJP'],
                )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
