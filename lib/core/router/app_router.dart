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
import '../../features/auth/screens/reset_password_screen.dart';
import '../../features/home/screens/home_screen.dart';
import '../../features/landing/screens/landing_screen.dart';
import '../../features/auth/screens/profile_setup_screen.dart';
import '../../features/onboarding/providers/onboarding_provider.dart';
import '../../features/onboarding/screens/onboarding_screen.dart';
import '../../features/quiz/screens/quiz_screen.dart';
import '../../features/settings/screens/settings_screen.dart';
import '../../features/timetable/screens/timetable_screen.dart';
import '../../shared/widgets/app_shell.dart';

/// The app's single [GoRouter]. Its redirect reads [authStateProvider] and
/// [onboardingProvider] and is re-run by `_RouterRefreshNotifier` when either changes.
///
/// Redirects:
///   - Either provider loading: none (avoids flicker).
///   - Logged out outside the login/landing routes: `/`.
///   - Logged in on login or `/`: `/onboarding`, `/profile-setup` or `/home`.
///   - Logged in, onboarding not done: `/onboarding`.
///   - Logged in, onboarded, `profileComplete` false: `/profile-setup`. This also
///     catches accounts created before that field existed.
final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/home',
    refreshListenable: _RouterRefreshNotifier(ref),
    redirect: (context, state) {
      // read, not watch: the refresh notifier re-runs redirect, and watching
      // would recreate the GoRouter on every auth change.
      final authState = ref.read(authStateProvider);
      final onboardingState = ref.read(onboardingProvider);
      final currentUser = authState.valueOrNull;
      final isLoggedIn = currentUser != null;
      final isAuthLoading = authState.isLoading;
      final isOnboardingLoading = onboardingState.isLoading;
      final onboardingDone = onboardingState.valueOrNull ?? false;
      final needsProfileSetup = isLoggedIn && !currentUser.profileComplete;

      final isOnLogin = state.matchedLocation.startsWith('/login');
      final isOnLanding = state.matchedLocation == '/';
      final isOnOnboarding = state.matchedLocation == '/onboarding';
      final isOnProfileSetup = state.matchedLocation == '/profile-setup';

      if (isAuthLoading || isOnboardingLoading) return null;

      if (!isLoggedIn && !isOnLogin && !isOnLanding) return '/';

      if (isLoggedIn && (isOnLogin || state.matchedLocation == '/')) {
        if (!onboardingDone) return '/onboarding';
        if (needsProfileSetup) return '/profile-setup';
        return '/home';
      }

      // Onboarding just finished: nothing else navigates away from /onboarding.
      if (isLoggedIn && isOnOnboarding && onboardingDone) {
        return needsProfileSetup ? '/profile-setup' : '/home';
      }

      if (isLoggedIn && !isOnOnboarding && !onboardingDone) {
        return '/onboarding';
      }

      // Block every other route until the school profile is filled in.
      if (isLoggedIn &&
          onboardingDone &&
          needsProfileSetup &&
          !isOnProfileSetup) {
        return '/profile-setup';
      }

      return null;
    },
    routes: [
      GoRoute(
          path: '/', pageBuilder: (_, s) => _fade(s, const LandingScreen())),
      GoRoute(
          path: '/login', pageBuilder: (_, s) => _fade(s, const LoginScreen())),
      GoRoute(
          path: '/login/signup',
          pageBuilder: (_, s) => _slideUp(s, const EmailSignupScreen())),
      GoRoute(
          path: '/login/email',
          pageBuilder: (_, s) => _slideUp(s, const EmailLoginScreen())),
      GoRoute(
          path: '/login/reset',
          pageBuilder: (_, s) => _slideUp(s, const ResetPasswordScreen())),
      GoRoute(
          path: '/onboarding',
          pageBuilder: (_, s) => _fade(s, const OnboardingScreen())),
      GoRoute(
          path: '/profile-setup',
          pageBuilder: (_, s) => _fade(s, const ProfileSetupScreen())),
      GoRoute(
          path: '/settings',
          pageBuilder: (_, s) => _slideRight(s, const SettingsScreen())),
      GoRoute(
          path: '/quiz',
          pageBuilder: (_, s) => _slideUp(s, const QuizScreen())),
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(path: '/home', builder: (_, __) => const HomeScreen()),
          GoRoute(
              path: '/timetable', builder: (_, __) => const TimetableScreen()),
          GoRoute(
              path: '/assignments',
              builder: (_, __) => const AssignmentsScreen()),
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

/// Cross-fade for top-level tabs and login.
CustomTransitionPage<void> _fade(GoRouterState s, Widget child) =>
    CustomTransitionPage<void>(
      key: s.pageKey,
      child: child,
      transitionDuration: const Duration(milliseconds: 220),
      reverseTransitionDuration: const Duration(milliseconds: 220),
      transitionsBuilder: (_, anim, __, c) =>
          FadeTransition(opacity: anim, child: c),
    );

/// Slight upward slide + fade for modal-style pushes (sign-up, quiz).
CustomTransitionPage<void> _slideUp(GoRouterState s, Widget child) =>
    CustomTransitionPage<void>(
      key: s.pageKey,
      child: child,
      transitionDuration: const Duration(milliseconds: 260),
      reverseTransitionDuration: const Duration(milliseconds: 260),
      transitionsBuilder: (_, anim, __, c) {
        final curved =
            CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        return SlideTransition(
          position: Tween(begin: const Offset(0, 0.08), end: Offset.zero)
              .animate(curved),
          child: FadeTransition(opacity: curved, child: c),
        );
      },
    );

/// Slight horizontal slide + fade for settings.
CustomTransitionPage<void> _slideRight(GoRouterState s, Widget child) =>
    CustomTransitionPage<void>(
      key: s.pageKey,
      child: child,
      transitionDuration: const Duration(milliseconds: 240),
      reverseTransitionDuration: const Duration(milliseconds: 240),
      transitionsBuilder: (_, anim, __, c) {
        final curved =
            CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        return SlideTransition(
          position: Tween(begin: const Offset(-0.06, 0), end: Offset.zero)
              .animate(curved),
          child: FadeTransition(opacity: curved, child: c),
        );
      },
    );

/// Bridges Riverpod changes to GoRouter's [ChangeNotifier]-based refresh.
class _RouterRefreshNotifier extends ChangeNotifier {
  _RouterRefreshNotifier(Ref ref) {
    ref.listen(authStateProvider, (_, __) => notifyListeners());
    ref.listen(onboardingProvider, (_, __) => notifyListeners());
  }
}
