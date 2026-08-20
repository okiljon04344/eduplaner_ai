import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

class AppInputField extends StatelessWidget {
  final TextEditingController controller;
  final String? hintText;
  final int? maxLines;
  final int? minLines;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final Widget? suffix;
  final Widget? prefix;
  final bool obscureText;
  final TextInputAction? textInputAction;
  final FocusNode? focusNode;
  final bool expands;

  const AppInputField({
    super.key,
    required this.controller,
    this.hintText,
    this.maxLines = 1,
    this.minLines,
    this.validator,
    this.onChanged,
    this.onSubmitted,
    this.suffix,
    this.prefix,
    this.obscureText = false,
    this.textInputAction,
    this.focusNode,
    this.expands = false,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      maxLines: expands ? null : maxLines,
      minLines: expands ? null : minLines,
      expands: expands,
      validator: validator,
      onChanged: onChanged,
      onFieldSubmitted: onSubmitted,
      obscureText: obscureText,
      textInputAction: textInputAction,
      style: TextStyle(
        fontSize: 15,
        color: AppColors.textPrimary,
        fontFamily: 'Plus Jakarta Sans',
        fontFamilyFallback: const ['NotoSansJP'],
      ),
      cursorColor: AppColors.primary,
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: TextStyle(fontSize: 14, fontWeight: FontWeight.w400, color: AppColors.textMuted),
        prefixIcon: prefix,
        suffixIcon: suffix,
        filled: true,
        fillColor: AppColors.bgInput,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppColors.borderPrimary, width: 1.5)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppColors.borderPrimary, width: 1.5)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppColors.primaryMid, width: 2)),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.danger)),
        focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.danger, width: 2)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
    );
  }
}
