import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import 'google_signin_button.dart';

/// Google sign-in entry point, shared by the mobile and desktop layouts.
///
/// Web has no `authenticate()` support — `GoogleSignIn` on web requires a
/// button rendered by Google's own SDK (see `google_signin_button.dart`),
/// which handles the click internally and completes sign-in via
/// `AuthRepository`'s `authenticationEvents` listener, not [onTap]. Other
/// platforms keep the app's own styled button wired to [onTap].
class GoogleSignInArea extends StatelessWidget {
  final bool loading;
  final VoidCallback onTap;
  const GoogleSignInArea({super.key, required this.loading, required this.onTap});

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return SizedBox(height: 52, child: Center(child: renderGoogleSignInButton()));
    }
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: AppColors.surfaceVar,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'assets/images/google_logo.png',
              width: 20,
              height: 20,
              errorBuilder: (context, error, stackTrace) => Container(
                width: 20,
                height: 20,
                decoration: const BoxDecoration(color: Color(0xFF4285F4), shape: BoxShape.circle),
                alignment: Alignment.center,
                child: const Text(
                  'G',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              AppStrings.t('login_google'),
              style: TextStyle(
                fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary,
                fontFamily: 'Plus Jakarta Sans', fontFamilyFallback: const ['NotoSansJP'],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
