import 'package:flutter/widgets.dart';
import 'package:google_sign_in_web/web_only.dart' as web;

/// Renders Google's own Sign-In button widget via the Google Identity
/// Services JS SDK. Required on web — `GoogleSignIn.authenticate()` always
/// throws `UnsupportedError` there (`supportsAuthenticate()` is hard-coded
/// `false` in `google_sign_in_web`); a user-initiated web sign-in must use
/// a button rendered by the SDK itself instead of app-provided UI.
///
/// UZ: Google Identity Services JS SDK orqali Google'ning shaxsiy Sign-In tugmasi vidjetini
/// render qiladi. Vebda talab qilinadi — u yerda `GoogleSignIn.authenticate()` doimo
/// `UnsupportedError` tashlaydi (`google_sign_in_web` da `supportsAuthenticate()` qat'iy `false`
/// qilib qo'yilgan); foydalanuvchi tomonidan boshlangan veb kirish ilova taqdim etgan UI o'rniga
/// SDK tomonidan render qilingan tugmadan foydalanishi shart.
Widget renderGoogleSignInButton() {
  return web.renderButton(
    configuration: web.GSIButtonConfiguration(
      theme: web.GSIButtonTheme.filledBlack,
      size: web.GSIButtonSize.large,
      shape: web.GSIButtonShape.pill,
      text: web.GSIButtonText.signinWith,
      minimumWidth: 300,
    ),
  );
}
