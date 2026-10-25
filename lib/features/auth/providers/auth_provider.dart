import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/app_providers.dart';
import '../models/user_model.dart';

/// The signed-in [UserModel], or null when signed out. The router watches this.
final authStateProvider = StreamProvider<UserModel?>(
    (ref) => ref.watch(authRepositoryProvider).authStateStream);

/// Synchronous snapshot of [authStateProvider]; null until the stream emits.
/// Use for one-off reads in callbacks, not for reactive rebuilds.
final currentUserProvider =
    Provider<UserModel?>((ref) => ref.watch(authStateProvider).valueOrNull);

/// Auth mutations. Each runs through [AsyncValue.guard], so failures surface as
/// [AsyncError] for the calling screen to display.
class AuthNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  /// Signs in with Google. Only the `idToken` is sent to Firebase; the rest of
  /// the Google profile stays on-device.
  Future<void> signInWithGoogle() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
        () => ref.read(authRepositoryProvider).signInWithGoogle());
  }

  /// Creates an Auth account and writes [name] into `users/{uid}`.
  Future<void> signUpWithEmail(String email, String password, String name) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
        () => ref.read(authRepositoryProvider).signUpWithEmail(email, password, name));
  }

  Future<void> signInWithEmail(String email, String password) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
        () => ref.read(authRepositoryProvider).signInWithEmail(email, password));
  }

  /// The router redirects to the landing screen once [authStateProvider] emits null.
  Future<void> signOut() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
        () => ref.read(authRepositoryProvider).signOut());
  }

  /// Saves the school profile, then invalidates [authStateProvider] so the
  /// router's profile-setup redirect clears now, not at the next auth event.
  Future<void> saveSchoolProfile({
    required String schoolType,
    required String schoolName,
    String? grade,
    String? program,
    String? faculty,
    String? department,
    String? course,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await ref.read(authRepositoryProvider).saveSchoolProfile(
            schoolType: schoolType,
            schoolName: schoolName,
            grade: grade,
            program: program,
            faculty: faculty,
            department: department,
            course: course,
          );
      ref.invalidate(authStateProvider);
    });
  }
}

final authNotifierProvider =
    AsyncNotifierProvider<AuthNotifier, void>(AuthNotifier.new);
