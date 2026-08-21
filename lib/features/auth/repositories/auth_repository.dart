import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../../../core/l10n/app_strings.dart';
import '../models/user_model.dart';

class AuthRepository {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  bool _googleSignInInitialized = false;

  /// Memoized so a re-emission of `userChanges()` for the *same already
  /// resolved* uid (e.g. an ID token refresh, which fires this stream
  /// periodically for the whole session) doesn't re-read the Firestore doc.
  /// Only re-fetches when the uid changes, or when the previous fetch didn't
  /// find a doc yet (the brief window right after sign-up before the caller
  /// writes it) — in that case we keep retrying so the router picks up the
  /// real name as soon as it's written.
  UserModel? _cachedUser;
  String? _cachedUid;
  bool _cachedFromDoc = false;

  Stream<UserModel?> get authStateStream async* {
    await for (final user in _auth.userChanges()) {
      if (user == null) {
        _cachedUser = null;
        _cachedUid = null;
        _cachedFromDoc = false;
        yield null;
        continue;
      }
      if (user.uid == _cachedUid && _cachedFromDoc && _cachedUser != null) {
        yield _cachedUser;
        continue;
      }
      final doc = await _db.collection('users').doc(user.uid).get();
      final model = doc.exists
          ? UserModel.fromFirestore(doc)
          // User is authenticated but Firestore doc not yet written.
          // This happens during the brief window between Firebase Auth completing
          // (which fires userChanges()) and the caller writing the user doc.
          // Return a minimal UserModel so the router doesn't redirect back to /login.
          : UserModel(
              uid: user.uid,
              name: user.displayName ?? 'ユーザー',
              email: user.email ?? '',
              photoUrl: user.photoURL,
              createdAt: DateTime.now(),
            );
      _cachedUser = model;
      _cachedUid = user.uid;
      _cachedFromDoc = doc.exists;
      yield model;
    }
  }

  /// google_sign_in 7.x requires `initialize()` to be called exactly once
  /// before any other method — see the package's MIGRATION.md.
  ///
  /// On web this throws if `web/index.html` has no
  /// `<meta name="google-signin-client_id" ...>` tag (a required, per-platform
  /// setup step — see that file). Wrapped so a missing/misconfigured client
  /// id surfaces as a normal translated error instead of an uncaught
  /// assertion.
  ///
  /// On web this also starts listening for sign-in events fired by the
  /// SDK-rendered button (see `renderGoogleSignInButton()`) — web has no
  /// `authenticate()` support (`supportsAuthenticate()` is hard-coded false
  /// in `google_sign_in_web`), so a user-initiated sign-in there completes
  /// via this event stream instead of a direct method call/return. Once
  /// Firebase sign-in succeeds, `authStateStream` picks it up exactly like
  /// any other sign-in and the router redirects — there's nothing further
  /// for a caller to await.
  Future<void> _ensureGoogleSignInInitialized() async {
    if (_googleSignInInitialized) return;
    try {
      await _googleSignIn.initialize();
      _googleSignInInitialized = true;
    } catch (_) {
      throw Exception(AppStrings.t('err_google_signin_failed'));
    }
    if (kIsWeb) {
      _googleSignIn.authenticationEvents.listen((event) {
        if (event is GoogleSignInAuthenticationEventSignIn) {
          unawaited(_handleWebSignInEvent(event.user));
        }
      });
    }
  }

  Future<void> _handleWebSignInEvent(GoogleSignInAccount account) async {
    try {
      await _completeGoogleSignIn(account);
    } catch (e) {
      debugPrint('Web Google sign-in completion error: $e');
    }
  }

  /// Kicks off Google Sign-In initialization early on web, so the SDK's own
  /// rendered button (which shows "Getting ready" until initialization
  /// resolves) becomes interactive as soon as possible after the login
  /// screen appears, rather than only starting once tapped.
  Future<void> ensureGoogleSignInReady() => _ensureGoogleSignInInitialized();

