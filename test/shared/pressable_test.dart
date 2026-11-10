import 'package:edu_planner_ai/shared/widgets/pressable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Pressable', () {
    testWidgets('scales down on press, back on release, and tap fires', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: Pressable(
                onTap: () => tapped = true,
                child: const Text('Tap Me'),
              ),
            ),
          ),
        ),
      );

      final scaleFinder = find.byType(AnimatedScale);
      expect(scaleFinder, findsOneWidget);
      expect(tester.widget<AnimatedScale>(scaleFinder).scale, 1.0);

      // Press down
      final gesture = await tester.startGesture(tester.getCenter(find.text('Tap Me')));
      await tester.pump();
      expect(tester.widget<AnimatedScale>(scaleFinder).scale, 0.97);

      await tester.pump(const Duration(milliseconds: 120));

      // Release
      await gesture.up();
      await tester.pump();
      expect(tester.widget<AnimatedScale>(scaleFinder).scale, 1.0);

      await tester.pump(const Duration(milliseconds: 120));
      expect(tapped, isTrue);
    });

    testWidgets('scales back on cancel and does not fire onTap', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: Pressable(
                onTap: () => tapped = true,
                child: const Text('Cancel Me'),
              ),
            ),
          ),
        ),
      );

      final scaleFinder = find.byType(AnimatedScale);
      final gesture = await tester.startGesture(tester.getCenter(find.text('Cancel Me')));
      await tester.pump();
      expect(tester.widget<AnimatedScale>(scaleFinder).scale, 0.97);

      await gesture.cancel();
      await tester.pump();
      expect(tester.widget<AnimatedScale>(scaleFinder).scale, 1.0);

      await tester.pump(const Duration(milliseconds: 120));
      expect(tapped, isFalse);
    });

    testWidgets('does not scale when disableAnimations is true', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MediaQuery(
              data: const MediaQueryData(disableAnimations: true),
              child: Center(
                child: Pressable(
                  onTap: () => tapped = true,
                  child: const Text('Reduced Motion'),
                ),
              ),
            ),
          ),
        ),
      );

      final scaleFinder = find.byType(AnimatedScale);
      final gesture = await tester.startGesture(tester.getCenter(find.text('Reduced Motion')));
      await tester.pump();
      expect(tester.widget<AnimatedScale>(scaleFinder).scale, 1.0);

      await gesture.up();
      await tester.pump();
      expect(tester.widget<AnimatedScale>(scaleFinder).scale, 1.0);
      expect(tapped, isTrue);
    });

    testWidgets('pure visual Pressable (onTap: null) scales and preserves inner InkWell tap', (tester) async {
      var innerTapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: Pressable(
                child: InkWell(
                  onTap: () => innerTapped = true,
                  child: const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Inner InkWell'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      final scaleFinder = find.byType(AnimatedScale);
      expect(tester.widget<AnimatedScale>(scaleFinder).scale, 1.0);

      final gesture = await tester.startGesture(tester.getCenter(find.text('Inner InkWell')));
      await tester.pump();
      expect(tester.widget<AnimatedScale>(scaleFinder).scale, 0.97);

      await gesture.up();
      await tester.pump();
      expect(tester.widget<AnimatedScale>(scaleFinder).scale, 1.0);

      await tester.pump(const Duration(milliseconds: 120));
      expect(innerTapped, isTrue);
    });
  });
}
