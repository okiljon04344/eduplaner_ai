import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/app_providers.dart';
import '../models/user_model.dart';

/// Streams the currently signed-in [UserModel], or `null` when signed out.
///
/// The router watches this provider to redirect between authenticated and
/// unauthenticated routes whenever the auth state changes.
///
/// UZ: Hozirda tizimga kirgan [UserModel] ni yoki tizimdan chiqilganda `null` qiymatini oqim tarzida uzatadi.
///
/// Router autentifikatsiya holati o'zgarganda autentifikatsiyalangan va autentifikatsiyalanmagan
/// yo'nalishlar o'rtasida qayta yo'naltirish uchun ushbu provayderni kuzatadi.
final authStateProvider = StreamProvider<UserModel?>(
    (ref) => ref.watch(authRepositoryProvider).authStateStream);

/// Convenience provider that exposes the current user synchronously.
///
/// Returns `null` when the stream hasn't emitted yet or the user is signed out.
/// Suitable for one-off reads inside callbacks — prefer [authStateProvider]
/// when you need reactive rebuilds.
///
/// UZ: Joriy foydalanuvchini sinxron tarzda taqdim etuvchi qulay provayder.
///
/// Oqim hali ma'lumot uzatmagan bo'lsa yoki foydalanuvchi tizimdan chiqqan bo'lsa `null` qaytaradi.
/// Qayta chaqiruvlar (callbacks) ichida bir martalik o'qish uchun mos keladi — reaktiv qayta
/// qurilishlar kerak bo'lganda [authStateProvider] dan foydalanish afzalroq.
final currentUserProvider =
    Provider<UserModel?>((ref) => ref.watch(authStateProvider).valueOrNull);

/// Handles all authentication mutations: Google sign-in, email sign-up/in,
/// and sign-out.
///
/// Each method sets state to [AsyncLoading] then delegates to
/// [AuthRepository] via [AsyncValue.guard], which catches any thrown
/// exceptions and surfaces them as [AsyncError] — the calling screen can
/// display them via `ref.watch(authNotifierProvider).whenOrNull(error: ...)`.
///
/// UZ: Barcha autentifikatsiya o'zgarishlarini boshqaradi: Google orqali kirish, elektron pochta
/// orqali ro'yxatdan o'tish/kirish va tizimdan chiqish.
///
/// Har bir metod holatni [AsyncLoading] ga o'rnatadi, so'ngra [AsyncValue.guard] orqali
/// [AuthRepository] ga topshiradi, bu har qanday tashlangan istisnolarni ushlaydi va ularni
/// [AsyncError] sifatida ko'rsatadi — chaqiruvchi ekran ularni
/// `ref.watch(authNotifierProvider).whenOrNull(error: ...)` orqali ko'rsatishi mumkin.
class AuthNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  /// Signs in with a Google account using `GoogleSignIn.instance.authenticate()`.
  /// Only the `idToken` is sent to Firebase — the full Google profile stays
  /// on-device.
  ///
  /// UZ: `GoogleSignIn.instance.authenticate()` yordamida Google hisobi bilan tizimga kiradi.
  /// Firebase ga faqat `idToken` yuboriladi — to'liq Google profili qurilmada qoladi.
  Future<void> signInWithGoogle() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
        () => ref.read(authRepositoryProvider).signInWithGoogle());
  }

  /// Creates a new Firebase Auth account with [email] / [password] and
  /// immediately writes the [name] into the `users/{uid}` Firestore document.
  ///
  /// UZ: [email] / [password] bilan yangi Firebase Auth hisobini yaratadi va
  /// darhol [name] ni `users/{uid}` Firestore hujjatiga yozadi.
  Future<void> signUpWithEmail(String email, String password, String name) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
        () => ref.read(authRepositoryProvider).signUpWithEmail(email, password, name));
  }

  /// Signs in with an existing [email] / [password] Firebase account.
  ///
  /// UZ: Mavjud [email] / [password] Firebase hisobi bilan tizimga kiradi.
  Future<void> signInWithEmail(String email, String password) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
        () => ref.read(authRepositoryProvider).signInWithEmail(email, password));
  }

  /// Signs out from Firebase Auth and Google Sign-In.
  /// The router automatically redirects to the landing screen once
  /// [authStateProvider] emits `null`.
  ///
  /// UZ: Firebase Auth va Google Sign-In dan tizimdan chiqadi.
  /// [authStateProvider] `null` qiymatini uzatgach, router avtomatik ravishda
  /// kirish (landing) ekraniga yo'naltiradi.
  Future<void> signOut() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
        () => ref.read(authRepositoryProvider).signOut());
  }

  /// Saves the mandatory school-profile fields, then invalidates
  /// [authStateProvider] so it re-subscribes and re-reads the freshly
  /// written Firestore doc — without this, [currentUserProvider] would keep
  /// returning the pre-save (incomplete) model until the next unrelated
  /// auth-state emission, and the router's profile-setup redirect wouldn't
  /// clear until then.
  ///
  /// UZ: Majburiy maktab profili maydonlarini saqlaydi, so'ngra [authStateProvider] ni bekor
  /// qiladi (invalidate), natijada u qayta obuna bo'ladi va yangi yozilgan Firestore hujjatini
  /// qayta o'qiydi — busiz, [currentUserProvider] keyingi bog'liq bo'lmagan auth holati uzatilishigacha
  /// saqlashdan oldingi (to'liq bo'lmagan) modelni qaytarishda davom etadi va routerning
  /// profilni sozlash yo'naltirish holati o'sha paytgacha tozalanmaydi.
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
            schoolDomain: schoolDomain,
          );
      ref.invalidate(authStateProvider);
    });
  }
}

/// Global provider for [AuthNotifier].
///
/// Call `ref.read(authNotifierProvider.notifier).signInWithGoogle()` etc.
/// from button callbacks.  Watch the state for loading/error UI:
/// ```dart
/// ref.watch(authNotifierProvider).whenOrNull(error: (e, _) => showError(e));
/// ```
///
/// UZ: [AuthNotifier] uchun global provayder.
///
/// Tugma qayta chaqiruvlaridan (callbacks) `ref.read(authNotifierProvider.notifier).signInWithGoogle()`
/// va boshqalarni chaqiring. Yuklash/xatolik UI uchun holatni kuzating:
/// ```dart
/// ref.watch(authNotifierProvider).whenOrNull(error: (e, _) => showError(e));
/// ```
final authNotifierProvider =
    AsyncNotifierProvider<AuthNotifier, void>(AuthNotifier.new);
