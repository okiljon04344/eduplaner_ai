import 'package:flutter/material.dart';

/// EduPlanner AI design tokens — Dark Neon (HTML prototype) + Light (README handoff).
/// Theme-dependent tokens are mutable statics reassigned by [applyBrightness].
abstract class AppColors {
  // ==================== Theme-dependent ====================
  static Color bgDeep = _darkBgDeep;
  static Color background = _darkBackground;
  static Color surface = _darkSurface;
  static Color surfaceVar = _darkSurfaceVar;
  static Color bgInput = _darkBgInput;
  static Color bgLayer = _darkBgLayer;

  static Color textPrimary = _darkTextPrimary;
  static Color textSecondary = _darkTextSecondary;
  static Color textMuted = _darkTextMuted;
  static Color textOnHero = Colors.white;

  static Color border = _darkBorder;
  static Color borderLight = _darkBorderLight;

  static Color cardBg = _darkCardBg;
  static Color cardBorder = _darkCardBorder;
  static Color dividerSubtle = _darkDividerSubtle;
  static Color glassBg = _darkGlassBg;
  static Color glassBorder = _darkGlassBorder;
  static Color navBg = _darkNavBg;
  static Color navBorder = _darkNavBorder;
  static Color checkboxUnchecked = _darkCheckboxUnchecked;
  static Color iconButtonBg = _darkIconButtonBg;

  static Color progText = _darkProgText;
  static Color progDot = _darkProgDot;
  static Color mathText = _darkMathText;
  static Color mathDot = _darkMathDot;
  static Color engText = _darkEngText;
  static Color engDot = _darkEngDot;
  static Color physText = _darkPhysText;
  static Color physDot = _darkPhysDot;
  static Color chemText = _darkChemText;
  static Color chemDot = _darkChemDot;
  static Color histText = _darkHistText;
  static Color histDot = _darkHistDot;

  static LinearGradient get heroHomeGradient => isDark ? _darkHeroHomeGradient : _lightHeroHomeGradient;
  static LinearGradient get heroScheduleGradient => isDark ? _darkHeroScheduleGradient : _lightHeroScheduleGradient;
  static LinearGradient get heroTasksGradient => isDark ? _darkHeroTasksGradient : _lightHeroTasksGradient;

  static List<BoxShadow> get cardShadow => isDark ? _darkCardShadow : _lightCardShadow;
  static List<BoxShadow> get heroCardShadow => isDark ? _darkHeroCardShadow : _lightHeroCardShadow;

  static Brightness _brightness = Brightness.dark;
  static Brightness get brightness => _brightness;
  static bool get isDark => _brightness == Brightness.dark;

  static void applyBrightness(Brightness value) {
    if (_brightness == value) return;
    _brightness = value;
    final isDarkMode = value == Brightness.dark;
    bgDeep = isDarkMode ? _darkBgDeep : _lightBgDeep;
    background = isDarkMode ? _darkBackground : _lightBackground;
    surface = isDarkMode ? _darkSurface : _lightSurface;
    surfaceVar = isDarkMode ? _darkSurfaceVar : _lightSurfaceVar;
    bgInput = isDarkMode ? _darkBgInput : _lightBgInput;
    bgLayer = isDarkMode ? _darkBgLayer : _lightBgLayer;
    textPrimary = isDarkMode ? _darkTextPrimary : _lightTextPrimary;
    textSecondary = isDarkMode ? _darkTextSecondary : _lightTextSecondary;
    textMuted = isDarkMode ? _darkTextMuted : _lightTextMuted;
    textOnHero = Colors.white;
    border = isDarkMode ? _darkBorder : _lightBorder;
    borderLight = isDarkMode ? _darkBorderLight : _lightBorderLight;
    cardBg = isDarkMode ? _darkCardBg : _lightCardBg;
    cardBorder = isDarkMode ? _darkCardBorder : _lightCardBorder;
    dividerSubtle = isDarkMode ? _darkDividerSubtle : _lightDividerSubtle;
    glassBg = isDarkMode ? _darkGlassBg : _lightGlassBg;
    glassBorder = isDarkMode ? _darkGlassBorder : _lightGlassBorder;
    navBg = isDarkMode ? _darkNavBg : _lightNavBg;
    navBorder = isDarkMode ? _darkNavBorder : _lightNavBorder;
    checkboxUnchecked = isDarkMode ? _darkCheckboxUnchecked : _lightCheckboxUnchecked;
    iconButtonBg = isDarkMode ? _darkIconButtonBg : _lightIconButtonBg;
    progText = isDarkMode ? _darkProgText : _lightProgText;
    progDot = isDarkMode ? _darkProgDot : _lightProgDot;
    mathText = isDarkMode ? _darkMathText : _lightMathText;
    mathDot = isDarkMode ? _darkMathDot : _lightMathDot;
    engText = isDarkMode ? _darkEngText : _lightEngText;
    engDot = isDarkMode ? _darkEngDot : _lightEngDot;
    physText = isDarkMode ? _darkPhysText : _lightPhysText;
    physDot = isDarkMode ? _darkPhysDot : _lightPhysDot;
    chemText = isDarkMode ? _darkChemText : _lightChemText;
    chemDot = isDarkMode ? _darkChemDot : _lightChemDot;
    histText = isDarkMode ? _darkHistText : _lightHistText;
    histDot = isDarkMode ? _darkHistDot : _lightHistDot;
  }

