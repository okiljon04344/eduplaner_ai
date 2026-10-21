import 'package:flutter/material.dart';

/// EduPlanner AI dizayn tokenlari — Green Neon.
/// Tema o'zgarganda [applyBrightness] orqali statik ranglar yangilanadi.
abstract class AppColors {
  // ==================== Tema holatiga bog'liq ranglar (Mutable) ====================
  static Color bgDeep = darkBgDeep;
  static Color background = darkBackground;
  static Color surface = darkSurface;
  static Color surfaceVar = darkSurfaceVar;
  static Color bgInput = darkBgInput;
  static Color bgLayer = darkBgLayer;

  static Color textPrimary = darkTextPrimary;
  static Color textSecondary = darkTextSecondary;
  static Color textMuted = darkTextMuted;

  /// Hero panellardagi matn rangi. 
  /// Darkda oq, Lightda textPrimary (qora) bo'lishi shart.
  static Color textOnHero = Colors.white;

  static Color border = darkBorder;
  static Color borderLight = darkBorderLight;

  static Color cardBg = darkCardBg;
  static Color cardBorder = darkCardBorder;
  static Color dividerSubtle = darkDividerSubtle;
  static Color glassBg = darkGlassBg;
  static Color glassBorder = darkGlassBorder;
  static Color navBg = darkNavBg;
  static Color navBorder = darkNavBorder;
  static Color checkboxUnchecked = darkCheckboxUnchecked;
  static Color iconButtonBg = darkIconButtonBg;

  // Subject colors (Mutable statics for theme-aware coloring)
  static Color progText = darkProgText;
  static Color progDot = darkProgDot;
  static Color mathText = darkMathText;
  static Color mathDot = darkMathDot;
  static Color engText = darkEngText;
  static Color engDot = darkEngDot;
  static Color physText = darkPhysText;
  static Color physDot = darkPhysDot;
  static Color chemText = darkChemText;
  static Color chemDot = darkChemDot;
  static Color histText = darkHistText;
  static Color histDot = darkHistDot;

  static LinearGradient get heroHomeGradient => isDark ? darkHeroHomeGradient : lightHeroHomeGradient;
  static LinearGradient get heroScheduleGradient => isDark ? darkHeroScheduleGradient : lightHeroScheduleGradient;
  static LinearGradient get heroTasksGradient => isDark ? darkHeroTasksGradient : lightHeroTasksGradient;

  static List<BoxShadow> get cardShadow => isDark ? darkCardShadow : lightCardShadow;
  static List<BoxShadow> get heroCardShadow => isDark ? darkHeroCardShadow : lightHeroCardShadow;

  static Color get cardSurface => isDark ? surfaceVar : surface;
  static Color get cardStroke => border;

  static Brightness _brightness = Brightness.dark;
  static Brightness get brightness => _brightness;
  static bool get isDark => _brightness == Brightness.dark;

  static void applyBrightness(Brightness value) {
    if (_brightness == value) return;
    _brightness = value;
    final isDarkMode = value == Brightness.dark;
    
    bgDeep = isDarkMode ? darkBgDeep : lightBgDeep;
    background = isDarkMode ? darkBackground : lightBackground;
    surface = isDarkMode ? darkSurface : lightSurface;
    surfaceVar = isDarkMode ? darkSurfaceVar : lightSurfaceVar;
    bgInput = isDarkMode ? darkBgInput : lightBgInput;
    bgLayer = isDarkMode ? darkBgLayer : lightBgLayer;
    
    textPrimary = isDarkMode ? darkTextPrimary : lightTextPrimary;
    textSecondary = isDarkMode ? darkTextSecondary : lightTextSecondary;
    textMuted = isDarkMode ? darkTextMuted : lightTextMuted;
    textOnHero = isDarkMode ? Colors.white : lightTextPrimary;
    
    border = isDarkMode ? darkBorder : lightBorder;
    borderLight = isDarkMode ? darkBorderLight : lightBorderLight;
    cardBg = isDarkMode ? darkCardBg : lightCardBg;
    cardBorder = isDarkMode ? darkCardBorder : lightCardBorder;
    dividerSubtle = isDarkMode ? darkDividerSubtle : lightDividerSubtle;
    glassBg = isDarkMode ? darkGlassBg : lightGlassBg;
    glassBorder = isDarkMode ? darkGlassBorder : lightGlassBorder;
    navBg = isDarkMode ? darkNavBg : lightNavBg;
    navBorder = isDarkMode ? darkNavBorder : lightNavBorder;
    checkboxUnchecked = isDarkMode ? darkCheckboxUnchecked : lightCheckboxUnchecked;
    iconButtonBg = isDarkMode ? darkIconButtonBg : lightIconButtonBg;
    
    progText = isDarkMode ? darkProgText : lightProgText;
    progDot = isDarkMode ? darkProgDot : lightProgDot;
    mathText = isDarkMode ? darkMathText : lightMathText;
    mathDot = isDarkMode ? darkMathDot : lightMathDot;
    engText = isDarkMode ? darkEngText : lightEngText;
    engDot = isDarkMode ? darkEngDot : lightEngDot;
    physText = isDarkMode ? darkPhysText : lightPhysText;
    physDot = isDarkMode ? darkPhysDot : lightPhysDot;
    chemText = isDarkMode ? darkChemText : lightChemText;
    chemDot = isDarkMode ? darkChemDot : lightChemDot;
    histText = isDarkMode ? darkHistText : lightHistText;
    histDot = isDarkMode ? darkHistDot : lightHistDot;
  }

