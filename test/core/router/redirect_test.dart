import 'package:edu_planner_ai/core/router/app_router.dart';
import 'package:edu_planner_ai/features/auth/models/user_model.dart';
import 'package:edu_planner_ai/features/auth/providers/auth_provider.dart';
import 'package:edu_planner_ai/features/onboarding/providers/onboarding_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

UserModel _buildUser({
  String uid = 'test-uid',
  String name = 'テスト生徒',
  String email = 'student@example.com',
  String? schoolType,
}) {
  return UserModel(
    uid: uid,
    name: name,
    email: email,
    schoolType: schoolType,
    createdAt: DateTime(2026, 1, 1),
  );
}

void main() {
  final newUser = _buildUser(schoolType: null);
  final returningUser = _buildUser(schoolType: 'vocational');

  group('Pure redirect logic (appRedirect & resolveRedirect)', () {
    test('loading states unchanged', () {
      // Auth loading
      expect(
        appRedirect(
          authState: const AsyncLoading(),
          onboardingState: const AsyncData(false),
          location: '/home',
        ),
        isNull,
      );
      expect(
        appRedirect(
          authState: const AsyncLoading(),
          onboardingState: const AsyncData(true),
          location: '/login',
        ),
        isNull,
      );

      // Onboarding loading
      expect(
        appRedirect(
          authState: AsyncData(returningUser),
          onboardingState: const AsyncLoading(),
          location: '/login',
        ),
        isNull,
      );
      expect(
        appRedirect(
          authState: AsyncData(newUser),
          onboardingState: const AsyncLoading(),
          location: '/home',
        ),
        isNull,
      );

      // Both loading
      expect(
        appRedirect(
          authState: const AsyncLoading(),
          onboardingState: const AsyncLoading(),
          location: '/home',
        ),
        isNull,
      );
    });

    test('logged out on /home -> /login (keep whatever the current logged-out behavior is)', () {
      // Current behavior redirects unauthenticated users on protected paths to '/' (landing)
      expect(
        appRedirect(
          authState: const AsyncData(null),
          onboardingState: const AsyncData(true),
          location: '/home',
        ),
        '/',
      );
      expect(
        appRedirect(
          authState: const AsyncData(null),
          onboardingState: const AsyncData(false),
          location: '/timetable',
        ),
        '/',
      );

      // Auth pages and landing allow access without redirect
      expect(
        appRedirect(
          authState: const AsyncData(null),
          onboardingState: const AsyncData(false),
          location: '/login',
        ),
        isNull,
      );
      expect(
        appRedirect(
          authState: const AsyncData(null),
          onboardingState: const AsyncData(false),
          location: '/login/reset',
        ),
        isNull,
      );
      expect(
        appRedirect(
          authState: const AsyncData(null),
          onboardingState: const AsyncData(false),
          location: '/login/email',
        ),
        isNull,
      );
      expect(
        appRedirect(
          authState: const AsyncData(null),
          onboardingState: const AsyncData(false),
          location: '/',
        ),
        isNull,
      );
    });

    test('new user + onboarding not done -> /onboarding', () {
      expect(newUser.profileComplete, isFalse);

      expect(
        appRedirect(
          authState: AsyncData(newUser),
          onboardingState: const AsyncData(false),
          location: '/home',
        ),
        '/onboarding',
      );
      expect(
        appRedirect(
          authState: AsyncData(newUser),
          onboardingState: const AsyncData(false),
          location: '/',
        ),
        '/onboarding',
      );
      expect(
        appRedirect(
          authState: AsyncData(newUser),
          onboardingState: const AsyncData(false),
          location: '/login',
        ),
        '/onboarding',
      );
      expect(
        appRedirect(
          authState: AsyncData(newUser),
          onboardingState: const AsyncData(false),
          location: '/profile-setup',
        ),
        '/onboarding',
      );

      // Already on /onboarding -> stays on /onboarding
      expect(
        appRedirect(
          authState: AsyncData(newUser),
          onboardingState: const AsyncData(false),
          location: '/onboarding',
        ),
        isNull,
      );
    });

    test('new user + onboarding done -> /profile-setup', () {
      expect(newUser.profileComplete, isFalse);

      expect(
        appRedirect(
          authState: AsyncData(newUser),
          onboardingState: const AsyncData(true),
          location: '/home',
        ),
        '/profile-setup',
      );
      expect(
        appRedirect(
          authState: AsyncData(newUser),
          onboardingState: const AsyncData(true),
          location: '/',
        ),
        '/profile-setup',
      );
      expect(
        appRedirect(
          authState: AsyncData(newUser),
          onboardingState: const AsyncData(true),
          location: '/login',
        ),
        '/profile-setup',
      );
      expect(
        appRedirect(
          authState: AsyncData(newUser),
          onboardingState: const AsyncData(true),
          location: '/onboarding',
        ),
        '/profile-setup',
      );

      // Already on /profile-setup -> stays on /profile-setup
      expect(
        appRedirect(
          authState: AsyncData(newUser),
          onboardingState: const AsyncData(true),
          location: '/profile-setup',
        ),
        isNull,
      );
    });

    test('returning user + onboarding not done -> /home (not /onboarding)', () {
      expect(returningUser.profileComplete, isTrue);

      // Even if onboarding_done is false on this device, returning users go to /home
      expect(
        appRedirect(
          authState: AsyncData(returningUser),
          onboardingState: const AsyncData(false),
          location: '/onboarding',
        ),
        '/home',
      );
      expect(
        appRedirect(
          authState: AsyncData(returningUser),
          onboardingState: const AsyncData(false),
          location: '/',
        ),
        '/home',
      );

      // If already on /home, stays on /home and never redirected to /onboarding
      expect(
        appRedirect(
          authState: AsyncData(returningUser),
          onboardingState: const AsyncData(false),
          location: '/home',
        ),
        isNull,
      );
    });

    test('returning user on /login -> /home', () {
      expect(returningUser.profileComplete, isTrue);

      // On /login with onboarding done
      expect(
        appRedirect(
          authState: AsyncData(returningUser),
          onboardingState: const AsyncData(true),
          location: '/login',
        ),
        '/home',
      );

      // On /login with onboarding NOT done
      expect(
        appRedirect(
          authState: AsyncData(returningUser),
          onboardingState: const AsyncData(false),
          location: '/login',
        ),
        '/home',
      );

      // Sub-routes under /login
      expect(
        appRedirect(
          authState: AsyncData(returningUser),
          onboardingState: const AsyncData(false),
          location: '/login/email',
        ),
        '/home',
      );
      expect(
        appRedirect(
          authState: AsyncData(returningUser),
          onboardingState: const AsyncData(true),
          location: '/login/signup',
        ),
        '/home',
      );
    });

    test('returning user allowed on protected app routes', () {
      expect(
        appRedirect(
          authState: AsyncData(returningUser),
          onboardingState: const AsyncData(true),
          location: '/timetable',
        ),
        isNull,
      );
      expect(
        appRedirect(
          authState: AsyncData(returningUser),
          onboardingState: const AsyncData(false),
          location: '/assignments',
        ),
        isNull,
      );
      expect(
        appRedirect(
          authState: AsyncData(returningUser),
          onboardingState: const AsyncData(false),
          location: '/settings',
        ),
        isNull,
      );
    });
  });

  group('syncReturningUserOnboarding', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({'onboarding_done': false});
    });

    test('marks onboarding done asynchronously for returning user', () async {
      final refProvider = Provider<Ref>((ref) => ref);
      final container = ProviderContainer(
        overrides: [
          authStateProvider.overrideWith((ref) => Stream.value(returningUser)),
        ],
      );
      addTearDown(container.dispose);

      // Wait for providers to initialize
      await container.read(authStateProvider.future);
      await container.read(onboardingProvider.future);

      expect(container.read(onboardingProvider).valueOrNull, isFalse);

      final ref = container.read(refProvider);
      syncReturningUserOnboarding(ref);

      // Wait for microtask to execute
      await Future<void>.delayed(Duration.zero);

      expect(container.read(onboardingProvider).valueOrNull, isTrue);
    });

    test('does not mark onboarding done for new user', () async {
      final refProvider = Provider<Ref>((ref) => ref);
      final container = ProviderContainer(
        overrides: [
          authStateProvider.overrideWith((ref) => Stream.value(newUser)),
        ],
      );
      addTearDown(container.dispose);

      await container.read(authStateProvider.future);
      await container.read(onboardingProvider.future);

      expect(container.read(onboardingProvider).valueOrNull, isFalse);

      final ref = container.read(refProvider);
      syncReturningUserOnboarding(ref);

      await Future<void>.delayed(Duration.zero);

      expect(container.read(onboardingProvider).valueOrNull, isFalse);
    });

    test('does not mark onboarding done for logged out state', () async {
      final refProvider = Provider<Ref>((ref) => ref);
      final container = ProviderContainer(
        overrides: [
          authStateProvider.overrideWith((ref) => Stream.value(null)),
        ],
      );
      addTearDown(container.dispose);

      await container.read(authStateProvider.future);
      await container.read(onboardingProvider.future);

      expect(container.read(onboardingProvider).valueOrNull, isFalse);

      final ref = container.read(refProvider);
      syncReturningUserOnboarding(ref);

      await Future<void>.delayed(Duration.zero);

      expect(container.read(onboardingProvider).valueOrNull, isFalse);
    });
  });

  test('returning user can open /profile-setup to edit (Settings)', () {
    expect(
      resolveRedirect(
        currentUser: returningUser,
        isAuthLoading: false,
        isOnboardingLoading: false,
        onboardingDone: true,
        location: '/profile-setup',
      ),
      isNull,
    );
  });
}
