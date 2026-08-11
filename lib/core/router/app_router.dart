import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../l10n/app_strings.dart';
import '../theme/app_colors.dart';
import '../../features/ai_chat/screens/ai_chat_screen.dart';
import '../../features/assignments/screens/assignments_screen.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../../features/auth/screens/email_login_screen.dart';
import '../../features/auth/screens/email_signup_screen.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/home/screens/home_screen.dart';
import '../../features/landing/screens/landing_screen.dart';
import '../../features/onboarding/providers/onboarding_provider.dart';
import '../../features/onboarding/screens/onboarding_screen.dart';
import '../../features/quiz/screens/quiz_screen.dart';
import '../../features/settings/screens/settings_screen.dart';
import '../../features/timetable/screens/timetable_screen.dart';
import '../../shared/widgets/app_shell.dart';

/// Provides the singleton [GoRouter] instance.
///
/// The router is created inside a Riverpod [Provider] so it can watch
/// [authStateProvider] and [onboardingProvider] and automatically redirect
/// when auth state changes (e.g. sign-out from any screen).
///
/// Redirect logic (evaluated on every navigation and on auth/onboarding state changes):
///   - While either provider is loading → no redirect (avoid flicker).
///   - Not logged in and not on an auth/landing path → redirect to `'/'`.
///   - Logged in and on login/root → redirect to `/home` or `/onboarding`.
///   - Logged in but onboarding not done → redirect to `/onboarding`.
final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authStateProvider);
  final onboardingState = ref.watch(onboardingProvider);

  return GoRouter(
    initialLocation: '/home',
    refreshListenable: _RouterRefreshNotifier(ref),
    redirect: (context, state) {
      final isLoggedIn = authState.valueOrNull != null;
      final isAuthLoading = authState.isLoading;
      final isOnboardingLoading = onboardingState.isLoading;
      final onboardingDone = onboardingState.valueOrNull ?? false;

      final isOnLogin = state.matchedLocation.startsWith('/login');
      final isOnLanding = state.matchedLocation == '/' || state.matchedLocation == '/landing-preview';
      final isOnOnboarding = state.matchedLocation == '/onboarding';

      // Wait for both auth and onboarding state to load
      if (isAuthLoading || isOnboardingLoading) return null;

      // Not logged in → go to landing (if not already on an auth page)
      if (!isLoggedIn && !isOnLogin && !isOnLanding) return '/';

      // Logged in but on login → redirect to appropriate screen
      // '/landing-preview' is exempt — allows logged-in users to preview the page
      if (isLoggedIn && (isOnLogin || state.matchedLocation == '/')) {
        return onboardingDone ? '/home' : '/onboarding';
      }

      // Logged in but hasn't seen onboarding → show onboarding
      if (isLoggedIn && !isOnOnboarding && !onboardingDone) {
        return '/onboarding';
      }

      return null;
    },
    routes: [
      GoRoute(path: '/', pageBuilder: (_, s) => _fade(s, const LandingScreen())),
      GoRoute(path: '/landing-preview', pageBuilder: (_, s) => _slideUp(s, const LandingScreen())),
      GoRoute(path: '/login', pageBuilder: (_, s) => _fade(s, const LoginScreen())),
      GoRoute(path: '/login/signup', pageBuilder: (_, s) => _slideUp(s, const EmailSignupScreen())),
      GoRoute(path: '/login/email', pageBuilder: (_, s) => _slideUp(s, const EmailLoginScreen())),
      GoRoute(path: '/onboarding', pageBuilder: (_, s) => _fade(s, const OnboardingScreen())),
      GoRoute(path: '/settings', pageBuilder: (_, s) => _slideRight(s, const SettingsScreen())),
      GoRoute(path: '/quiz', pageBuilder: (_, s) => _slideUp(s, const QuizScreen())),
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(path: '/home', builder: (_, __) => const HomeScreen()),
          GoRoute(path: '/timetable', builder: (_, __) => const TimetableScreen()),
          GoRoute(path: '/assignments', builder: (_, __) => const AssignmentsScreen()),
          GoRoute(path: '/ai', builder: (_, __) => const AiChatScreen()),
        ],
      ),
    ],
    errorBuilder: (_, state) => Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Text(
          AppStrings.t('err_page_not_found', {'error': state.error}),
          style: const TextStyle(color: Colors.red),
        ),
      ),
    ),
  );
});

// ─── Page transition helpers ─────────────────────────────────────────────────

/// Simple cross-fade — used for top-level tab switches and login.
CustomTransitionPage<void> _fade(GoRouterState s, Widget child) =>
    CustomTransitionPage<void>(
      key: s.pageKey,
      child: child,
      transitionDuration: const Duration(milliseconds: 280),
      transitionsBuilder: (_, anim, __, c) =>
          FadeTransition(opacity: anim, child: c),
    );

/// Slight upward slide + fade — used for modal-style pushes (sign-up, quiz).
CustomTransitionPage<void> _slideUp(GoRouterState s, Widget child) =>
    CustomTransitionPage<void>(
      key: s.pageKey,
      child: child,
      transitionDuration: const Duration(milliseconds: 340),
      transitionsBuilder: (_, anim, __, c) {
        final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        return SlideTransition(
          position: Tween(begin: const Offset(0, 0.08), end: Offset.zero).animate(curved),
          child: FadeTransition(opacity: curved, child: c),
        );
      },
    );

/// Slight right-to-left slide + fade — used for settings (secondary screen).
CustomTransitionPage<void> _slideRight(GoRouterState s, Widget child) =>
    CustomTransitionPage<void>(
      key: s.pageKey,
      child: child,
      transitionDuration: const Duration(milliseconds: 300),
      transitionsBuilder: (_, anim, __, c) {
        final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        return SlideTransition(
          position: Tween(begin: const Offset(-0.06, 0), end: Offset.zero).animate(curved),
          child: FadeTransition(opacity: curved, child: c),
        );
      },
    );

/// Bridges Riverpod provider changes to GoRouter's [ChangeNotifier]-based
/// refresh mechanism so the router re-evaluates its redirect logic whenever
/// auth or onboarding state changes.
class _RouterRefreshNotifier extends ChangeNotifier {
  _RouterRefreshNotifier(Ref ref) {
    ref.listen(authStateProvider, (_, __) => notifyListeners());
    ref.listen(onboardingProvider, (_, __) => notifyListeners());
  }
}
