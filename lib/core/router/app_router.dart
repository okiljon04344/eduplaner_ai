import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../l10n/app_strings.dart';
import '../theme/app_colors.dart';
import '../../features/ai_chat/screens/ai_chat_screen.dart';
import '../../features/assignments/screens/assignments_screen.dart';
import '../../features/auth/models/user_model.dart';
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
import '../../features/school/screens/teacher_assignments_screen.dart';
import '../../features/school/screens/teacher_home_screen.dart';
import '../../features/school/screens/teacher_notices_screen.dart';
import '../../features/school/screens/teacher_screen.dart';
import '../../features/settings/screens/settings_screen.dart';
import '../../features/timetable/screens/timetable_import_screen.dart';
import '../../features/timetable/screens/timetable_screen.dart';
import '../../shared/widgets/app_shell.dart';

/// Pure top-level redirect decision function.
///
/// Evaluates Riverpod [authState] and [onboardingState] against the target [location].
String? appRedirect({
  required AsyncValue<UserModel?> authState,
  required AsyncValue<bool> onboardingState,
  required String location,
}) {
  return resolveRedirect(
    currentUser: authState.valueOrNull,
    isAuthLoading: authState.isLoading,
    isOnboardingLoading: onboardingState.isLoading,
    onboardingDone: onboardingState.valueOrNull ?? false,
    location: location,
  );
}

/// Resolves the redirect route based on auth, onboarding state, and current location.
///
/// Pure and synchronous — no side-effects.
String? resolveRedirect({
  required UserModel? currentUser,
  required bool isAuthLoading,
  required bool isOnboardingLoading,
  required bool onboardingDone,
  required String location,
}) {
  // Wait for both auth and onboarding state to load
  if (isAuthLoading || isOnboardingLoading) return null;

  final isLoggedIn = currentUser != null;
  final isOnLogin = location.startsWith('/login');
  final isOnLanding = location == '/';
  final isOnOnboarding = location == '/onboarding';
  final isOnProfileSetup = location == '/profile-setup';

  // Not logged in → go to landing (if not already on an auth page or landing)
  if (!isLoggedIn) {
    if (!isOnLogin && !isOnLanding) return '/';
    return null;
  }

  // Returning user: signed in and profileComplete is true.
  // Flow: straight to /home, never /onboarding, whatever the device flag says.
  if (currentUser.profileComplete) {
    // /profile-setup stays reachable: Settings pushes it to edit school info.
    if (isOnLogin || isOnLanding || isOnOnboarding) return '/home';
    return null;
  }

  // New user: signed in but profileComplete is false (no school profile yet).
  // Flow: /onboarding (if not seen on this device) then /profile-setup then /home.
  if (!onboardingDone) {
    return isOnOnboarding ? null : '/onboarding';
  }

  // Onboarding done on this device, but school profile setup not completed yet.
  return isOnProfileSetup ? null : '/profile-setup';
}

/// Checks if the signed-in user is a returning user (`profileComplete == true`)
/// whose device onboarding flag is not yet marked done. If so, calls
/// [OnboardingNotifier.markDone] asynchronously outside the redirect callback.
void syncReturningUserOnboarding(Ref ref) {
  final user = ref.read(authStateProvider).valueOrNull;
  if (user != null && user.profileComplete) {
    final onboardingDone = ref.read(onboardingProvider).valueOrNull;
    if (onboardingDone == false) {
      Future.microtask(() {
        ref.read(onboardingProvider.notifier).markDone();
      });
    }
  }
}

