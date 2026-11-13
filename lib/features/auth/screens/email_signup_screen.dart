import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:toastification/toastification.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/responsive.dart';
import '../../../core/utils/validators.dart';
import '../../../shared/widgets/app_input_field.dart';
import '../../../shared/widgets/language_picker_button.dart';
import '../providers/auth_provider.dart';

class EmailSignupScreen extends ConsumerStatefulWidget {
  const EmailSignupScreen({super.key});

  @override
  ConsumerState<EmailSignupScreen> createState() => _EmailSignupScreenState();
}

class _EmailSignupScreenState extends ConsumerState<EmailSignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  bool _agreed = false;

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    await ref.read(authNotifierProvider.notifier).signUpWithEmail(
          _emailController.text.trim(),
          _passwordController.text,
          _nameController.text.trim(),
        );
    final state = ref.read(authNotifierProvider);
    if (state.hasError && mounted) {
      toastification.show(
        context: context,
        type: ToastificationType.error,
        style: ToastificationStyle.flat,
        title: Text(AppStrings.t('login_signup_error')),
        description: Text(state.error.toString().replaceAll('Exception: ', '')),
        autoCloseDuration: const Duration(seconds: 3),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final loading = ref.watch(authNotifierProvider).isLoading;
    final isDesktop = context.isTablet;

    final formContent = Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            AppStrings.t('login_signup_title'),
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.textPrimary, fontFamily: 'Plus Jakarta Sans', fontFamilyFallback: const ['NotoSansJP']),
          ),
          const SizedBox(height: 4),
          Text(
            AppStrings.t('login_signup_subtitle'),
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary, fontFamily: 'Plus Jakarta Sans', fontFamilyFallback: const ['NotoSansJP']),
          ),
          const SizedBox(height: 28),
          AppInputField(
            controller: _nameController,
            hintText: AppStrings.t('login_name_hint'),
            textInputAction: TextInputAction.next,
            validator: Validators.required,
          ),
          const SizedBox(height: 14),
          AppInputField(
            controller: _emailController,
            hintText: AppStrings.t('login_email_hint'),
            textInputAction: TextInputAction.next,
            validator: Validators.email,
          ),
          const SizedBox(height: 14),
          AppInputField(
            controller: _passwordController,
            hintText: AppStrings.t('login_pass_hint_min'),
            obscureText: _obscurePassword,
            textInputAction: TextInputAction.next,
            validator: Validators.minLength(6),
            suffix: IconButton(
              icon: Icon(_obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: AppColors.textMuted),
              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
            ),
          ),
          const SizedBox(height: 14),
          AppInputField(
            controller: _confirmController,
            hintText: AppStrings.t('login_pass_confirm_hint'),
            obscureText: _obscureConfirm,
            textInputAction: TextInputAction.done,
            validator: (v) => v != _passwordController.text ? AppStrings.t('val_pass_mismatch') : null,
            suffix: IconButton(
              icon: Icon(_obscureConfirm ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: AppColors.textMuted),
              onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
            ),
            onChanged: (_) => _formKey.currentState?.validate(),
          ),
          const SizedBox(height: 14),
          CheckboxListTile(
            value: _agreed,
            onChanged: (v) => setState(() => _agreed = v ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(AppStrings.t('signup_consent'),
                style: TextStyle(fontSize: 13, height: 1.4, color: AppColors.textSecondary)),
          ),
          Wrap(
            children: [
              TextButton(
                onPressed: () => launchUrl(Uri.parse('https://okiljon04344.github.io/eduplaner_ai/privacy-policy.html')),
                child: Text(AppStrings.t('set_privacy')),
              ),
              TextButton(
                onPressed: () => launchUrl(Uri.parse('https://okiljon04344.github.io/eduplaner_ai/terms-of-service.html')),
                child: Text(AppStrings.t('set_terms')),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ElevatedButton(
            onPressed: loading || !_agreed ? null : _submit,
            child: loading
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.onPrimary))
                : Text(AppStrings.t('login_signup_btn')),
          ),
          const SizedBox(height: 16),
          Center(
            child: TextButton(
              onPressed: () => context.pushReplacement('/login/email'),
              child: Text(AppStrings.t('login_have_account')),
            ),
          ),
        ],
      ),
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Text(AppStrings.t('login_email_register'), style: const TextStyle(fontFamily: 'Plus Jakarta Sans', fontFamilyFallback: ['NotoSansJP'])),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: LanguagePickerButton(color: AppColors.textPrimary),
          ),
        ],
      ),
      body: SafeArea(
        child: isDesktop
            ? Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: Container(
                      padding: const EdgeInsets.all(32),
                      decoration: BoxDecoration(
                        color: AppColors.cardSurface,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: AppColors.cardStroke),
                        boxShadow: AppColors.cardShadow,
                      ),
                      child: formContent,
                    ),
                  ),
                ),
              )
            : ResponsiveBody(
                maxWidth: 480,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
                  child: formContent,
                ),
              ),
      ),
    );
  }
}
