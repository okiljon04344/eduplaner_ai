import 'package:edu_planner_ai/core/theme/app_colors.dart';
import 'package:edu_planner_ai/shared/widgets/app_bottom_nav.dart';
import 'package:edu_planner_ai/shared/widgets/nav_destinations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  setUp(() {
    AppColors.applyBrightness(Brightness.dark);
  });

  tearDown(() {
    AppColors.applyBrightness(Brightness.dark);
  });

  testWidgets('active index changes the pill alignment', (tester) async {
    final router = GoRouter(
      initialLocation: '/home',
      routes: [
        for (final route in kNavRoutes)
          GoRoute(
            path: route,
            builder: (context, state) => const Scaffold(
              body: SizedBox.expand(),
              bottomNavigationBar: AppBottomNav(),
            ),
          ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // At '/home' (index 0), alignment x should be -1.0
    final alignFinder = find.byType(AnimatedAlign);
    expect(alignFinder, findsOneWidget);
    var alignWidget = tester.widget<AnimatedAlign>(alignFinder);
    expect(alignWidget.alignment, const Alignment(-1.0, 0.0));

    // Navigate to '/assignments' (index 2) -> alignment x should be 0.0
    router.go('/assignments');
    await tester.pumpAndSettle();

    alignWidget = tester.widget<AnimatedAlign>(alignFinder);
    expect(alignWidget.alignment, const Alignment(0.0, 0.0));

    // Navigate to '/settings' (index 4) -> alignment x should be 1.0
    router.go('/settings');
    await tester.pumpAndSettle();

    alignWidget = tester.widget<AnimatedAlign>(alignFinder);
    expect(alignWidget.alignment, const Alignment(1.0, 0.0));
  });
}
