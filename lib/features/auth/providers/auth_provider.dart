import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/app_providers.dart';
import '../models/user_model.dart';

/// Streams the currently signed-in [UserModel], or `null` when signed out.
///
/// The router watches this provider to redirect between authenticated and
/// unauthenticated routes whenever the auth state changes.
final authStateProvider = StreamProvider<UserModel?>(
    (ref) => ref.watch(authRepositoryProvider).authStateStream);

/// Convenience provider that exposes the current user synchronously.
///
/// Returns `null` when the stream hasn't emitted yet or the user is signed out.
/// Suitable for one-off reads inside callbacks — prefer [authStateProvider]
/// when you need reactive rebuilds.
final currentUserProvider =
    Provider<UserModel?>((ref) => ref.watch(authStateProvider).valueOrNull);

/// Handles all authentication mutations: Google sign-in, email sign-up/in,
/// and sign-out.
///
/// Each method sets state to [AsyncLoading] then delegates to
/// [AuthRepository] via [AsyncValue.guard], which catches any thrown
/// exceptions and surfaces them as [AsyncError] — the calling screen can
/// display them via `ref.watch(authNotifierProvider).whenOrNull(error: ...)`.
class AuthNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  /// Signs in with a Google account using `GoogleSignIn.instance.authenticate()`.
  /// Only the `idToken` is sent to Firebase — the full Google profile stays
  /// on-device.
  Future<void> signInWithGoogle() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
        () => ref.read(authRepositoryProvider).signInWithGoogle());
  }

  /// Creates a new Firebase Auth account with [email] / [password] and
  /// immediately writes the [name] into the `users/{uid}` Firestore document.
  Future<void> signUpWithEmail(String email, String password, String name) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
        () => ref.read(authRepositoryProvider).signUpWithEmail(email, password, name));
  }

  /// Signs in with an existing [email] / [password] Firebase account.
  Future<void> signInWithEmail(String email, String password) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
        () => ref.read(authRepositoryProvider).signInWithEmail(email, password));
  }

  /// Signs out from Firebase Auth and Google Sign-In.
  /// The router automatically redirects to the landing screen once
  /// [authStateProvider] emits `null`.
  Future<void> signOut() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
        () => ref.read(authRepositoryProvider).signOut());
  }
}

/// Global provider for [AuthNotifier].
///
/// Call `ref.read(authNotifierProvider.notifier).signInWithGoogle()` etc.
/// from button callbacks.  Watch the state for loading/error UI:
/// ```dart
/// ref.watch(authNotifierProvider).whenOrNull(error: (e, _) => showError(e));
/// ```
final authNotifierProvider =
    AsyncNotifierProvider<AuthNotifier, void>(AuthNotifier.new);
