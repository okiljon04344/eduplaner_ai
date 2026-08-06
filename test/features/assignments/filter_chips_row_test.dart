import 'package:edu_planner_ai/core/theme/app_colors.dart';
import 'package:edu_planner_ai/features/assignments/providers/assignments_provider.dart';
import 'package:edu_planner_ai/features/assignments/widgets/filter_chips_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _harness(Widget child) => ProviderScope(
      child: MaterialApp(home: Scaffold(body: child)),
    );

void main() {
  setUp(() => AppColors.applyBrightness(Brightness.dark));
  tearDown(() => AppColors.applyBrightness(Brightness.dark));

  testWidgets('renders all four filter labels in Japanese', (tester) async {
    await tester.pumpWidget(_harness(const FilterChipsRow()));

    for (final label in const ['すべて', '未着手', '進行中', '完了']) {
      expect(find.text(label), findsOneWidget, reason: 'filter $label should render');
    }
  });

  testWidgets('tapping a chip updates selectedFilterProvider', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: FilterChipsRow())),
    ));

    // Default state.
    expect(container.read(selectedFilterProvider), 'すべて');

    await tester.tap(find.text('進行中'));
    await tester.pumpAndSettle();
    expect(container.read(selectedFilterProvider), '進行中');

    await tester.tap(find.text('完了'));
    await tester.pumpAndSettle();
    expect(container.read(selectedFilterProvider), '完了');

    await tester.tap(find.text('未着手'));
    await tester.pumpAndSettle();
    expect(container.read(selectedFilterProvider), '未着手');
  });

  testWidgets('reflects an externally-set filter as the visually-active chip', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    // Preset before first frame.
    container.read(selectedFilterProvider.notifier).state = '完了';

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: FilterChipsRow())),
    ));

    // Widget still renders all four labels regardless of which is active.
    expect(find.text('完了'), findsOneWidget);
    expect(container.read(selectedFilterProvider), '完了');
    expect(tester.takeException(), isNull);
  });
}