  // ---- Dark Mode Constants ----
  static const darkBgDeep = Color(0xFF0C0A08);
  static const darkBackground = Color(0xFF100C08);
  static const darkSurface = Color(0xFF17120A);
  static const darkSurfaceVar = Color(0x0AFFFFFF);
  static const darkBgInput = Color(0xFF221A0E);
  static const darkBgLayer = Color(0xFF241C10);
  static const darkTextPrimary = Color(0xFFFFF3E8);
  static const darkTextSecondary = Color(0x80D1FAE5);
  static const darkTextMuted = Color(0x6ED1FAE5);
  static const darkBorder = Color(0x12FFFFFF);
  static const darkBorderLight = Color(0x0CFFFFFF);
  static const darkCardBg = Color(0x0AFFFFFF);
  static const darkCardBorder = Color(0x12FFFFFF);
  static const darkDividerSubtle = Color(0x0AFFFFFF);
  static const darkGlassBg = Color(0x21FFFFFF);
  static const darkGlassBorder = Color(0x26FFFFFF);
  static const darkNavBg = Color(0xF508060F);
  static const darkNavBorder = Color(0x0FFFFFFF);
  static const darkCheckboxUnchecked = Color(0x26FFFFFF);
  static const darkIconButtonBg = Color(0x14FFFFFF);
  static const darkProgText = Color(0xFFC084FC);
  static const darkProgDot = Color(0xFFA855F7);
  static const darkMathText = Color(0xFFFBBF24);
  static const darkMathDot = Color(0xFFFBBF24);
  static const darkEngText = Color(0xFFF472B6);
  static const darkEngDot = Color(0xFFF472B6);
  static const darkPhysText = Color(0xFF60A5FA);
  static const darkPhysDot = Color(0xFF60A5FA);
  static const darkChemText = Color(0xFF34D399);
  static const darkChemDot = Color(0xFF34D399);
  static const darkHistText = Color(0xFFF87171);
  static const darkHistDot = Color(0xFFF87171);

