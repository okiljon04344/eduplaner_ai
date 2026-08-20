import 'package:edu_planner_ai/core/theme/app_colors.dart';
import 'package:edu_planner_ai/features/timetable/widgets/day_tab_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _harness(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  // Force dark so tests don't depend on whatever the last test left behind.
  setUp(() => AppColors.applyBrightness(Brightness.dark));
  tearDown(() => AppColors.applyBrightness(Brightness.dark));

  testWidgets('renders the five weekday labels 月・火・水・木・金', (tester) async {
    await tester.pumpWidget(_harness(
      DayTabRow(
        selectedDay: 0,
        weekStart: DateTime(2026, 8, 3), // Monday 2026-08-03
        onSelect: (_) {},
      ),
    ));

    for (final label in const ['月', '火', '水', '木', '金']) {
      expect(find.text(label), findsOneWidget, reason: 'weekday $label should render');
    }
  });

  testWidgets('propagates the weekStart date to each tab (M/D under the label)', (tester) async {
    // Monday 2026-08-03 → tabs render 8/3, 8/4, 8/5, 8/6, 8/7.
    final weekStart = DateTime(2026, 8, 3);
    await tester.pumpWidget(_harness(
      DayTabRow(selectedDay: 2, weekStart: weekStart, onSelect: (_) {}),
    ));

    expect(find.text('8/3'), findsOneWidget);
    expect(find.text('8/4'), findsOneWidget);
    expect(find.text('8/5'), findsOneWidget);
    expect(find.text('8/6'), findsOneWidget);
    expect(find.text('8/7'), findsOneWidget);
  });

  testWidgets('tapping a tab fires onSelect with that index', (tester) async {
    final selected = <int>[];
    await tester.pumpWidget(_harness(
      DayTabRow(
        selectedDay: 0,
        weekStart: DateTime(2026, 8, 3),
        onSelect: selected.add,
      ),
    ));

    await tester.tap(find.text('水'));
    await tester.pumpAndSettle();

    expect(selected, [2]);
  });

  testWidgets('selected tab is visually distinct from unselected tabs', (tester) async {
    await tester.pumpWidget(_harness(
      DayTabRow(
        selectedDay: 1, // 火
        weekStart: DateTime(2026, 8, 3),
        onSelect: (_) {},
      ),
    ));

    // The active tab background is AppColors.primary at 22% alpha (see
    // day_tab_row.dart); no other tab uses that colour. Finding exactly one
    // such container proves that (a) some tab is selected, and (b) only one
    // is — no state leak across tabs.
    final activeBg = AppColors.primary.withValues(alpha: 0.22);
    final activeContainers = find.byWidgetPredicate((w) {
      if (w is! AnimatedContainer) return false;
      final deco = w.decoration;
      return deco is BoxDecoration && deco.color == activeBg;
    });
    expect(activeContainers, findsOneWidget);
  });

  testWidgets('renders cleanly in both dark and light themes', (tester) async {
    for (final brightness in [Brightness.dark, Brightness.light]) {
      AppColors.applyBrightness(brightness);
      await tester.pumpWidget(_harness(
        DayTabRow(
          selectedDay: 0,
          weekStart: DateTime(2026, 8, 3),
          onSelect: (_) {},
        ),
      ));
      expect(find.text('月'), findsOneWidget, reason: 'theme=$brightness');
      expect(tester.takeException(), isNull, reason: 'no exception in $brightness');
    }
  });
}
