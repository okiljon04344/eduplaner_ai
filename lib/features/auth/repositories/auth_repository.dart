import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../models/user_model.dart';

class AuthRepository {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Stream<UserModel?> get authStateStream {
    return _auth.userChanges().asyncMap((user) async {
      if (user == null) return null;
      final doc = await _db.collection('users').doc(user.uid).get();
      if (doc.exists) return UserModel.fromFirestore(doc);
      return null;
    });
  }

  Future<UserModel> signInWithGoogle() async {
    final googleUser = await _googleSignIn.signIn();
    if (googleUser == null) throw Exception('Googleサインインがキャンセルされました');
    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );
    final result = await _auth.signInWithCredential(credential);
    final user = result.user;
    if (user == null) throw Exception('ユーザー情報を取得できませんでした');
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

  Future<void> signOut() async {
    await Future.wait([_auth.signOut(), _googleSignIn.signOut()]);
  }

  String? get currentUid => _auth.currentUser?.uid;
}
