import 'package:flutter/widgets.dart';

/// Non-web stub — never actually called (gated by `kIsWeb` at the call
/// site), but this file must exist and compile on Android/iOS since
/// `google_signin_button.dart` conditionally exports either this or the
/// real web implementation.
Widget renderGoogleSignInButton() {
  throw StateError('renderGoogleSignInButton() is web-only');
}
