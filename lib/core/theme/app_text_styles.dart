import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Text styles for the dark-neon design system.
/// Primary typeface: Plus Jakarta Sans (registered globally via GoogleFonts in
/// [AppTheme]). Japanese glyphs fall back to the bundled NotoSansJP font.
abstract class AppTextStyles {
  static const String _font = 'Plus Jakarta Sans';
  static const String _fontGrotesk = 'Space Grotesk';
  static const List<String> _fallback = ['NotoSansJP'];

  static const h1 = TextStyle(
    fontFamily: _font, fontFamilyFallback: _fallback,
    fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.5, color: AppColors.textPrimary,
  );
  static const headXL = TextStyle(
    fontFamily: _font, fontFamilyFallback: _fallback,
    fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.5, color: Colors.white,
  );
  static const headLG = TextStyle(
    fontFamily: _font, fontFamilyFallback: _fallback,
    fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.4, color: Colors.white,
  );
  static const h2 = TextStyle(
    fontFamily: _font, fontFamilyFallback: _fallback,
    fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textPrimary,
  );
  static const headMD = TextStyle(
    fontFamily: _font, fontFamilyFallback: _fallback,
    fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: -0.3, color: AppColors.textPrimary,
  );
  static const sectionTitle = TextStyle(
    fontFamily: _font, fontFamilyFallback: _fallback,
    fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: AppColors.textSecondary,
  );
  static const cardTitle = TextStyle(
    fontFamily: _font, fontFamilyFallback: _fallback,
    fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: -0.2, color: AppColors.textPrimary,
  );
  static const body1 = TextStyle(
    fontFamily: _font, fontFamilyFallback: _fallback,
    fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary,
  );
  static const body = TextStyle(
    fontFamily: _font, fontFamilyFallback: _fallback,
    fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textPrimary, height: 1.55,
  );
  static const body2 = TextStyle(
    fontFamily: _font, fontFamilyFallback: _fallback,
    fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textSecondary,
  );
  static const label = TextStyle(
    fontFamily: _font, fontFamilyFallback: _fallback,
    fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textSecondary,
  );
  static const caption = TextStyle(
    fontFamily: _font, fontFamilyFallback: _fallback,
    fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textSecondary,
  );
  static const micro = TextStyle(fontFamily: _font, fontFamilyFallback: _fallback, fontSize: 10, fontWeight: FontWeight.w700);
  static const navLabel = TextStyle(fontFamily: _font, fontFamilyFallback: _fallback, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.3);
  static const badge = TextStyle(fontFamily: _font, fontFamilyFallback: _fallback, fontSize: 10, fontWeight: FontWeight.w700);
  static const overline = TextStyle(
    fontFamily: _font, fontFamilyFallback: _fallback,
    fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: AppColors.textMuted,
  );

  /// Hero stat numbers (streak, done count, GPA) — Space Grotesk.
  static const statNumber = TextStyle(
    fontFamily: _fontGrotesk, fontFamilyFallback: _fallback,
    fontSize: 24, fontWeight: FontWeight.w800,
  );
}
