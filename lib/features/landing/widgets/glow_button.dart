import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

// ─── Glow button ──────────────────────────────────────────────────────────────

class GlowButton extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  final bool small;
  final bool large;
  final AnimationController? pulseCtrl;
  const GlowButton({
    super.key,
    required this.label,
    required this.onTap,
    this.small = false,
    this.large = false,
    this.pulseCtrl,
  });

  @override
  State<GlowButton> createState() => _GlowButtonState();
}

class _GlowButtonState extends State<GlowButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final px = widget.large ? 32.0 : widget.small ? 14.0 : 22.0;
    final py = widget.large ? 16.0 : widget.small ? 9.0 : 13.0;
    final fs = widget.large ? 16.0 : widget.small ? 12.0 : 14.0;

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
              begin: Alignment.topLeft, end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF06D6A0).withValues(alpha: _hovered ? 0.65 : 0.35),
                blurRadius: _hovered ? 28 : 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: fs, fontWeight: FontWeight.w700, color: AppColors.onPrimary,
              letterSpacing: 0.2,
              fontFamily: 'Plus Jakarta Sans', fontFamilyFallback: const ['NotoSansJP'],
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