  // ---- dark (HTML prototype) ----
  static const _darkBgDeep = Color(0xFF050508);
  static const _darkBackground = Color(0xFF08060F);
  static const _darkSurface = Color(0xFF12101C);
  static const _darkSurfaceVar = Color(0x0AFFFFFF);
  static const _darkBgInput = Color(0xFF16112A);
  static const _darkBgLayer = Color(0xFF1A1828);
  static const _darkTextPrimary = Color(0xFFF0E6FF);
  static const _darkTextSecondary = Color(0x80C8AAFF);
  static const _darkTextMuted = Color(0x40C8AAFF);
  static const _darkBorder = Color(0x12FFFFFF);
  static const _darkBorderLight = Color(0x0CFFFFFF);
  static const _darkCardBg = Color(0x0AFFFFFF);
  static const _darkCardBorder = Color(0x12FFFFFF);
  static const _darkDividerSubtle = Color(0x0AFFFFFF);
  static const _darkGlassBg = Color(0x21FFFFFF);
  static const _darkGlassBorder = Color(0x26FFFFFF);
  static const _darkNavBg = Color(0xF508060F);
  static const _darkNavBorder = Color(0x0FFFFFFF);
  static const _darkCheckboxUnchecked = Color(0x26FFFFFF);
  static const _darkIconButtonBg = Color(0x14FFFFFF);
  static const _darkProgText = Color(0xFFC084FC);
  static const _darkProgDot = Color(0xFFA855F7);
  static const _darkMathText = Color(0xFFFBBF24);
  static const _darkMathDot = Color(0xFFFBBF24);
  static const _darkEngText = Color(0xFFF472B6);
  static const _darkEngDot = Color(0xFFF472B6);
  static const _darkPhysText = Color(0xFF60A5FA);
  static const _darkPhysDot = Color(0xFF60A5FA);
  static const _darkChemText = Color(0xFF34D399);
  static const _darkChemDot = Color(0xFF34D399);
  static const _darkHistText = Color(0xFFF87171);
  static const _darkHistDot = Color(0xFFF87171);

