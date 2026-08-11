import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../../../core/l10n/app_strings.dart';
import '../models/user_model.dart';

class AuthRepository {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  bool _googleSignInInitialized = false;

  Stream<UserModel?> get authStateStream {
    return _auth.userChanges().asyncMap((user) async {
      if (user == null) return null;
      final doc = await _db.collection('users').doc(user.uid).get();
      if (doc.exists) return UserModel.fromFirestore(doc);
      // User is authenticated but Firestore doc not yet written.
      // This happens during the brief window between Firebase Auth completing
      // (which fires userChanges()) and the caller writing the user doc.
      // Return a minimal UserModel so the router doesn't redirect back to /login.
      return UserModel(
        uid: user.uid,
        name: user.displayName ?? 'ユーザー',
        email: user.email ?? '',
        photoUrl: user.photoURL,
        createdAt: DateTime.now(),
      );
    });
  }

  /// google_sign_in 7.x requires `initialize()` to be called exactly once
  /// before any other method — see the package's MIGRATION.md.
  Future<void> _ensureGoogleSignInInitialized() async {
    if (_googleSignInInitialized) return;
    await _googleSignIn.initialize();
    _googleSignInInitialized = true;
  }

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
    final credential = GoogleAuthProvider.credential(idToken: googleUser.authentication.idToken);
    final result = await _auth.signInWithCredential(credential);
    final user = result.user;
    if (user == null) throw Exception(AppStrings.t('err_user_info_unavailable'));
    final docRef = _db.collection('users').doc(user.uid);
    final doc = await docRef.get();
    if (!doc.exists) {
      final newUser = UserModel(
        uid: user.uid,
        name: user.displayName ?? 'ユーザー',
        email: user.email ?? '',
        photoUrl: user.photoURL,
        createdAt: DateTime.now(),
      );
      await docRef.set(newUser.toFirestore());
      return newUser;
    }
    return UserModel.fromFirestore(doc);
  }

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
      throw Exception(_authErrorMessage(e.code));
    }
  }

  Future<UserModel> signInWithEmail(String email, String password) async {
    try {
      final result = await _auth.signInWithEmailAndPassword(email: email, password: password);
      final user = result.user;
      if (user == null) throw Exception(AppStrings.t('err_user_info_unavailable'));
      final docRef = _db.collection('users').doc(user.uid);
      final doc = await docRef.get();
      if (!doc.exists) {
        final newUser = UserModel(
          uid: user.uid,
          name: user.displayName ?? 'ユーザー',
          email: user.email ?? email,
          createdAt: DateTime.now(),
        );
        await docRef.set(newUser.toFirestore());
        return newUser;
      }
      return UserModel.fromFirestore(doc);
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
}
