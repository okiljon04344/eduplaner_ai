import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/services/notification_service.dart';
import '../models/user_model.dart';

/// Authentication repository managing Firebase Auth, Google Sign-In, session state streaming,
/// and user profile synchronization in Firestore.
///
/// UZ: Firebase Auth, Google Sign-In, sessiya holati oqimi va Firestore'da foydalanuvchi
/// profilini sinxronlashni boshqaradigan autentifikatsiya repozitoriysi.
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
  ///
  /// UZ: *Ayni bir allaqachon aniqlangan* uid uchun `userChanges()` ning qayta chiqarilishi (masalan,
  /// butun sessiya davomida ushbu oqimni vaqti-vaqti bilan ishga tushiradigan ID token yangilanishi)
  /// Firestore hujjatini qayta o'qimasligi uchun memoizatsiya qilingan. Faqat uid o'zgarganda yoki
  /// oldingi olish hali hujjatni topmaganida qayta o'qiydi (ro'yxatdan o'tishdan so'ng chaqiruvchi
  /// yozishidan oldingi qisqa vaqt oralig'i) — bu holda router yozilishi bilanoq haqiqiy nomni
  /// olishi uchun qayta urinishda davom etamiz.
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
        // UZ: Muvaffaqiyatsiz o'qish hech qachon bu oqimni tugatmasligi kerak: router
        // qayta ishga tushguncha foydalanuvchini tizimdan chiqqan deb hisoblab qo'yadi.
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
          // User is authenticated but Firestore doc not yet written.
          // This happens during the brief window between Firebase Auth completing
          // (which fires userChanges()) and the caller writing the user doc.
          // Return a minimal UserModel so the router doesn't redirect back to /login.
          // UZ: Foydalanuvchi autentifikatsiyadan o'tgan, ammo Firestore hujjati hali yozilmagan.
          // Bu Firebase Auth tugashi (u userChanges() ni chaqiradi) va chaqiruvchi foydalanuvchi
          // hujjatini yozishi oralig'idagi qisqa vaqtda yuz beradi. Router /login ga qayta
          // yo'naltirmasligi uchun minimal UserModel qaytaring.
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

  /// Re-reads `users/{uid}` up to 3 more times, 2s apart, after the first
  /// read failed. Returns `null` if every attempt fails so the caller can
  /// fall back to the minimal [UserModel].
  ///
  /// UZ: Birinchi o'qish muvaffaqiyatsiz bo'lgach, 2 soniya oralig'ida `users/{uid}` ni yana
  /// 3 martagacha qayta o'qiydi. Chaqiruvchi minimal [UserModel] ga qaytishi uchun, har bir
  /// urinish muvaffaqiyatsiz bo'lsa `null` qaytaradi.
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
  ///
  /// UZ: google_sign_in 7.x har qanday boshqa metoddan oldin `initialize()` aynan bir marta
  /// chaqirilishini talab qiladi — paketning MIGRATION.md fayliga qarang.
  ///
  /// Vebda, agar `web/index.html` da `<meta name="google-signin-client_id" ...>` tegi bo'lmasa,
  /// bu xato tashlaydi (har bir platforma uchun majburiy sozlash bosqichi — o'sha faylga qarang).
  /// Yo'qolgan/noto'g'ri sozlangan client id ushlanmagan assert o'rniga oddiy tarjima qilingan xato
  /// sifatida ko'rinishi uchun o'rab olingan.
  ///
  /// Vebda bu shuningdek SDK chizgan tugma tomonidan chiqarilgan kirish hodisalarini tinglashni
  /// boshlaydi (`renderGoogleSignInButton()` ga qarang) — vebda `authenticate()` qo'llab-quvvatlovi
  /// yo'q (`google_sign_in_web` ichida `supportsAuthenticate()` kodda false qilingan), shuning uchun
  /// foydalanuvchi boshlagan kirish to'g'ridan-to'g'ri metod chaqiruvi/qaytishi o'rniga ushbu hodisa
  /// oqimi orqali yakunlanadi. Firebase kirishi muvaffaqiyatli bo'lgach, `authStateStream` uni xuddi
  /// boshqa kirishlar kabi oladi va router qayta yo'naltiradi — chaqiruvchi kutishi kerak bo'lgan boshqa
  /// narsa yo'q.
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
  ///
  /// UZ: Vebda Google Sign-In ishga tushirishni erta boshlaydi, shunda SDK tomonidan chizilgan
  /// tugma (ishga tushirish tugaguniga qadar "Getting ready" deb ko'rsatadi) faqat bosilganda
  /// boshlanmasdan, kirish ekrani paydo bo'lishi bilanoq imkon qadar tezroq interaktiv bo'ladi.
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
  ///
  /// UZ: [GoogleSignInAccount] ning id tokenini Firebase credential'iga almashtiradi va
  /// `users/{uid}` Firestore hujjati mavjudligini ta'minlaydi — mobil `authenticate()` oqimi
  /// va veb kirish hodisasi tinglovchisi tomonidan birgalikda ishlatiladi.
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
  ///
  /// UZ: [user] uchun `users/{uid}` hujjatini o'qiydi, agar u hali mavjud bo'lmasa, uni
  /// mantiqiy standart qiymatlar bilan yaratadi. [fallbackEmail] faqat [user] ning o'zida
  /// elektron pochta bo'lmaganida ishlatiladi (masalan, ba'zi email/password oqimlari).
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
  ///
  /// UZ: Mutlaqo yangi hisobni ro'yxatdan o'tkazadi yoki — agar [email] allaqachon ro'yxatdan
  /// o'tgan bo'lsa — foydalanuvchini kiritgan [password] bilan bildirmasdan tizimga kiritadi.
  ///
  /// Bu ro'yxatdan o'tish formasini "davom etish" harakatiga aylantiradi: login o'rniga adashib
  /// ro'yxatdan o'tish sahifasiga kirib qolgan qaytgan foydalanuvchi shunchaki "email allaqachon
  /// band" xatosi bilan to'xtatilmaydi. Agar ularning paroli mavjud hisobga mos kelsa, ular
  /// shunchaki tizimga kiritiladi (Firebase'ning `userChanges()` oqimi ularni odatiy login kabi
  /// `/home` ga yo'naltiradi). Agar mos kelmasa, xabar aniq harakatga yo'naltirilgan bo'lishi
  /// uchun xom FirebaseAuth xatosi o'rniga [err_account_exists] tashlanadi ("ushbu hisob
  /// allaqachon mavjud — to'g'ri paroldan yoki kirish ekranidan foydalaning").
  Future<UserModel> signUpWithEmail(String email, String password, String name) async {
    try {
      final result = await _auth.createUserWithEmailAndPassword(email: email, password: password);
      final user = result.user;
      if (user == null) throw Exception(AppStrings.t('err_user_info_unavailable'));
      await user.updateDisplayName(name);
      final newUser = UserModel(uid: user.uid, name: name, email: email, createdAt: DateTime.now());
      await _db.collection('users').doc(user.uid).set(newUser.toFirestore());
      // Best effort: Home shows VerifyEmailCard with a resend button.
      // UZ: Imkon qadar urinish: Home qayta yuborish tugmasi bilan VerifyEmailCard ni ko'rsatadi.
      await user.sendEmailVerification().catchError((_) {});
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

  Future<void> sendEmailVerification() async => _auth.currentUser?.sendEmailVerification();

  /// Reloads the user and, once verified, refreshes the ID token so Firestore
  /// rules (`email_verified`) see it without a re-login.
  ///
  /// UZ: Foydalanuvchini qayta yuklaydi va tasdiqlangach, ID tokenni yangilaydi, shunda
  /// Firestore qoidalari (`email_verified`) uni qayta kirmasdan ko'radi.
  Future<bool> refreshEmailVerified() async {
    await _auth.currentUser?.reload();
    final user = _auth.currentUser;
    if (user == null || !user.emailVerified) return false;
    await user.getIdToken(true);
    return true;
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
  ///
  /// UZ: Parolni tiklash `oobCode` kodini tekshiradi (Firebase [sendPasswordResetEmail] da
  /// yuboradigan havolaga biriktirilgan kod) va u tegishli bo'lgan elektron pochta manzilini
  /// qaytaradi, shunda tasdiqlash ekrani foydalanuvchi yangi parolni kiritishidan oldin
  /// "{email} uchun parol tiklanmoqda" xabarini ko'rsatishi mumkin.
  Future<String> verifyPasswordResetCode(String code) async {
    try {
      final email = await _auth.verifyPasswordResetCode(code);
      return email;
    } on FirebaseAuthException catch (_) {
      throw Exception(AppStrings.t('reset_code_invalid'));
    }
  }

  /// Applies [newPassword] using a previously-verified `oobCode`.
  ///
  /// UZ: Avval tasdiqlangan `oobCode` yordamida [newPassword] ni qo'llaydi.
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

  /// Signs out after best-effort cleanup of device-local, per-user state
  /// (push token, pending reminders, cached AI results) so the next account
  /// on this device doesn't inherit it. Cleanup failures never block sign-out.
  ///
  /// UZ: Qurilmadagi mahalliy, foydalanuvchiga tegishli holatni (push token, kutilayotgan
  /// eslatmalar, keshlashtirilgan AI natijalari) tozalashga harakat qilib, tizimdan chiqadi,
  /// shunda ushbu qurilmadagi keyingi hisob uni meros qilib olmaydi. Tozalashdagi xatoliklar
  /// hech qachon chiqishni to'xtatmaydi.
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
        // UZ: `streak_*` ataylab saqlanadi: streak har bir hisob uchun emas, balki har bir qurilma uchun.
        if (key.startsWith('study_tip_') || key.startsWith('weak_area_')) {
          await prefs.remove(key);
        }
      }
    } catch (e) {
      debugPrint('Clear cached data error: $e');
    }
    await Future.wait([_auth.signOut(), _googleSignIn.signOut()]);
  }

  String? get currentUid => _auth.currentUser?.uid;

  /// Merges the mandatory school-profile fields into the current user's
  /// Firestore doc. [grade]/[program]/[faculty]/[department]/[course] are optional —
  /// blank strings are written as `null` so they render as "not set" rather
  /// than an empty label.
  ///
  /// UZ: Joriy foydalanuvchining Firestore hujjatiga majburiy maktab profili maydonlarini
  /// birlashtiradi. [grade]/[program]/[faculty]/[department]/[course] ixtiyoriy — bo'sh satrlar
  /// `null` sifatida yoziladi, shuning uchun ular bo'sh yorliq emas, "o'rnatilmagan" sifatida chiziladi.
  Future<void> saveSchoolProfile({
    required String schoolType,
    required String schoolName,
    String? grade,
    String? program,
    String? faculty,
    String? department,
    String? course,
    String? schoolDomain,
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
      // Null clears it; the Firestore rule only accepts the verified-email domain.
      // UZ: Null uni tozalaydi; Firestore qoidasi faqat tasdiqlangan elektron pochta domenini qabul qiladi.
      'schoolDomain': schoolDomain,
    }, SetOptions(merge: true));
    // authStateStream memoizes the model per-uid (see field docs above) and
    // only re-reads Firestore when the uid changes — this write wouldn't
    // otherwise surface until the next unrelated userChanges() emission
    // (token refresh, up to ~1h later). Forcing a re-read here is what makes
    // the router's profileComplete redirect fire immediately after saving.
    // UZ: authStateStream modelni har bir uid bo'yicha memoizatsiya qiladi (yuqoridagi maydon
    // hujjatlariga qarang) va Firestore'ni faqat uid o'zgarganda qayta o'qiydi — aks holda bu yozuv
    // keyingi aloqasiz userChanges() emissiyasigacha (~1 soatgacha kechroq) ko'rinmas edi. Bu yerda
    // majburiy qayta o'qish router'ning profileComplete qayta yo'naltirishini saqlashdan so'ng darhol
    // ishga tushiradi.
    _cachedFromDoc = false;
  }
}
