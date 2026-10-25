import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:toastification/toastification.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/responsive.dart';
import '../../../core/utils/validators.dart';
import '../../../shared/widgets/app_input_field.dart';

/// Completes a Firebase password reset without deep links: the user pastes the
/// reset link from their email (or just its `oobCode`) and sets the new
/// password in the app. This avoids Dynamic Links (discontinued) and
/// App Links / Universal Links (need domain ownership and native config), at
/// the cost of a copy-paste step.
class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  ConsumerState<ResetPasswordScreen> createState() =>
      _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _codeFormKey = GlobalKey<FormState>();
  final _passFormKey = GlobalKey<FormState>();
  final _codeController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _loading = false;
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  // Set once the code is verified; step 2 (new password) starts then.
  String? _verifiedCode;
  String? _verifiedEmail;

  @override
  void dispose() {
    _codeController.dispose();
    _newPasswordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  /// Extracts `oobCode` from a pasted reset link; a bare code is returned as-is.
  String _extractCode(String input) {
    final trimmed = input.trim();
    final uri = Uri.tryParse(trimmed);
    if (uri != null && uri.queryParameters.containsKey('oobCode')) {
      return uri.queryParameters['oobCode']!;
    }
    return trimmed;
  }

  Future<void> _verifyCode() async {
    if (!(_codeFormKey.currentState?.validate() ?? false)) return;
    final code = _extractCode(_codeController.text);
    setState(() => _loading = true);
    try {
      final email =
          await ref.read(authRepositoryProvider).verifyPasswordResetCode(code);
      if (!mounted) return;
      setState(() {
        _verifiedCode = code;
        _verifiedEmail = email;
      });
    } catch (e) {
      if (mounted) _showErrorToast(e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submitNewPassword() async {
    if (!(_passFormKey.currentState?.validate() ?? false)) return;
    final code = _verifiedCode;
    if (code == null) return;
    setState(() => _loading = true);
    try {
      await ref
          .read(authRepositoryProvider)
          .confirmPasswordReset(code, _newPasswordController.text);
      if (!mounted) return;
      toastification.show(
        context: context,
        type: ToastificationType.success,
        style: ToastificationStyle.flat,
        title: Text(AppStrings.t('reset_code_success')),
        description: Text(AppStrings.t('reset_code_success_msg')),
        autoCloseDuration: const Duration(seconds: 3),
      );
      context.pushReplacement('/login/email');
    } catch (e) {
      if (mounted) _showErrorToast(e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showErrorToast(String message) {
    toastification.show(
      context: context,
      type: ToastificationType.error,
      style: ToastificationStyle.flat,
      title: Text(AppStrings.t('login_error')),
      description: Text(message),
      autoCloseDuration: const Duration(seconds: 3),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Text(AppStrings.t('reset_code_title'),
            style: const TextStyle(
                fontFamily: 'Plus Jakarta Sans',
                fontFamilyFallback: ['NotoSansJP'])),
      ),
      body: SafeArea(
        child: ResponsiveBody(
          maxWidth: 480,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
            child:
                _verifiedCode == null ? _buildCodeStep() : _buildPasswordStep(),
          ),
        ),
      ),
    );
  }

  Widget _buildCodeStep() {
    return Form(
      key: _codeFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            AppStrings.t('reset_code_intro'),
            style: TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                fontFamily: 'Plus Jakarta Sans',
                fontFamilyFallback: const ['NotoSansJP']),
          ),
          const SizedBox(height: 20),
          AppInputField(
            controller: _codeController,
            hintText: AppStrings.t('reset_code_hint'),
            validator: Validators.required,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _verifyCode(),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _loading ? null : _verifyCode,
            child: _loading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5, color: AppColors.onPrimary))
                : Text(AppStrings.t('reset_code_verify_btn')),
          ),
        ],
      ),
    );
  }

  Widget _buildPasswordStep() {
    return Form(
      key: _passFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            AppStrings.t(
                'reset_code_for_email', {'email': _verifiedEmail ?? ''}),
            style: TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                fontFamily: 'Plus Jakarta Sans',
                fontFamilyFallback: const ['NotoSansJP']),
          ),
          const SizedBox(height: 20),
          AppInputField(
            controller: _newPasswordController,
            hintText: AppStrings.t('reset_code_new_pass_hint'),
            obscureText: _obscureNew,
            textInputAction: TextInputAction.next,
            validator: Validators.minLength(6),
            suffix: IconButton(
              icon: Icon(
                  _obscureNew
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  color: AppColors.textMuted),
              onPressed: () => setState(() => _obscureNew = !_obscureNew),
            ),
          ),
          const SizedBox(height: 14),
          AppInputField(
            controller: _confirmController,
            hintText: AppStrings.t('reset_code_confirm_hint'),
            obscureText: _obscureConfirm,
            textInputAction: TextInputAction.done,
            validator: (v) => v != _newPasswordController.text
                ? AppStrings.t('val_pass_mismatch')
                : null,
            suffix: IconButton(
              icon: Icon(
                  _obscureConfirm
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  color: AppColors.textMuted),
              onPressed: () =>
                  setState(() => _obscureConfirm = !_obscureConfirm),
            ),
            onSubmitted: (_) => _submitNewPassword(),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _loading ? null : _submitNewPassword,
            child: _loading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5, color: AppColors.onPrimary))
                : Text(AppStrings.t('reset_code_submit_btn')),
          ),
        ],
      ),
    );
  }
}
