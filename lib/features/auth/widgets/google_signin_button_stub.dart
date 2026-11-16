import 'package:flutter/widgets.dart';

/// Non-web stub — never actually called (gated by `kIsWeb` at the call
/// site), but this file must exist and compile on Android/iOS since
/// `google_signin_button.dart` conditionally exports either this or the
/// real web implementation.
///
/// UZ: Veb bo'lmagan platformalar uchun stub — hech qachon amalda chaqirilmaydi (chaqiruv
/// joyida `kIsWeb` bilan cheklangan), ammo bu fayl Android/iOS da mavjud bo'lishi va kompilyatsiya
/// qilinishi kerak, chunki `google_signin_button.dart` shartli ravishda yoki buni yoki haqiqiy veb
/// implementatsiyasini eksport qiladi.
Widget renderGoogleSignInButton() {
  throw StateError('renderGoogleSignInButton() is web-only');
}
