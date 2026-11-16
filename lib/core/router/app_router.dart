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
import '../../features/school/screens/board_screen.dart';
import '../../features/school/screens/teacher_notices_screen.dart';
import '../../features/school/screens/teacher_screen.dart';
import '../../features/settings/screens/settings_screen.dart';
import '../../features/timetable/screens/timetable_screen.dart';
import '../../shared/widgets/app_shell.dart';

/// Pure top-level redirect decision function.
///
/// Evaluates Riverpod [authState] and [onboardingState] against the target [location].
///
/// UZ: Yuqori darajadagi sof qayta yo'naltirish (redirect) qarori funksiyasi.
///
/// Riverpod [authState] va [onboardingState] holatlarini nishon [location] ga nisbatan baholaydi.
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
///
/// UZ: Autentifikatsiya, onboarding holati va joriy joylashuv asosida qayta yo'naltirish marshrutini hal qiladi.
///
/// Sof va sinxron — nojo'ya ta'sirlarsiz (no side-effects).
String? resolveRedirect({
  required UserModel? currentUser,
  required bool isAuthLoading,
  required bool isOnboardingLoading,
  required bool onboardingDone,
  required String location,
}) {
  // Wait for both auth and onboarding state to load
  // UZ: Ham autentifikatsiya, ham onboarding holati yuklanishini kutish
  if (isAuthLoading || isOnboardingLoading) return null;

  final isLoggedIn = currentUser != null;
  final isOnLogin = location.startsWith('/login');
  final isOnLanding = location == '/';
  final isOnOnboarding = location == '/onboarding';
  final isOnProfileSetup = location == '/profile-setup';

  // Not logged in → go to landing (if not already on an auth page or landing)
  // UZ: Tizimga kirmagan → landing sahifasiga o'tish (agar hali auth yoki landing sahifasida bo'lmasa)
  if (!isLoggedIn) {
    if (!isOnLogin && !isOnLanding) return '/';
    return null;
  }

  // Returning user: signed in and profileComplete is true.
  // Flow: straight to /home, never /onboarding, whatever the device flag says.
  // UZ: Qaytgan foydalanuvchi: tizimga kirgan va profileComplete qiymati true.
  // Oqim: to'g'ridan-to'g'ri /home ga, hech qachon /onboarding ga emas, qurilma bayrog'i nima deyishidan qat'i nazar.
  if (currentUser.profileComplete) {
    // /profile-setup stays reachable: Settings pushes it to edit school info.
    // UZ: /profile-setup ochiq qoladi: Sozlamalar maktab ma'lumotlarini tahrirlash uchun uni ochadi.
    if (isOnLogin || isOnLanding || isOnOnboarding) return '/home';
    return null;
  }

  // New user: signed in but profileComplete is false (no school profile yet).
  // Flow: /onboarding (if not seen on this device) then /profile-setup then /home.
  // UZ: Yangi foydalanuvchi: tizimga kirgan, lekin profileComplete qiymati false (hali maktab profili yo'q).
  // Oqim: /onboarding (agar bu qurilmada ko'rilmagan bo'lsa), keyin /profile-setup, keyin /home.
  if (!onboardingDone) {
    return isOnOnboarding ? null : '/onboarding';
  }

  // Onboarding done on this device, but school profile setup not completed yet.
  // UZ: Ushbu qurilmada onboarding yakunlangan, lekin maktab profilini sozlash hali tugallanmagan.
  return isOnProfileSetup ? null : '/profile-setup';
}

/// Checks if the signed-in user is a returning user (`profileComplete == true`)
/// whose device onboarding flag is not yet marked done. If so, calls
/// [OnboardingNotifier.markDone] asynchronously outside the redirect callback.
///
/// UZ: Tizimga kirgan foydalanuvchi qurilmadagi onboarding bayrog'i hali bajarildi deb belgilanmagan
/// qaytgan foydalanuvchi (`profileComplete == true`) ekanligini tekshiradi. Agar shunday bo'lsa,
/// qayta yo'naltirish chaqiruvidan tashqarida asinxron ravishda [OnboardingNotifier.markDone] ni chaqiradi.
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
///
/// UZ: Yagona [GoRouter] instansiyasini taqdim etadi.
///
/// Router Riverpod [Provider] ichida bir marta yaratiladi; uning qayta yo'naltirishi
/// [authStateProvider] va [onboardingProvider] ni o'qiydi va autentifikatsiya holati o'zgarganda
/// (masalan, istalgan ekrandan chiqish) `_RouterRefreshNotifier` tomonidan qayta ishga tushiriladi.
///
/// Qayta yo'naltirish mantiqi (har bir navigatsiyada va auth/onboarding holati o'zgarganda baholanadi):
///   - Har ikkala provider yuklanayotganda → qayta yo'naltirish yo'q (miltillashning oldini olish).
///   - Tizimga kirmagan va auth/landing yo'lida bo'lmaganda → `'/'` ga qayta yo'naltirish.
///   - Qaytgan foydalanuvchi (`profileComplete` true) → to'g'ridan-to'g'ri `/home` ga, hech qachon `/onboarding` ga emas.
///   - Yangi foydalanuvchi (`profileComplete` false) va onboarding bajarilmagan → `/onboarding` ga qayta yo'naltirish.
///   - Yangi foydalanuvchi, onboardingdan o'tgan, lekin majburiy maktab profili bosqichi yetishmayapti → `/profile-setup` ga qayta yo'naltirish.
final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/home',
    refreshListenable: _RouterRefreshNotifier(ref),
    redirect: (context, state) {
      // read (not watch): the notifier below re-runs redirect, and watching
      // would recreate the GoRouter on every auth change.
      // UZ: read (watch emas): quyidagi bildirishnoma qayta yo'naltirishni qayta ishga tushiradi,
      // va watching har bir auth o'zgarishida GoRouter'ni qayta yaratadi.
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
      GoRoute(
          path: '/board',
          pageBuilder: (_, s) => _slideRight(s, BoardScreen(subject: s.uri.queryParameters['subject']))),
      GoRoute(path: '/teacher', pageBuilder: (_, s) => _slideRight(s, const TeacherHomeScreen())),
      GoRoute(path: '/teacher/timetable', pageBuilder: (_, s) => _slideRight(s, const TeacherScreen())),
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
///
/// UZ: Oddiy cross-fade — yuqori darajadagi tab almashinuvi va login uchun ishlatiladi.
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
///
/// UZ: Yengil yuqoriga siljish + fade — modal uslubidagi push'lar uchun ishlatiladi (ro'yxatdan o'tish, quiz).
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
///
/// UZ: O'ngdan chapga yengil siljish + fade — sozlamalar uchun ishlatiladi (ikkilamchi ekran).
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
///
/// UZ: Riverpod provider o'zgarishlarini GoRouter'ning [ChangeNotifier] asosidagi yangilash
/// mexanizmiga bog'laydi, shunda router autentifikatsiya yoki onboarding holati o'zgarganda
/// o'zining qayta yo'naltirish mantiqini qayta baholaydi.
///
/// Shuningdek, qaytgan foydalanuvchilar uchun qurilmadagi onboarding bayrog'ini sinxron qayta
/// yo'naltirish chaqiruvidan tashqarida sinxronlashtiradi.
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