  Future<UserModel> signInWithGoogle() async {
    await _ensureGoogleSignInInitialized();
    final GoogleSignInAccount googleUser;
    try {
      googleUser = await _googleSignIn.authenticate();
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        throw Exception(AppStrings.t('err_google_signin_cancelled'));
      }
      throw Exception(AppStrings.t('err_google_signin_failed'));
    }
    return _completeGoogleSignIn(googleUser);
  }

  /// Exchanges a [GoogleSignInAccount]'s id token for a Firebase credential
  /// and ensures the `users/{uid}` Firestore doc exists — shared by the
  /// mobile `authenticate()` flow and the web sign-in event listener.
  Future<UserModel> _completeGoogleSignIn(GoogleSignInAccount googleUser) async {
    final credential = GoogleAuthProvider.credential(idToken: googleUser.authentication.idToken);
    final result = await _auth.signInWithCredential(credential);
    final user = result.user;
    if (user == null) throw Exception(AppStrings.t('err_user_info_unavailable'));
    return _getOrCreateUserDoc(user);
  }

  /// Reads the `users/{uid}` doc for [user], creating it with sensible
  /// defaults if it doesn't exist yet. [fallbackEmail] is used only when
  /// [user] itself has no email on file (e.g. some email/password flows).
  Future<UserModel> _getOrCreateUserDoc(User user, {String? fallbackEmail}) async {
    final docRef = _db.collection('users').doc(user.uid);
    final doc = await docRef.get();
    if (doc.exists) return UserModel.fromFirestore(doc);
    final newUser = UserModel(
      uid: user.uid,
      name: user.displayName ?? 'ユーザー',
      email: user.email ?? fallbackEmail ?? '',
      photoUrl: user.photoURL,
      createdAt: DateTime.now(),
    );
    await docRef.set(newUser.toFirestore());
    return newUser;
  }

  /// Registers a brand-new account, or — if [email] is already registered —
  /// transparently logs the user in with the [password] they just typed.
  ///
  /// This turns the sign-up form into a "continue" action: a returning user
  /// who mistakenly lands on sign-up instead of login isn't blocked with a
  /// bare "email already in use" error. If their password matches the
  /// existing account, they're simply signed in (Firebase's `userChanges()`
  /// then routes them to `/home` exactly as a normal login would). If it
  /// doesn't match, [err_account_exists] is thrown instead of a raw
  /// FirebaseAuth error so the message is actionable ("this account already
  /// exists — use the correct password or the login screen").
  Future<UserModel> signUpWithEmail(String email, String password, String name) async {
    try {
      final result = await _auth.createUserWithEmailAndPassword(email: email, password: password);
      final user = result.user;
      if (user == null) throw Exception(AppStrings.t('err_user_info_unavailable'));
      await user.updateDisplayName(name);
      final newUser = UserModel(uid: user.uid, name: name, email: email, createdAt: DateTime.now());
      await _db.collection('users').doc(user.uid).set(newUser.toFirestore());
      return newUser;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'email-already-in-use') {
        try {
          return await signInWithEmail(email, password);
        } catch (_) {
          throw Exception(AppStrings.t('err_account_exists'));
        }
      }
      throw Exception(_authErrorMessage(e.code));
    }
  }

  Future<UserModel> signInWithEmail(String email, String password) async {
    try {
      final result = await _auth.signInWithEmailAndPassword(email: email, password: password);
      final user = result.user;
      if (user == null) throw Exception(AppStrings.t('err_user_info_unavailable'));
      return await _getOrCreateUserDoc(user, fallbackEmail: email);
    } on FirebaseAuthException catch (e) {
      throw Exception(_authErrorMessage(e.code));
    }
  }

  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
    } on FirebaseAuthException catch (e) {
      throw Exception(_authErrorMessage(e.code));
    }
  }

  /// Validates a password-reset `oobCode` (the code embedded in the link
  /// Firebase emails on [sendPasswordResetEmail]) and returns the email
  /// address it belongs to, so the confirmation screen can show "resetting
  /// the password for {email}" before the user commits to a new password.
  Future<String> verifyPasswordResetCode(String code) async {
    try {
      final email = await _auth.verifyPasswordResetCode(code);
      return email;
    } on FirebaseAuthException catch (_) {
      throw Exception(AppStrings.t('reset_code_invalid'));
    }
  }

  /// Applies [newPassword] using a previously-verified `oobCode`.
  Future<void> confirmPasswordReset(String code, String newPassword) async {
    try {
      await _auth.confirmPasswordReset(code: code, newPassword: newPassword);
    } on FirebaseAuthException catch (_) {
      throw Exception(AppStrings.t('reset_code_invalid'));
    }
  }

  String _authErrorMessage(String code) {
    switch (code) {
      case 'email-already-in-use':
        return AppStrings.t('err_email_in_use');
      case 'invalid-email':
        return AppStrings.t('err_invalid_email');
      case 'weak-password':
        return AppStrings.t('err_weak_password');
      case 'user-not-found':
      case 'invalid-credential':
      case 'wrong-password':
        return AppStrings.t('err_invalid_credential');
      case 'user-disabled':
        return AppStrings.t('err_user_disabled');
      case 'too-many-requests':
        return AppStrings.t('err_too_many_requests');
      case 'network-request-failed':
        return AppStrings.t('err_network');
      default:
        return AppStrings.t('err_generic_retry');
    }
  }

  Future<void> signOut() async {
    await Future.wait([_auth.signOut(), _googleSignIn.signOut()]);
  }

  String? get currentUid => _auth.currentUser?.uid;

  /// Merges the mandatory school-profile fields into the current user's
  /// Firestore doc. [grade]/[faculty]/[department]/[course] are optional —
  /// blank strings are written as `null` so they render as "not set" rather
  /// than an empty label.
  Future<void> saveSchoolProfile({
    required String schoolType,
    required String schoolName,
    String? grade,
    String? faculty,
    String? department,
    String? course,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception(AppStrings.t('err_user_info_unavailable'));
    String? blankToNull(String? v) => (v == null || v.trim().isEmpty) ? null : v.trim();
    await _db.collection('users').doc(uid).set({
      'schoolType': schoolType,
      'school': schoolName.trim(),
      'grade': blankToNull(grade),
      'faculty': blankToNull(faculty),
      'department': blankToNull(department),
      'course': blankToNull(course),
    }, SetOptions(merge: true));
    // authStateStream memoizes the model per-uid (see field docs above) and
    // only re-reads Firestore when the uid changes — this write wouldn't
    // otherwise surface until the next unrelated userChanges() emission
    // (token refresh, up to ~1h later). Forcing a re-read here is what makes
    // the router's profileComplete redirect fire immediately after saving.
    _cachedFromDoc = false;
  }
}
