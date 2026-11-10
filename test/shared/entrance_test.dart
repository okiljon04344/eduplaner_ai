import 'package:edu_planner_ai/shared/widgets/entrance.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    Entrance.reset();
  });

  tearDown(() {
    Entrance.reset();
  });

  group('Entrance', () {
    testWidgets('fades and translates on first play, and plays only once', (tester) async {
      expect(Entrance.hasPlayed, isFalse);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Entrance(
              index: 0,
              child: Text('Home Section'),
            ),
          ),
        ),
      );

      // On first frame, Transform exists inside Entrance to offset 10px vertically
      final entranceTransformFinder = find.descendant(
        of: find.byType(Entrance),
        matching: find.byType(Transform),
      );
      expect(entranceTransformFinder, findsOneWidget);
      expect(find.text('Home Section'), findsOneWidget);

      // Animate to completion
      await tester.pump(const Duration(milliseconds: 280));
      await tester.pumpAndSettle();

      expect(Entrance.hasPlayed, isTrue);

      // Subsequent build after hasPlayed = true leaves no Transform / ticker
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Entrance(
              index: 0,
              child: Text('Home Section'),
            ),
          ),
        ),
      );

      // Child renders directly with no Transform wrapper inside Entrance
      expect(entranceTransformFinder, findsNothing);
      expect(find.text('Home Section'), findsOneWidget);
    });

    testWidgets('with disableAnimations there is no Transform offset', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MediaQuery(
              data: MediaQueryData(disableAnimations: true),
              child: Entrance(
                index: 0,
                child: Text('Section Reduced'),
              ),
            ),
          ),
        ),
      );

      // Reduced motion: no movement at all, zero Transform widgets inside Entrance
      final entranceTransformFinder = find.descendant(
        of: find.byType(Entrance),
        matching: find.byType(Transform),
      );
      expect(entranceTransformFinder, findsNothing);
      expect(find.text('Section Reduced'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 150));
      await tester.pumpAndSettle();
      expect(Entrance.hasPlayed, isTrue);
    });
  });
}
