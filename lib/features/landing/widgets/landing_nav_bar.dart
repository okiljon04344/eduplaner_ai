import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../shared/widgets/language_picker_button.dart';
import 'glow_button.dart';

// ─── Nav bar ─────────────────────────────────────────────────────────────────

class NavBar extends StatelessWidget {
  final bool isDesktop;
  const NavBar({super.key, required this.isDesktop});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      padding: EdgeInsets.symmetric(horizontal: isDesktop ? 48 : 20),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.2),
        border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06))),
      ),
      child: Row(
        children: [
          // Animated logo
          Container(
            width: 34, height: 34,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF059669), Color(0xFF06D6A0)],
                begin: Alignment.topLeft, end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(10),
              boxShadow: [BoxShadow(color: const Color(0xFF06D6A0).withValues(alpha: 0.6), blurRadius: 12)],
            ),
            child: const Icon(Icons.auto_awesome, size: 18, color: Colors.white),
          )
              .animate(onPlay: (c) => MediaQuery.disableAnimationsOf(context) ? c.stop() : c.repeat(reverse: true))
              .shimmer(duration: 2400.ms, color: Colors.white.withValues(alpha: 0.15)),
          const SizedBox(width: 10),
          // Expanded (not Flexible+Spacer) so the wordmark claims the *entire*
          // leftover width; scaleDown (not ellipsis) keeps the brand whole when
          // a long localized CTA (de/ru/vi) leaves less room on phones.
          const Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                'EduPlanner AI',
                maxLines: 1,
                softWrap: false,
                style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white,
                  fontFamily: 'Plus Jakarta Sans', fontFamilyFallback: ['NotoSansJP'],
                ),
              ),
            ),
          ),
          const LanguagePickerButton(color: Colors.white),
          const SizedBox(width: 12),
          // The hero section right below already repeats both the login and
          // signup CTAs prominently, so on narrow phones the nav bar only
          // keeps the signup button — otherwise there isn't enough width for
          // the full "EduPlanner AI" wordmark next to three separate CTAs.
          if (isDesktop) ...[
            TextButton(
              onPressed: () => context.push('/login'),
              child: Text(
                AppStrings.t('landing_cta_login'),
                style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: 0.7),
                  fontFamily: 'Plus Jakarta Sans', fontFamilyFallback: const ['NotoSansJP'],
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          // Capped on phones so a long translation ("Commencer gratuitement")
          // shrinks the button instead of squeezing the wordmark; dropped
          // under 360dp, where the hero CTAs right below are enough.
          if (isDesktop || MediaQuery.sizeOf(context).width >= 360) ConstrainedBox(
            constraints: BoxConstraints(maxWidth: isDesktop ? double.infinity : 140),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: GlowButton(
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
