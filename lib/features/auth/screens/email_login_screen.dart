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
import '../../../shared/widgets/language_picker_button.dart';
import '../providers/auth_provider.dart';

class EmailLoginScreen extends ConsumerStatefulWidget {
  const EmailLoginScreen({super.key});

  @override
  ConsumerState<EmailLoginScreen> createState() => _EmailLoginScreenState();
}

class _EmailLoginScreenState extends ConsumerState<EmailLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _sendingReset = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    await ref.read(authNotifierProvider.notifier).signInWithEmail(
          _emailController.text.trim(),
          _passwordController.text,
        );
    final state = ref.read(authNotifierProvider);
    if (state.hasError && mounted) {
      _showToast(AppStrings.t('login_error'), state.error.toString().replaceAll('Exception: ', ''), isError: true);
    }
  }

  Future<void> _forgotPassword() async {
    final controller = TextEditingController(text: _emailController.text.trim());
    final email = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgLayer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: AppColors.border)),
        title: Text(AppStrings.t('login_reset_pass_title'), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary, fontFamily: 'Plus Jakarta Sans', fontFamilyFallback: const ['NotoSansJP'])),
        content: AppInputField(controller: controller, hintText: AppStrings.t('login_email_hint')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(AppStrings.t('common_cancel'))),
          TextButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: Text(AppStrings.t('common_send'))),
        ],
      ),
    );
    if (email == null || email.isEmpty || !mounted) return;
    setState(() => _sendingReset = true);
    try {
      await ref.read(authRepositoryProvider).sendPasswordResetEmail(email);
      if (mounted) _showToast(AppStrings.t('login_reset_sent'), AppStrings.t('login_reset_sent_msg'));
    } catch (e) {
      if (mounted) _showToast(AppStrings.t('login_send_err'), e.toString().replaceAll('Exception: ', ''), isError: true);
    } finally {
      if (mounted) setState(() => _sendingReset = false);
    }
  }

  void _showToast(String title, String message, {bool isError = false}) {
    toastification.show(
      context: context,
      type: isError ? ToastificationType.error : ToastificationType.success,
      style: ToastificationStyle.flat,
      title: Text(title),
      description: Text(message),
      autoCloseDuration: const Duration(seconds: 3),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loading = ref.watch(authNotifierProvider).isLoading;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Text(AppStrings.t('login_title'), style: const TextStyle(fontFamily: 'Plus Jakarta Sans', fontFamilyFallback: ['NotoSansJP'])),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: LanguagePickerButton(color: AppColors.textPrimary),
          ),
        ],
      ),
      body: SafeArea(
        child: ResponsiveBody(
          maxWidth: 480,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    AppStrings.t('login_welcome_back'),
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.textPrimary, fontFamily: 'Plus Jakarta Sans', fontFamilyFallback: const ['NotoSansJP']),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    AppStrings.t('login_email_pass_prompt'),
                    style: TextStyle(fontSize: 13, color: AppColors.textSecondary, fontFamily: 'Plus Jakarta Sans', fontFamilyFallback: const ['NotoSansJP']),
                  ),
                  const SizedBox(height: 28),
                  AppInputField(
                    controller: _emailController,
                    hintText: AppStrings.t('login_email_hint'),
                    textInputAction: TextInputAction.next,
                    validator: Validators.email,
                  ),
                  const SizedBox(height: 14),
                  AppInputField(
                    controller: _passwordController,
                    hintText: AppStrings.t('login_pass_hint'),
                    obscureText: _obscurePassword,
                    textInputAction: TextInputAction.done,
                    validator: Validators.required,
                    suffix: IconButton(
                      icon: Icon(_obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: AppColors.textMuted),
                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _sendingReset ? null : _forgotPassword,
                      child: Text(AppStrings.t('login_forgot_pass')),
                    ),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: loading ? null : _submit,
                    child: loading
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                        : Text(AppStrings.t('login_title')),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: TextButton(
                      onPressed: () => context.pushReplacement('/login/signup'),
                      child: Text(AppStrings.t('login_no_account')),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
