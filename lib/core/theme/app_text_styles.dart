import 'package:flutter/material.dart';
import 'app_colors.dart';

abstract class AppTextStyles {
  static const String _font = 'Plus Jakarta Sans';
  static const String _fontGrotesk = 'Space Grotesk';
  static const List<String> _fallback = ['NotoSansJP'];

  static TextStyle get headLG => const TextStyle(
        fontFamily: _font,
        fontFamilyFallback: _fallback,
        fontSize: 22,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.4,
      ).copyWith(color: AppColors.textOnHero);

  static TextStyle get h2 => const TextStyle(
        fontFamily: _font,
        fontFamilyFallback: _fallback,
        fontSize: 18,
        fontWeight: FontWeight.w800,
      ).copyWith(color: AppColors.textPrimary);

  static TextStyle get headMD => const TextStyle(
        fontFamily: _font,
        fontFamilyFallback: _fallback,
        fontSize: 16,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.3,
      ).copyWith(color: AppColors.textPrimary);

  static TextStyle get sectionTitle => const TextStyle(
        fontFamily: _font,
        fontFamilyFallback: _fallback,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.5,
      ).copyWith(color: AppColors.textSecondary);

  static TextStyle get body => const TextStyle(
        fontFamily: _font,
        fontFamilyFallback: _fallback,
        fontSize: 13,
        fontWeight: FontWeight.w500,
        height: 1.55,
      ).copyWith(color: AppColors.textPrimary);

  static TextStyle get label => const TextStyle(
        fontFamily: _font,
        fontFamilyFallback: _fallback,
        fontSize: 12,
        fontWeight: FontWeight.w500,
      ).copyWith(color: AppColors.textSecondary);

  static const badge = TextStyle(
      fontFamily: _font,
      fontFamilyFallback: _fallback,
      fontSize: 10,
      fontWeight: FontWeight.w700);

  static TextStyle get overline => const TextStyle(
        fontFamily: _font,
        fontFamilyFallback: _fallback,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
      ).copyWith(color: AppColors.textMuted);

  static TextStyle get statNumber => const TextStyle(
        fontFamily: _fontGrotesk,
        fontFamilyFallback: _fallback,
        fontSize: 24,
        fontWeight: FontWeight.w800,
      );
}
