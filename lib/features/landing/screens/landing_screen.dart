import 'package:flutter/material.dart';
import '../widgets/landing_background.dart';
import '../widgets/landing_nav_bar.dart';
import '../widgets/landing_hero.dart';
import '../widgets/landing_features.dart';
import '../widgets/landing_cta.dart';

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
    _bgCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 12));
    _floatCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 4));
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));
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
          // Animated background orbs
          AnimatedBg(ctrl: _bgCtrl),
          // Scrollable content — SafeArea keeps the nav bar (title + CTA
          // button) clear of the OS status bar/notch on phones.
          SafeArea(
            bottom: false,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  NavBar(isDesktop: isDesktop),
                  HeroSection(
                    isDesktop: isDesktop,
                    floatCtrl: _floatCtrl,
                    pulseCtrl: _pulseCtrl,
                  ),
                  FeaturesSection(isDesktop: isDesktop),
                  CtaSection(pulseCtrl: _pulseCtrl),
                  const Footer(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
