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
  static Color navBg = darkNavBg;
  static Color navBorder = darkNavBorder;
  static Color checkboxUnchecked = darkCheckboxUnchecked;
  static Color iconButtonBg = darkIconButtonBg;

  // Subject colors (Mutable statics for theme-aware coloring)
  // UZ: Fan ranglari (Mavzuga mos rang berish uchun o'zgaruvchan statiklar)
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

  static List<BoxShadow> get cardShadow => isDark ? darkCardShadow : lightCardShadow;
  static List<BoxShadow> get heroCardShadow => isDark ? darkHeroCardShadow : lightHeroCardShadow;

  static Color get cardSurface => surface;
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
  static const darkBgDeep = Color(0xFF030504);
  static const darkBackground = Color(0xFF050807);
  static const darkSurface = Color(0xFF0E1513);
  static const darkSurfaceVar = Color(0xFF1A2420);
  static const darkBgInput = Color(0xFF1A2420);
  static const darkBgLayer = Color(0xFF0E1513);
  static const darkTextPrimary = Color(0xFFEEF6F2);
  static const darkTextSecondary = Color(0xFFA7B8B0);
  static const darkTextMuted = Color(0xFF7B8D85);
  static const darkBorder = Color(0xFF26332E);
  static const darkBorderLight = Color(0xFF1A2420);
  static const darkCardBg = Color(0xFF0E1513);
  static const darkCardBorder = Color(0xFF26332E);
  static const darkDividerSubtle = Color(0xFF26332E);
  static const darkGlassBg = Color(0x21FFFFFF);
  static const darkNavBg = Color(0xFF0A100E);
  static const darkNavBorder = Color(0xFF26332E);
  static const darkCheckboxUnchecked = Color(0xFF34443D);
  static const darkIconButtonBg = Color(0xFF1A2420);
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

  static const darkCardShadow = <BoxShadow>[];
  static const darkHeroCardShadow = <BoxShadow>[
    BoxShadow(color: Color(0x4006D6A0), blurRadius: 20, offset: Offset(0, 4)),
  ];

  // ---- Light Mode Constants ----
  static const lightBgDeep = Color(0xFFEEF2F0);
  static const lightBackground = Color(0xFFF5F7F6);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightSurfaceVar = Color(0xFFEEF2F0);
  static const lightBgInput = Color(0xFFFFFFFF);
  static const lightBgLayer = Color(0xFFFFFFFF);
  static const lightTextPrimary = Color(0xFF0F1A16);
  static const lightTextSecondary = Color(0xFF4A5A53);
  static const lightTextMuted = Color(0xFF66756E);
  static const lightBorder = Color(0xFFDFE6E2);
  static const lightBorderLight = Color(0xFFEEF2F0);
  static const lightCardBg = Color(0xFFFFFFFF);
  static const lightCardBorder = Color(0xFFDFE6E2);
  static const lightDividerSubtle = Color(0xFFDFE6E2);
  static const lightGlassBg = Color(0x1406D6A0);
  static const lightNavBg = Color(0xFFFFFFFF);
  static const lightNavBorder = Color(0xFFDFE6E2);
  static const lightCheckboxUnchecked = Color(0xFFC8D3CE);
  static const lightIconButtonBg = Color(0xFFEEF2F0);
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

  static const lightCardShadow = <BoxShadow>[];
  static const lightHeroCardShadow = <BoxShadow>[
    BoxShadow(color: Color(0x1A06D6A0), blurRadius: 24, offset: Offset(0, 4)),
  ];

  // ==================== Brand/accent (shared) ====================
  static const primary = Color(0xFF06D6A0);

  /// Label/icon color for content drawn ON primary/gradientPrimary fills —
  /// white on #06D6A0 is only 1.89:1.
  ///
  /// UZ: primary/gradientPrimary to'ldirishlari USTIDA chizilgan kontent uchun yorliq/belgi rangi —
  /// #06D6A0 ustida oq rang atigi 1.89:1 nisbatga ega.
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
  static const gradientDark = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0B1714), Color(0xFF10221C), Color(0xFF0B1714)],
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

  static const subjectProgramming = Color(0xFFA855F7);
  static const subjectMath = Color(0xFFFBBF24);
  static const subjectEnglish = Color(0xFFF472B6);
  static const subjectPhysics = Color(0xFF60A5FA);
  static const subjectHistory = Color(0xFFF87171);

  static LinearGradient get userBubbleGradient =>
      isDark ? gradientUserBubble : gradientUserBubbleLight;

  static const gradientAiBannerLight = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFECFDF5), Color(0xFFD1FAE5)],
  );

  static LinearGradient get aiBannerGradient =>
      isDark ? gradientDark : gradientAiBannerLight;

  /// Status-chip text on the translucent *Light fills: bright on dark, deep
  /// shade on light so it stays readable in both themes.
  ///
  /// UZ: Shaffof *Light fonlar ustidagi holat yozuvi: qorong'ida yorqin, yorug'da to'q
  /// tus, shunda ikkala mavzuda ham o'qiladi.
  static Color get warningText => isDark ? warning : const Color(0xFFC2410C);
  static Color get successText => isDark ? success : const Color(0xFF15803D);

  /// Small accent links/timestamps needing extra pop (`accent-text` token).
  ///
  /// UZ: Qo'shimcha ajralib turishga muhtoj kichik aksent havolalar/vaqt tamg'alari (`accent-text` tokeni).
  static Color get accentText => isDark ? const Color(0xFF06D6A0) : const Color(0xFF047857);

  /// Vibrant green-toned brand panel background (login/onboarding hero
  /// panels) — deliberately distinct from [aiBannerGradient]/[gradientDark],
  /// which use the design's warm-brown `ai-grad` tokens meant only for the
  /// AI chat screen. Reusing those elsewhere muddies the brand color.
  ///
  /// UZ: Jonli yashil tusdagi brend paneli foni (login/onboarding hero panellari) —
  /// ataylab [aiBannerGradient]/[gradientDark] dan farq qiladi, ular faqat AI chat ekrani
  /// uchun mo'ljallangan iliq jigarrang `ai-grad` tokenlaridan foydalanadi. Ularni boshqa joyda
  /// qayta ishlatish brend rangini xiralashtiradi.
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

  // ==================== Glass tokens (mockup spec) ====================
  // Top glass block & general panels
  // UZ: Yuqori oyna (glass) bloki va umumiy panellar
  static Color get glassFill => isDark ? const Color(0x0DFFFFFF) : const Color(0x99FFFFFF);
  static Color get glassBorder => isDark ? const Color(0x1AFFFFFF) : const Color(0xE6FFFFFF);
  static Color get glassHighlight => isDark ? const Color(0x14FFFFFF) : const Color(0xFFFFFFFF);

  // Background glow circles behind Home
  // UZ: Home ortidagi fon nurli doiralari
  static Color get glowGreen => isDark ? const Color(0x4D06D6A0) : const Color(0x4706D6A0);
  static Color get glowBlue => isDark ? const Color(0x3360A5FA) : const Color(0x3860A5FA);
  static Color get glowGreenSubtle => isDark ? const Color(0x2906D6A0) : const Color(0x2E06D6A0);

  // Student bottom navigation
  // UZ: Talabaning pastki navigatsiyasi
  static Color get navGlassFill => isDark ? const Color(0xD90E1513) : const Color(0xD9FFFFFF);
  static Color get navGlassBorder => isDark ? const Color(0x1AFFFFFF) : const Color(0xF2FFFFFF);
  static List<BoxShadow> get navGlassShadow => isDark
      ? const [BoxShadow(color: Color(0x73000000), blurRadius: 32, offset: Offset(0, 12))]
      : const [BoxShadow(color: Color(0x1F0F1A16), blurRadius: 32, offset: Offset(0, 12))];

  // NowLessonCard
  // UZ: NowLessonCard
  static Color get nowGlassFill => isDark ? const Color(0x1F06D6A0) : const Color(0xBFE6FAF2);
  static Color get nowGlassBorder => const Color(0x7306D6A0);
  // Outer-only: these cards have translucent fills, and a normal shadow would
  // show through them as a hard band.
  // UZ: Faqat tashqi (outer-only): bu kartalar yarim shaffof to'ldirishga ega va oddiy soya
  // ular orqali qattiq chiziq kabi ko'rinib qoladi.
  static List<BoxShadow> get nowGlow => isDark
      ? const [BoxShadow(color: Color(0x3806D6A0), blurRadius: 32, blurStyle: BlurStyle.outer)]
      : const [BoxShadow(color: Color(0x2E06D6A0), blurRadius: 30, blurStyle: BlurStyle.outer)];

  // Translucent stat cards & bell chip button inside top hero panel
  // UZ: Yuqori hero panelidagi yarim shaffof statistika kartalari va qo'ng'iroqcha tugmasi
  static Color get statGlassFill => isDark ? const Color(0x0FFFFFFF) : const Color(0xB3FFFFFF);
  static Color get statGlassBorder => isDark ? const Color(0x1AFFFFFF) : const Color(0xF2FFFFFF);

  // Top hero panel shadow in light theme
  // UZ: Yorug' mavzudagi yuqori hero paneli soyasi
  static List<BoxShadow> get glassShadow => isDark
      ? const <BoxShadow>[]
      : const [BoxShadow(color: Color(0x140F1A16), blurRadius: 30, offset: Offset(0, 8))];

}
