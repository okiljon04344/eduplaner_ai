import 'package:flutter/widgets.dart';
import 'package:google_sign_in_web/web_only.dart' as web;

/// Google's own Sign-In button from the Identity Services JS SDK. Required on
/// web: `GoogleSignIn.authenticate()` always throws `UnsupportedError` there,
/// so user-initiated sign-in must use an SDK-rendered button.
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
