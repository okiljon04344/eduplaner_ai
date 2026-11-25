import 'package:edu_planner_ai/core/l10n/app_strings.dart';
import 'package:edu_planner_ai/core/theme/app_colors.dart';
import 'package:edu_planner_ai/features/onboarding/providers/onboarding_provider.dart';
import 'package:edu_planner_ai/features/onboarding/screens/onboarding_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    AppColors.applyBrightness(Brightness.dark);
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('three slides, email hint on the last, start marks onboarding done', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: OnboardingScreen()),
    ));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.t('onboard_1_title')), findsOneWidget);
    expect(find.text(AppStrings.t('onboard_next_hint')), findsNothing);

    for (var i = 0; i < 2; i++) {
      await tester.tap(find.text(AppStrings.t('onboard_next')));
      await tester.pumpAndSettle();
    }
    expect(find.text(AppStrings.t('onboard_3_title')), findsOneWidget);
    expect(find.text(AppStrings.t('onboard_next_hint')), findsOneWidget);

    await tester.tap(find.text(AppStrings.t('onboard_start')));
    await tester.pumpAndSettle();
    expect(container.read(onboardingProvider).valueOrNull, isTrue);
  });
}