/// Provides the singleton [GoRouter] instance.
///
/// The router is created once inside a Riverpod [Provider]; its redirect reads
/// [authStateProvider] and [onboardingProvider] and is re-run by
/// `_RouterRefreshNotifier` when auth state changes (e.g. sign-out from any screen).
///
/// Redirect logic (evaluated on every navigation and on auth/onboarding state changes):
///   - While either provider is loading → no redirect (avoid flicker).
///   - Not logged in and not on an auth/landing path → redirect to `'/'`.
///   - Returning user (`profileComplete` true) → straight to `/home`, never `/onboarding`.
///   - New user (`profileComplete` false) and onboarding not done → redirect to `/onboarding`.
///   - New user, onboarded, but mandatory school-profile step missing → redirect to `/profile-setup`.
final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/home',
    refreshListenable: _RouterRefreshNotifier(ref),
    redirect: (context, state) {
      // read (not watch): the notifier below re-runs redirect, and watching
      // would recreate the GoRouter on every auth change.
      final authState = ref.read(authStateProvider);
      final onboardingState = ref.read(onboardingProvider);
      return appRedirect(
        authState: authState,
        onboardingState: onboardingState,
        location: state.matchedLocation,
      );
    },
    routes: [
      GoRoute(path: '/', pageBuilder: (_, s) => _fade(s, const LandingScreen())),
      GoRoute(path: '/login', pageBuilder: (_, s) => _fade(s, const LoginScreen())),
      GoRoute(path: '/login/signup', pageBuilder: (_, s) => _slideUp(s, const EmailSignupScreen())),
      GoRoute(path: '/login/email', pageBuilder: (_, s) => _slideUp(s, const EmailLoginScreen())),
      GoRoute(path: '/login/reset', pageBuilder: (_, s) => _slideUp(s, const ResetPasswordScreen())),
      GoRoute(path: '/onboarding', pageBuilder: (_, s) => _fade(s, const OnboardingScreen())),
      GoRoute(path: '/profile-setup', pageBuilder: (_, s) => _fade(s, const ProfileSetupScreen())),
      GoRoute(path: '/quiz', pageBuilder: (_, s) => _slideUp(s, const QuizScreen())),
      GoRoute(path: '/teacher', pageBuilder: (_, s) => _slideRight(s, const TeacherHomeScreen())),
      GoRoute(path: '/teacher/timetable', pageBuilder: (_, s) => _slideRight(s, const TeacherScreen())),
      GoRoute(path: '/teacher/timetable/import', pageBuilder: (_, s) => _slideRight(s, const TimetableImportScreen())),
      GoRoute(path: '/teacher/notices', pageBuilder: (_, s) => _slideRight(s, const TeacherNoticesScreen())),
      GoRoute(path: '/teacher/assignments', pageBuilder: (_, s) => _slideRight(s, const TeacherAssignmentsScreen())),
      GoRoute(path: '/school-admin', pageBuilder: (_, s) => _slideRight(s, const SchoolAdminScreen())),
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(path: '/home', builder: (_, __) => const HomeScreen()),
          GoRoute(path: '/timetable', builder: (_, __) => const TimetableScreen()),
          GoRoute(path: '/assignments', builder: (_, __) => const AssignmentsScreen()),
          GoRoute(path: '/ai', builder: (_, __) => const AiChatScreen()),
          GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
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
      transitionDuration: const Duration(milliseconds: 220),
      reverseTransitionDuration: const Duration(milliseconds: 220),
      transitionsBuilder: (_, anim, __, c) =>
          FadeTransition(opacity: anim, child: c),
    );

/// Slight upward slide + fade — used for modal-style pushes (sign-up, quiz).
CustomTransitionPage<void> _slideUp(GoRouterState s, Widget child) =>
    CustomTransitionPage<void>(
      key: s.pageKey,
      child: child,
      transitionDuration: const Duration(milliseconds: 260),
      reverseTransitionDuration: const Duration(milliseconds: 260),
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
      transitionDuration: const Duration(milliseconds: 240),
      reverseTransitionDuration: const Duration(milliseconds: 240),
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
///
/// Also synchronizes the device onboarding flag for returning users outside
/// of the synchronous redirect callback.
class _RouterRefreshNotifier extends ChangeNotifier {
  _RouterRefreshNotifier(Ref ref) {
    ref.listen(authStateProvider, (_, __) {
      syncReturningUserOnboarding(ref);
      notifyListeners();
    });
    ref.listen(onboardingProvider, (_, __) {
      syncReturningUserOnboarding(ref);
      notifyListeners();
    });
    syncReturningUserOnboarding(ref);
  }
}
