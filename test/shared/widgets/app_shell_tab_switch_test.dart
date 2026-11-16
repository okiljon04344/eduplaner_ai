import 'package:edu_planner_ai/core/providers/app_providers.dart';
import 'package:edu_planner_ai/core/theme/app_colors.dart';
import 'package:edu_planner_ai/features/school/school_providers.dart';
import 'package:edu_planner_ai/shared/widgets/app_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  setUp(() => AppColors.applyBrightness(Brightness.dark));

  // Regression: the shell child is go_router's Navigator (it has a GlobalKey).
  // Animating tab switches with two live copies threw "Duplicate GlobalKey
  // detected in widget tree" on every tab tap.
  testWidgets('switching tabs does not duplicate the shell navigator', (tester) async {
    final router = GoRouter(
      initialLocation: '/home',
      routes: [
        ShellRoute(
          builder: (_, __, child) => AppShell(child: child),
          routes: [
            GoRoute(path: '/home', builder: (_, __) => const Text('home page')),
            GoRoute(path: '/timetable', builder: (_, __) => const Text('timetable page')),
          ],
        ),
      ],
    );
    final container = ProviderContainer(overrides: [
      schoolReminderSyncProvider.overrideWithValue(null),
      schoolRoleProvider.overrideWithValue((teacher: false, admin: false)),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();

    router.go('/timetable');
    container.read(shellTabIndexProvider.notifier).state = 1;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100)); // mid-transition
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    expect(find.text('timetable page'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