  static const _darkHeroHomeGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF08060F), Color(0xFF08060F)],
  );
  static const _darkHeroScheduleGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF08060F), Color(0xFF08060F)],
  );
  static const _darkHeroTasksGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF08060F), Color(0xFF08060F)],
  );
  static const _darkCardShadow = <BoxShadow>[];
  static const _darkHeroCardShadow = <BoxShadow>[
    BoxShadow(color: Color(0x40A855F7), blurRadius: 20, offset: Offset(0, 4)),
  ];

  // ---- light (README handoff) ----
  static const _lightBgDeep = Color(0xFFFFFFFF);
  static const _lightBackground = Color(0xFFF2F0FF);
  static const _lightSurface = Color(0xFFFFFFFF);
  static const _lightSurfaceVar = Color(0xFFF3F4F6);
  static const _lightBgInput = Color(0xFFF9FAFB);
  static const _lightBgLayer = Color(0xFFFFFFFF);
  static const _lightTextPrimary = Color(0xFF1A1035);
  static const _lightTextSecondary = Color(0xFF9CA3AF);
  static const _lightTextMuted = Color(0xFFC4B5FD);
  static const _lightBorder = Color(0xFFE5E7EB);
  static const _lightBorderLight = Color(0xFFF3F4F6);
  static const _lightCardBg = Color(0xFFFFFFFF);
  static const _lightCardBorder = Color(0xFFE5E7EB);
  static const _lightDividerSubtle = Color(0xFFF3F4F6);
  static const _lightGlassBg = Color(0x21FFFFFF);
  static const _lightGlassBorder = Color(0x26FFFFFF);
  static const _lightNavBg = Color(0xF5FFFFFF);
  static const _lightNavBorder = Color(0x126B7280);
  static const _lightCheckboxUnchecked = Color(0xFFD1D5DB);
  static const _lightIconButtonBg = Color(0xFFF3F4F6);
  static const _lightProgText = Color(0xFF6D28D9);
  static const _lightProgDot = Color(0xFF6C5CE7);
  static const _lightMathText = Color(0xFFB45309);
  static const _lightMathDot = Color(0xFFF59E0B);
  static const _lightEngText = Color(0xFF9D174D);
  static const _lightEngDot = Color(0xFFEF4444);
  static const _lightPhysText = Color(0xFF1D4ED8);
  static const _lightPhysDot = Color(0xFF74B9FF);
  static const _lightChemText = Color(0xFF065F46);
  static const _lightChemDot = Color(0xFF10B981);
  static const _lightHistText = Color(0xFF991B1B);
  static const _lightHistDot = Color(0xFFEF4444);

  static const _lightHeroHomeGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF6C5CE7), Color(0xFF8B7CF8), Color(0xFFA29BFE)],
  );
  static const _lightHeroScheduleGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF6C5CE7), Color(0xFFA29BFE)],
  );
  static const _lightHeroTasksGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF00B894), Color(0xFF00CEC9)],
  );
  static const _lightCardShadow = <BoxShadow>[
    BoxShadow(color: Color(0x14000000), blurRadius: 16, offset: Offset(0, 2)),
  ];
  static const _lightHeroCardShadow = <BoxShadow>[
    BoxShadow(color: Color(0x1A6C5CE7), blurRadius: 24, offset: Offset(0, 4)),
  ];

  // ==================== Brand/accent (shared) ====================
  static const primary = Color(0xFF7C3AED);
  static const primaryMid = Color(0xFFA855F7);
  static const primaryLight = Color(0xFFC084FC);
  static const primaryDark = Color(0xFF4C1D95);
  static const primaryIndigo = Color(0xFF6C5CE7);

  static const cyan = Color(0xFF22D3EE);
  static const cyanDeep = Color(0xFF06B6D4);
  static const amber = Color(0xFFFBBF24);
  static const amberDeep = Color(0xFFF59E0B);
  static const pink = Color(0xFFF472B6);
  static const blue = Color(0xFF60A5FA);

  static const success = Color(0xFF34D399);
  static const successLight = Color(0x2634D399);
  static const successGreen = Color(0xFF00B894);
  static const warning = Color(0xFFFBBF24);
  static const warningLight = Color(0x1FFBBF24);
  static const danger = Color(0xFFF87171);
  static const dangerLight = Color(0x26F87171);

  static const borderPrimary = Color(0x4DA855F7);

  static const progFill = Color(0x26A855F7);
  static const mathFill = Color(0x1FFBBF24);
  static const engFill = Color(0x1FF472B6);
  static const physFill = Color(0x1F60A5FA);
  static const chemFill = Color(0x1F34D399);
  static const histFill = Color(0x1FF87171);

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
  static const gradientAvatarLight = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFDCB6E), Color(0xFFFD79A8)],
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
  static const gradientUserBubbleLight = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF6C5CE7), Color(0xFFA29BFE)],
  );
  static const gradientAddTaskLight = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF00B894), Color(0xFF00CEC9)],
  );

  static const subjectProgramming = Color(0xFFA855F7);
  static const subjectMath = Color(0xFFFBBF24);
  static const subjectEnglish = Color(0xFFF472B6);
  static const subjectPhysics = Color(0xFF60A5FA);
  static const subjectHistory = Color(0xFFF87171);
  static const subjectPE = Color(0xFF34D399);

  static LinearGradient get userBubbleGradient =>
      isDark ? gradientUserBubble : gradientUserBubbleLight;

  static const gradientAiBannerLight = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF1A1035), Color(0xFF2D1B69)],
  );

  static LinearGradient get aiBannerGradient =>
      isDark ? gradientDark : gradientAiBannerLight;

  static LinearGradient get avatarGradient =>
      isDark ? gradientAvatar : gradientAvatarLight;
}
