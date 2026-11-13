import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toastification/toastification.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../auth/providers/auth_provider.dart';

/// Shown on Home while an email/password account is unverified. School data
/// (timetable sync, notices, 課題配布) is granted on a verified email only,
/// so without this card such a student has no way to get in.
class VerifyEmailCard extends ConsumerStatefulWidget {
  const VerifyEmailCard({super.key});

  @override
  ConsumerState<VerifyEmailCard> createState() => _VerifyEmailCardState();
}

class _VerifyEmailCardState extends ConsumerState<VerifyEmailCard> {
  bool _busy = false;

  void _toast(String key, ToastificationType type) {
    if (!mounted) return;
    toastification.show(
      context: context,
      type: type,
      style: ToastificationStyle.flat,
      title: Text(AppStrings.t(key)),
      autoCloseDuration: const Duration(seconds: 3),
    );
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (_) {
      _toast('verify_email_failed', ToastificationType.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() => _run(() async {
        await ref.read(authRepositoryProvider).sendEmailVerification();
        _toast('verify_email_sent', ToastificationType.success);
      });

  Future<void> _check() => _run(() async {
        final verified = await ref.read(authRepositoryProvider).refreshEmailVerified();
        if (!verified) return _toast('verify_email_not_yet', ToastificationType.info);
        // authStateStream memoizes per uid, so restart it to let the school
        // providers see the verified email.
        ref.invalidate(authStateProvider);
      });

  @override
  Widget build(BuildContext context) {
    ref.watch(authStateProvider);
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.emailVerified || user.email == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
        decoration: BoxDecoration(
          color: AppColors.cardSurface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.borderPrimary),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.mark_email_unread_outlined, size: 20, color: AppColors.accentText),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(AppStrings.t('verify_email_title'),
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(AppStrings.t('verify_email_body', {'email': user.email!}),
                style: TextStyle(fontSize: 13, height: 1.5, color: AppColors.textSecondary)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 4,
              children: [
                FilledButton(onPressed: _busy ? null : _check, child: Text(AppStrings.t('verify_email_done'))),
                TextButton(onPressed: _busy ? null : _resend, child: Text(AppStrings.t('verify_email_resend'))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
