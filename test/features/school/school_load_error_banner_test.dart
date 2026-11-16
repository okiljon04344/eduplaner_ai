import 'package:edu_planner_ai/core/l10n/app_strings.dart';
import 'package:edu_planner_ai/core/theme/app_colors.dart';
import 'package:edu_planner_ai/features/school/school_providers.dart';
import 'package:edu_planner_ai/features/school/widgets/school_load_error_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _buildBanner({required bool failed, EdgeInsets? margin}) => ProviderScope(
      overrides: [
        schoolLoadFailedProvider.overrideWithValue(failed),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SchoolLoadErrorBanner(margin: margin),
        ),
      ),
    );

void main() {
  setUp(() => AppColors.applyBrightness(Brightness.dark));

  testWidgets('banner hidden when the provider is false', (tester) async {
    await tester.pumpWidget(_buildBanner(failed: false));
    await tester.pumpAndSettle();

    expect(find.byType(SchoolLoadErrorBanner), findsOneWidget);
    expect(find.byIcon(Icons.cloud_off_outlined), findsNothing);
    expect(find.text(AppStrings.t('school_load_error')), findsNothing);
    expect(tester.getSize(find.byType(SchoolLoadErrorBanner)), Size.zero);
  });

  testWidgets('shows the text when true', (tester) async {
    await tester.pumpWidget(_buildBanner(failed: true, margin: const EdgeInsets.all(16)));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.cloud_off_outlined), findsOneWidget);
    expect(find.text(AppStrings.t('school_load_error')), findsOneWidget);
    expect(
      find.byWidgetPredicate((w) => w is Semantics && w.properties.liveRegion == true),
      findsOneWidget,
    );
  });
}
