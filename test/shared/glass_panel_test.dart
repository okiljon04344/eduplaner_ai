import 'dart:ui';
import 'package:edu_planner_ai/core/theme/app_colors.dart';
import 'package:edu_planner_ai/shared/widgets/glass_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _buildHarness({
  required bool disableAnimations,
  double? blurSigma,
  Color? tint,
  Color? borderColor,
  List<BoxShadow>? shadows,
  double radius = 24,
  EdgeInsetsGeometry? padding,
}) {
  return MaterialApp(
    home: Scaffold(
      body: MediaQuery(
        data: MediaQueryData(disableAnimations: disableAnimations),
        child: GlassPanel(
          blurSigma: blurSigma,
          tint: tint,
          borderColor: borderColor,
          shadows: shadows,
          radius: radius,
          padding: padding,
          child: const Text('Glass Content'),
        ),
      ),
    ),
  );
}

void main() {
  tearDown(() => AppColors.applyBrightness(Brightness.dark));

  group('GlassPanel', () {
    testWidgets('renders child content', (tester) async {
      await tester.pumpWidget(
        _buildHarness(disableAnimations: false, blurSigma: 24),
      );
      expect(find.text('Glass Content'), findsOneWidget);
    });

    testWidgets('includes BackdropFilter when animations are allowed and blurSigma > 0', (tester) async {
      await tester.pumpWidget(
        _buildHarness(
          disableAnimations: false,
          blurSigma: 24,
          tint: const Color(0x8C131B18),
        ),
      );

      expect(find.byType(BackdropFilter), findsOneWidget);
      final backdrop = tester.widget<BackdropFilter>(find.byType(BackdropFilter));
      expect(backdrop.filter, ImageFilter.blur(sigmaX: 24, sigmaY: 24));
    });

    testWidgets('omits BackdropFilter and paints cardSurface when disableAnimations is true', (tester) async {
      AppColors.applyBrightness(Brightness.dark);
      await tester.pumpWidget(
        _buildHarness(
          disableAnimations: true,
          blurSigma: 24,
          tint: const Color(0x8C131B18),
        ),
      );

      // BackdropFilter must NOT be present when animations are disabled
      expect(find.byType(BackdropFilter), findsNothing);

      // DecoratedBox should have painted AppColors.cardSurface for readability
      final decoratedBoxes = tester.widgetList<DecoratedBox>(find.byType(DecoratedBox));
      final innerBox = decoratedBoxes.firstWhere(
        (box) => box.decoration is BoxDecoration && (box.decoration as BoxDecoration).color != null,
      );
      final decoration = innerBox.decoration as BoxDecoration;
      expect(decoration.color, AppColors.cardSurface);
    });

    testWidgets('omits BackdropFilter when blurSigma is null, but uses translucent tint', (tester) async {
      const customTint = Color(0x0DFFFFFF);
      await tester.pumpWidget(
        _buildHarness(
          disableAnimations: false,
          blurSigma: null,
          tint: customTint,
        ),
      );

      expect(find.byType(BackdropFilter), findsNothing);

      final decoratedBoxes = tester.widgetList<DecoratedBox>(find.byType(DecoratedBox));
      final innerBox = decoratedBoxes.firstWhere(
        (box) => box.decoration is BoxDecoration && (box.decoration as BoxDecoration).color != null,
      );
      final decoration = innerBox.decoration as BoxDecoration;
      expect(decoration.color, customTint);
    });

    testWidgets('paints custom shadows on outer decorated box without clipping', (tester) async {
      const shadows = [
        BoxShadow(color: Color(0x3806D6A0), blurRadius: 32),
      ];

      await tester.pumpWidget(
        _buildHarness(
          disableAnimations: false,
          blurSigma: 24,
          shadows: shadows,
        ),
      );

      final outerBox = tester.widget<DecoratedBox>(find.byType(DecoratedBox).first);
      final decoration = outerBox.decoration as BoxDecoration;
      // Outer-only, centred: a shadow under the translucent fill would show
      // through as a hard band.
      expect(decoration.boxShadow, const [
        BoxShadow(color: Color(0x3806D6A0), blurRadius: 32, blurStyle: BlurStyle.outer),
      ]);
    });

    testWidgets('renders cleanly in both dark and light modes', (tester) async {
      for (final brightness in [Brightness.dark, Brightness.light]) {
        AppColors.applyBrightness(brightness);
        await tester.pumpWidget(
          _buildHarness(
            disableAnimations: false,
            blurSigma: 24,
            tint: AppColors.navGlassFill,
            borderColor: AppColors.navGlassBorder,
            shadows: AppColors.navGlassShadow,
          ),
        );
        expect(tester.takeException(), isNull);
        expect(find.text('Glass Content'), findsOneWidget);
      }
    });
  });
}