  static const darkHeroHomeGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF17120A), Color(0xFF1C1108), Color(0xFF100C08)],
  );
  static const darkHeroScheduleGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF17120A), Color(0xFF100C08)],
  );
  static const darkHeroTasksGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0F1F19), Color(0xFF100C08)],
  );
  static const darkCardShadow = <BoxShadow>[];
  static const darkHeroCardShadow = <BoxShadow>[
    BoxShadow(color: Color(0x4006D6A0), blurRadius: 20, offset: Offset(0, 4)),
  ];

  // ---- Light Mode Constants ----
  static const lightBgDeep = Color(0xFFF7F6F3);
  static const lightBackground = Color(0xFFFFFFFF);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightSurfaceVar = Color(0xFFF3F4F6);
  static const lightBgInput = Color(0xFFFFFFFF);
  static const lightBgLayer = Color(0xFFF0FDF9);
  static const lightTextPrimary = Color(0xFF1C1917);
  static const lightTextSecondary = Color(0xFF6B7280);
  static const lightTextMuted = Color(0xFF7A818D);
  static const lightBorder = Color(0xFFE5E7EB);
  static const lightBorderLight = Color(0xFFF3F4F6);
  static const lightCardBg = Color(0xFFFFFFFF);
  static const lightCardBorder = Color(0xFFE5E7EB);
  static const lightDividerSubtle = Color(0xFFF3F4F6);
  static const lightGlassBg = Color(0x1406D6A0);
  static const lightGlassBorder = Color(0x2606D6A0);
  static const lightNavBg = Color(0xEBFFFFFF);
  static const lightNavBorder = Color(0x126B7280);
  static const lightCheckboxUnchecked = Color(0xFFD1D5DB);
  static const lightIconButtonBg = Color(0xFFF3F4F6);
  static const lightProgText = Color(0xFF6D28D9);
  static const lightProgDot = Color(0xFF6C5CE7);
  static const lightMathText = Color(0xFFB45309);
  static const lightMathDot = Color(0xFFF59E0B);
  static const lightEngText = Color(0xFF9D174D);
  static const lightEngDot = Color(0xFFEF4444);
  static const lightPhysText = Color(0xFF1D4ED8);
  static const lightPhysDot = Color(0xFF74B9FF);
  static const lightChemText = Color(0xFF065F46);
  static const lightChemDot = Color(0xFF10B981);
  static const lightHistText = Color(0xFF991B1B);
  static const lightHistDot = Color(0xFFEF4444);

  static const lightHeroHomeGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFECFDF5), Color(0xFFD1FAE5), Color(0xFFFFFFFF)],
  );
  static const lightHeroScheduleGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFECFDF5), Color(0xFFFFFFFF)],
  );
  static const lightHeroTasksGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFD1FAE5), Color(0xFFFFFFFF)],
  );
  static const lightCardShadow = <BoxShadow>[
    BoxShadow(color: Color(0x14000000), blurRadius: 16, offset: Offset(0, 2)),
  ];
  static const lightHeroCardShadow = <BoxShadow>[
    BoxShadow(color: Color(0x1A06D6A0), blurRadius: 24, offset: Offset(0, 4)),
  ];

  // ==================== Brand/accent (shared) ====================
  static const primary = Color(0xFF06D6A0);

  /// Label/icon color for content drawn ON primary/gradientPrimary fills —
  /// white on #06D6A0 is only 1.89:1.
  static const onPrimary = Color(0xFF04291F);
  static const primaryMid = Color(0xFF34D399);
  static const primaryLight = Color(0xFF5EEAD4);
  static const primaryDark = Color(0xFF059669);
  static const primaryIndigo = Color(0xFF059669);

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

  static const borderPrimary = Color(0x4D34D399);

  static const progFill = Color(0x26A855F7);
  static const mathFill = Color(0x1FFBBF24);
  static const engFill = Color(0x1FF472B6);
  static const physFill = Color(0x1F60A5FA);
  static const chemFill = Color(0x1F34D399);
  static const histFill = Color(0x1FF87171);

  static const gradientPrimary = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF059669), Color(0xFF06D6A0), Color(0xFF5EEAD4)],
  );
  static const gradientCyan = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [Color(0xFF059669), Color(0xFF34D399), Color(0xFF5EEAD4)],
  );
  static const gradientAmber = LinearGradient(colors: [Color(0xFFF59E0B), Color(0xFFFBBF24)]);
  static const gradientAvatar = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF06D6A0), Color(0xFF5EEAD4)],
  );
  static const gradientAvatarLight = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF059669), Color(0xFF06D6A0)],
  );
  static const gradientDark = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF1C1108), Color(0xFF2A1B0C), Color(0xFF1C1108)],
  );
  static const gradientUserBubble = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF059669), Color(0xFF06D6A0)],
  );
  static const gradientUserBubbleLight = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF059669), Color(0xFF06D6A0)],
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
    colors: [Color(0xFFECFDF5), Color(0xFFD1FAE5)],
  );

  static LinearGradient get aiBannerGradient =>
      isDark ? gradientDark : gradientAiBannerLight;

  static LinearGradient get avatarGradient =>
      isDark ? gradientAvatar : gradientAvatarLight;

  /// AI banner/header gradient stops (`ai-grad-1`/`ai-grad-2` in the design
  /// tokens) — exposed individually for headers that need just the two
  /// stops rather than the full 3-stop [aiBannerGradient].
  static Color get aiGrad1 => isDark ? const Color(0xFF1C1108) : const Color(0xFFECFDF5);
  static Color get aiGrad2 => isDark ? const Color(0xFF2A1B0C) : const Color(0xFFD1FAE5);

  /// Small accent links/timestamps needing extra pop (`accent-text` token).
  static Color get accentText => isDark ? const Color(0xFF06D6A0) : const Color(0xFF047857);

  /// Vibrant green-toned brand panel background (login/onboarding hero
  /// panels) — deliberately distinct from [aiBannerGradient]/[gradientDark],
  /// which use the design's warm-brown `ai-grad` tokens meant only for the
  /// AI chat screen. Reusing those elsewhere muddies the brand color.
  static const _darkBrandPanelGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0F1F19), Color(0xFF0C1611), Color(0xFF100C08)],
  );
  static const _lightBrandPanelGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFD1FAE5), Color(0xFFECFDF5), Color(0xFFFFFFFF)],
  );
  static LinearGradient get brandPanelGradient =>
      isDark ? _darkBrandPanelGradient : _lightBrandPanelGradient;
}
