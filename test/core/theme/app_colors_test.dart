import 'package:edu_planner_ai/core/constants/subject_colors.dart';
import 'package:edu_planner_ai/core/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Every test file that pokes AppColors must restore dark mode afterwards —
  // it's a mutable global and would otherwise leak into unrelated tests
  // running in the same isolate.
  tearDown(() => AppColors.applyBrightness(Brightness.dark));

  group('AppColors.applyBrightness', () {
    test('flips every mutable surface/text token to its light-mode value', () {
      AppColors.applyBrightness(Brightness.light);

      expect(AppColors.isDark, isFalse);
      expect(AppColors.brightness, Brightness.light);

      // Surface family
      expect(AppColors.background, const Color(0xFFFFFFFF));
      expect(AppColors.surface, const Color(0xFFFFFFFF));
      expect(AppColors.bgDeep, const Color(0xFFF7F6F3));
      expect(AppColors.bgInput, const Color(0xFFFFFFFF));
      expect(AppColors.bgLayer, const Color(0xFFF0FDF9));

      // Text family
      expect(AppColors.textPrimary, const Color(0xFF1C1917));
      expect(AppColors.textSecondary, const Color(0xFF9CA3AF));
      expect(AppColors.textMuted, const Color(0xFFB0B7C3));

      // Borders / dividers
      expect(AppColors.border, const Color(0xFFE5E7EB));
      expect(AppColors.borderLight, const Color(0xFFF3F4F6));

      // Subject text/dot pairs (only text/dot flip; fills stay constant)
      expect(AppColors.mathText, const Color(0xFFB45309));
      expect(AppColors.mathDot, const Color(0xFFF59E0B));
      expect(AppColors.progText, const Color(0xFF6D28D9));
      expect(AppColors.progDot, const Color(0xFF6C5CE7));
    });

    test('flips back to dark-mode values when brightness is Brightness.dark', () {
      AppColors.applyBrightness(Brightness.light);
      AppColors.applyBrightness(Brightness.dark);

      expect(AppColors.isDark, isTrue);
      expect(AppColors.background, const Color(0xFF100C08));
      expect(AppColors.surface, const Color(0xFF17120A));
      expect(AppColors.textPrimary, const Color(0xFFFFF3E8));
      expect(AppColors.mathText, const Color(0xFFFBBF24));
    });

    test('leaves brand/accent tokens unchanged across theme flips', () {
      const brandPrimary = Color(0xFF06D6A0);
      const brandPrimaryMid = Color(0xFF34D399);
      const brandDanger = Color(0xFFF87171);
      const brandCyan = Color(0xFF22D3EE);
      const brandSuccess = Color(0xFF34D399);

      AppColors.applyBrightness(Brightness.light);
      expect(AppColors.primary, brandPrimary);
      expect(AppColors.primaryMid, brandPrimaryMid);
      expect(AppColors.danger, brandDanger);
      expect(AppColors.cyan, brandCyan);
      expect(AppColors.success, brandSuccess);
      // Subject *fills* live under brand tokens too.
      expect(AppColors.mathFill, const Color(0x1FFBBF24));
      expect(AppColors.progFill, const Color(0x26A855F7));

      AppColors.applyBrightness(Brightness.dark);
      expect(AppColors.primary, brandPrimary);
      expect(AppColors.primaryMid, brandPrimaryMid);
      expect(AppColors.danger, brandDanger);
      expect(AppColors.cyan, brandCyan);
      expect(AppColors.success, brandSuccess);
      expect(AppColors.mathFill, const Color(0x1FFBBF24));
      expect(AppColors.progFill, const Color(0x26A855F7));
    });
  });

  group('SubjectColors.of', () {
    test('returns the correct fill/text/dot triple for each of the six subjects', () {
      // Dark palette (default), one representative expectation per subject.
      AppColors.applyBrightness(Brightness.dark);

      final math = SubjectColors.of('数学');
      expect(math.fill, AppColors.mathFill);
      expect(math.text, AppColors.mathText);
      expect(math.dot, AppColors.mathDot);

      final english = SubjectColors.of('英語');
      expect(english.fill, AppColors.engFill);
      expect(english.text, AppColors.engText);
      expect(english.dot, AppColors.engDot);

      final prog = SubjectColors.of('プログラミング');
      expect(prog.fill, AppColors.progFill);
      expect(prog.text, AppColors.progText);
      expect(prog.dot, AppColors.progDot);

      final phys = SubjectColors.of('物理');
      expect(phys.fill, AppColors.physFill);
      expect(phys.text, AppColors.physText);
      expect(phys.dot, AppColors.physDot);

      final chem = SubjectColors.of('化学');
      expect(chem.fill, AppColors.chemFill);
      expect(chem.text, AppColors.chemText);
      expect(chem.dot, AppColors.chemDot);

      final hist = SubjectColors.of('歴史');
      expect(hist.fill, AppColors.histFill);
      expect(hist.text, AppColors.histText);
      expect(hist.dot, AppColors.histDot);
    });

    test('subject text/dot re-read [AppColors] after applyBrightness (not baked at first access)', () {
      // Warm-up in dark mode.
      AppColors.applyBrightness(Brightness.dark);
      final darkMathText = SubjectColors.of('数学').text;
      expect(darkMathText, AppColors.mathText);

      // Flip to light and confirm the returned style tracks the new token.
      AppColors.applyBrightness(Brightness.light);
      final lightMathText = SubjectColors.of('数学').text;
      expect(lightMathText, AppColors.mathText);
      expect(lightMathText, isNot(equals(darkMathText)));
    });

    test('unknown subjects fall back to the neutral style (no crash)', () {
      AppColors.applyBrightness(Brightness.dark);
      final custom = SubjectColors.of('カスタム科目');
      expect(custom.text, AppColors.textSecondary);
      expect(custom.dot, AppColors.textMuted);
      // Fill is a fixed neutral 8% white regardless of theme.
      expect(custom.fill, const Color(0x14FFFFFF));
    });

    test('lists the six built-in subject names via `all`', () {
      expect(
        SubjectColors.all,
        containsAll(<String>['数学', '英語', 'プログラミング', '物理', '化学', '歴史']),
      );
    });
  });
}
