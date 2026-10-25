import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/services/notification_service.dart';
import '../models/user_model.dart';

class AuthRepository {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  bool _googleSignInInitialized = false;

  /// Memoised per uid so token refreshes (which re-emit `userChanges()`) don't
  /// re-read the Firestore doc. Re-fetches when the uid changes and keeps
  /// retrying while no doc exists yet (the window right after sign-up).
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
      DocumentSnapshot<Map<String, dynamic>>? doc;
      try {
        doc = await _db.collection('users').doc(user.uid).get();
      } catch (e) {
        // A failed read must never end this stream: the router would treat
        // the user as signed out until restart.
        debugPrint('User doc read error: $e');
        if (user.uid == _cachedUid && _cachedUser != null) {
          yield _cachedUser;
          continue;
        }
        doc = await _retryUserDocRead(user.uid);
      }
      final exists = doc?.exists ?? false;
      final model = doc != null && exists
          ? UserModel.fromFirestore(doc)
          // Signed in but the doc isn't written yet (right after sign-up):
          // return a minimal model so the router doesn't bounce back to /login.
          : UserModel(
              uid: user.uid,
              name: user.displayName ?? '',
              email: user.email ?? '',
              photoUrl: user.photoURL,
              createdAt: DateTime.now(),
            );
      _cachedUser = model;
      _cachedUid = user.uid;
      _cachedFromDoc = exists;
      yield model;
    }
  }

  /// Retries the read up to 3 times, 2s apart. Null if every attempt fails.
  Future<DocumentSnapshot<Map<String, dynamic>>?> _retryUserDocRead(String uid) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      await Future<void>.delayed(const Duration(seconds: 2));
      try {
        return await _db.collection('users').doc(uid).get();
      } catch (e) {
        debugPrint('User doc retry ${attempt + 1} error: $e');
      }
    }
    return null;
  }

  /// google_sign_in 7.x needs `initialize()` exactly once before anything else.
  ///
  /// Wrapped so a missing web client id (`google-signin-client_id` meta tag in
  /// `web/index.html`) surfaces as a translated error, not an uncaught assertion.
  ///
  /// On web `authenticate()` is unsupported, so sign-in through the SDK-rendered
  /// button completes via the event stream listened to here. `authStateStream`
  /// then picks it up like any other sign-in; callers have nothing to await.
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

  /// Starts initialisation early on web so the SDK-rendered button is
  /// interactive as soon as the login screen appears.
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

  /// Exchanges the Google id token for a Firebase credential and ensures the
  /// `users/{uid}` doc exists. Shared by mobile and the web event listener.
  Future<UserModel> _completeGoogleSignIn(GoogleSignInAccount googleUser) async {
    final credential = GoogleAuthProvider.credential(idToken: googleUser.authentication.idToken);
    final result = await _auth.signInWithCredential(credential);
    final user = result.user;
    if (user == null) throw Exception(AppStrings.t('err_user_info_unavailable'));
    return _getOrCreateUserDoc(user);
  }

  /// Reads `users/{uid}`, creating it with defaults if missing. [fallbackEmail]
  /// is used only when [user] has no email.
  Future<UserModel> _getOrCreateUserDoc(User user, {String? fallbackEmail}) async {
    final docRef = _db.collection('users').doc(user.uid);
    final doc = await docRef.get();
    if (doc.exists) return UserModel.fromFirestore(doc);
    final newUser = UserModel(
      uid: user.uid,
      name: user.displayName ?? '',
      email: user.email ?? fallbackEmail ?? '',
      photoUrl: user.photoURL,
      createdAt: DateTime.now(),
    );
    await docRef.set(newUser.toFirestore());
    return newUser;
  }

  /// Registers a new account, or signs in if [email] is already registered and
  /// [password] matches, so a returning user who lands on sign-up isn't blocked.
  /// A wrong password throws `err_account_exists` (actionable) instead of the
  /// raw FirebaseAuth error.
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

  /// Validates a password-reset `oobCode` and returns the email it belongs to,
  /// so the confirmation screen can name the account before the user commits.
  Future<String> verifyPasswordResetCode(String code) async {
    try {
      return await _auth.verifyPasswordResetCode(code);
    } on FirebaseAuthException catch (_) {
      throw Exception(AppStrings.t('reset_code_invalid'));
    }
  }

  /// Applies [newPassword] using a previously verified `oobCode`.
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

  /// Signs out after best-effort cleanup of per-user, device-local state (push
  /// token, reminders, cached AI results) so the next account doesn't inherit
  /// it. Cleanup failures never block sign-out.
  Future<void> signOut() async {
    final uid = _auth.currentUser?.uid;
    if (uid != null) {
      try {
        await NotificationService.unregisterPushToken(uid);
      } catch (e) {
        debugPrint('Push token unregister error: $e');
      }
    }
    try {
      await NotificationService.cancelAll();
    } catch (e) {
      debugPrint('Cancel reminders error: $e');
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final key in prefs.getKeys().toList()) {
        // `streak_*` is deliberately kept: the streak is per-device, not per-account.
        if (key.startsWith('study_tip_') || key.startsWith('weak_area_')) {
          await prefs.remove(key);
        }
      }
    } catch (e) {
      debugPrint('Clear cached data error: $e');
    }
    await Future.wait([_auth.signOut(), _googleSignIn.signOut()]);
  }

  /// Merges the school-profile fields into the current user's doc. The optional
  /// fields are stored as null when blank so they render as "not set".
  Future<void> saveSchoolProfile({
    required String schoolType,
    required String schoolName,
    String? grade,
    String? program,
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
      'program': blankToNull(program),
      'faculty': blankToNull(faculty),
      'department': blankToNull(department),
      'course': blankToNull(course),
    }, SetOptions(merge: true));
    // authStateStream caches the model per uid; drop the cache flag so the next
    // emission re-reads this write instead of waiting for a token refresh (~1h).
    _cachedFromDoc = false;
  }
}
