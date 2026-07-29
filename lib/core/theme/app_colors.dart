import 'package:flutter/material.dart';

/// EduPlanner AI — Dark Neon design tokens.
/// Source of truth: flutter_handoff/design_reference (EduPlanner_AI_prototype.html).
abstract class AppColors {
  // Background layers
  static const bgDeep = Color(0xFF050508);
  static const background = Color(0xFF08060F);
  static const surface = Color(0xFF12101C);
  static const surfaceVar = Color(0x0AFFFFFF); // 4% white — glass card fill
  static const bgInput = Color(0xFF16112A);
  static const bgLayer = Color(0xFF1A1828);

  // Primary — purple/violet neon
  static const primary = Color(0xFF7C3AED);
  static const primaryMid = Color(0xFFA855F7);
  static const primaryLight = Color(0xFFC084FC);
  static const primaryDark = Color(0xFF4C1D95);

  // Accents
  static const cyan = Color(0xFF22D3EE);
  static const cyanDeep = Color(0xFF06B6D4);
  static const amber = Color(0xFFFBBF24);
  static const amberDeep = Color(0xFFF59E0B);
  static const pink = Color(0xFFF472B6);
  static const blue = Color(0xFF60A5FA);

  // Status
  static const success = Color(0xFF34D399);
  static const successLight = Color(0x2634D399);
  static const warning = Color(0xFFFBBF24);
  static const warningLight = Color(0x1FFBBF24);
  static const danger = Color(0xFFF87171);
  static const dangerLight = Color(0x26F87171);

  // Text
  static const textPrimary = Color(0xFFF0E6FF);
  static const textSecondary = Color(0x80C8AAFF); // 50% purple-tinted white
  static const textMuted = Color(0x40C8AAFF); // 25%

  // Borders / dividers
  static const border = Color(0x12FFFFFF);
  static const borderLight = Color(0x0CFFFFFF);
  static const borderPrimary = Color(0x4DA855F7);

  // Subject trio (fill / text / dot) — translucent for dark cards
  static const progFill = Color(0x26A855F7);
  static const progText = Color(0xFFC084FC);
  static const progDot = Color(0xFFA855F7);
  static const mathFill = Color(0x1FFBBF24);
  static const mathText = Color(0xFFFBBF24);
  static const mathDot = Color(0xFFFBBF24);
  static const engFill = Color(0x1FF472B6);
  static const engText = Color(0xFFF472B6);
  static const engDot = Color(0xFFF472B6);
  static const physFill = Color(0x1F60A5FA);
  static const physText = Color(0xFF60A5FA);
  static const physDot = Color(0xFF60A5FA);
  static const chemFill = Color(0x1F34D399);
  static const chemText = Color(0xFF34D399);
  static const chemDot = Color(0xFF34D399);
  static const histFill = Color(0x1FF87171);
  static const histText = Color(0xFFF87171);
  static const histDot = Color(0xFFF87171);

  // Gradients
  static const gradientPrimary = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF7C3AED), Color(0xFFA855F7), Color(0xFFC084FC)],
  );
  static const gradientCyan = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [Color(0xFF06B6D4), Color(0xFF22D3EE), Color(0xFF67E8F9)],
  );
  static const gradientAmber = LinearGradient(colors: [Color(0xFFF59E0B), Color(0xFFFBBF24)]);
  static const gradientAvatar = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFF59E0B), Color(0xFFEC4899), Color(0xFFA855F7)],
  );
  static const gradientDark = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0D0521), Color(0xFF1A0A38), Color(0xFF0D0521)],
  );
  static const gradientUserBubble = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF7C3AED), Color(0xFFA855F7)],
  );

  // Subject accent colors (schedule cards)
  static const subjectProgramming = Color(0xFFA855F7);
  static const subjectMath = Color(0xFFFBBF24);
  static const subjectEnglish = Color(0xFFF472B6);
  static const subjectPhysics = Color(0xFF60A5FA);
  static const subjectHistory = Color(0xFFF87171);
  static const subjectPE = Color(0xFF34D399);
}
