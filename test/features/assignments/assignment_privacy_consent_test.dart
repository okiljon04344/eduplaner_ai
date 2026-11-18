import 'dart:convert';

import 'package:edu_planner_ai/core/l10n/app_strings.dart';
import 'package:edu_planner_ai/core/providers/app_providers.dart';
import 'package:edu_planner_ai/core/theme/app_colors.dart';
import 'package:edu_planner_ai/features/assignments/widgets/assignment_detail_sheet.dart';
import 'package:edu_planner_ai/features/auth/models/user_model.dart';
import 'package:edu_planner_ai/features/auth/providers/auth_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:toastification/toastification.dart';

import '../../support/fakes.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting(null);
    await AppStrings.load('ja');
  });
  setUp(() => AppColors.applyBrightness(Brightness.dark));
  tearDown(() => AppColors.applyBrightness(Brightness.dark));

  testWidgets('Prompts one-time AI file consent dialog when user has not consented yet and cancels cleanly', (tester) async {
    final assignment = buildAssignment(id: 'a1', title: '数学レポート');
    final fakeAuth = FakeAuthRepository(currentUser: buildUser(uid: 'u1'));
    final fakeAssign = FakeAssignmentsRepository(initial: [assignment]);
    var pickerCalled = false;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(fakeAuth),
          currentUserProvider.overrideWith((ref) => fakeAuth.currentUser),
          assignmentsRepositoryProvider.overrideWithValue(fakeAssign),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => ElevatedButton(
                onPressed: () => showAssignmentDetailSheet(
                  context,
                  ref,
                  assignment,
                  pickSubmissionFile: () async {
                    pickerCalled = true;
                    return null;
                  },
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text(AppStrings.t('ai_check_btn')));
    await tester.tap(find.text(AppStrings.t('ai_check_btn')));
    await tester.pumpAndSettle();

    // Consent dialog must appear
    expect(find.text(AppStrings.t('ai_file_consent_title')), findsOneWidget);
    expect(find.text(AppStrings.t('ai_file_consent_body')), findsOneWidget);

    // Tapping cancel must NOT record consent or open file picker
    await tester.tap(find.text(AppStrings.t('common_cancel')));
    await tester.pumpAndSettle();

    expect(fakeAuth.recordAiFileConsentCalls, 0);
    expect(pickerCalled, isFalse);
    expect(fakeAuth.currentUser?.hasCurrentAiFileConsent, isFalse);
  });

  testWidgets('Recording AI consent updates user consent state and proceeds to file picker', (tester) async {
    final assignment = buildAssignment(id: 'a2', title: '英語エッセイ');
    final fakeAuth = FakeAuthRepository(currentUser: buildUser(uid: 'u1'));
    final fakeAssign = FakeAssignmentsRepository(initial: [assignment]);
    var pickerCalled = false;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(fakeAuth),
          currentUserProvider.overrideWith((ref) => fakeAuth.currentUser),
          assignmentsRepositoryProvider.overrideWithValue(fakeAssign),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => ElevatedButton(
                onPressed: () => showAssignmentDetailSheet(
                  context,
                  ref,
                  assignment,
                  pickSubmissionFile: () async {
                    pickerCalled = true;
                    return null;
                  },
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text(AppStrings.t('ai_check_btn')));
    await tester.tap(find.text(AppStrings.t('ai_check_btn')));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.t('ai_file_consent_agree')), findsOneWidget);
    await tester.tap(find.text(AppStrings.t('ai_file_consent_agree')));
    await tester.pumpAndSettle();

    expect(fakeAuth.recordAiFileConsentCalls, 1);
    expect(fakeAuth.currentUser?.aiFileConsentVersion, kAiFileConsentVersion);
    expect(fakeAuth.currentUser?.hasCurrentAiFileConsent, isTrue);
    expect(pickerCalled, isTrue);
  });

  testWidgets(
    'Desktop rejects HEIC files with clear message without calling converter or server',
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
    (tester) async {
    final assignment = buildAssignment(id: 'a3', title: '物理プリント');
    final consentedUser = buildUser(uid: 'u1').copyWith(
      aiFileConsentAt: DateTime(2026, 11, 17),
      aiFileConsentVersion: kAiFileConsentVersion,
    );
    final fakeAuth = FakeAuthRepository(currentUser: consentedUser);
    final fakeAssign = FakeAssignmentsRepository(initial: [assignment]);
    var pickerCalled = false;
    var converterCalled = false;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(fakeAuth),
          currentUserProvider.overrideWith((ref) => fakeAuth.currentUser),
          assignmentsRepositoryProvider.overrideWithValue(fakeAssign),
        ],
        child: ToastificationWrapper(
          child: MaterialApp(
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) => ElevatedButton(
                  onPressed: () => showAssignmentDetailSheet(
                    context,
                    ref,
                    assignment,
                    pickSubmissionFile: () async {
                      pickerCalled = true;
                      return (
                        name: 'photo.heic',
                        readBytes: () async => Uint8List.fromList([1, 2, 3]),
                      );
                    },
                    convertHeicToJpeg: (bytes) async {
                      converterCalled = true;
                      return bytes;
                    },
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text(AppStrings.t('ai_check_btn')));
    await tester.tap(find.text(AppStrings.t('ai_check_btn')));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // Consent dialog must NOT appear again
    expect(find.text(AppStrings.t('ai_file_consent_title')), findsNothing);
    expect(fakeAuth.recordAiFileConsentCalls, 0);
    expect(pickerCalled, isTrue);
    expect(converterCalled, isFalse);
    expect(fakeAssign.analyzeSubmissionCalls, 0);

    // Clear HEIC error message must appear
    expect(
      find.text(AppStrings.t('err_heic_unsupported'), skipOffstage: false),
      findsOneWidget,
    );

    // Drain toastification timer
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });

  testWidgets(
    'iOS/Android converts HEIC to JPEG client-side before upload and shows highRedactionWarning banner when flagged',
    variant: const TargetPlatformVariant({TargetPlatform.iOS, TargetPlatform.android}),
    (tester) async {
    final assignment = buildAssignment(id: 'a4', title: '化学レポート');
    final consentedUser = buildUser(uid: 'u1').copyWith(
      aiFileConsentAt: DateTime(2026, 11, 17),
      aiFileConsentVersion: kAiFileConsentVersion,
    );
    final fakeAuth = FakeAuthRepository(currentUser: consentedUser);
    final fakeAssign = FakeAssignmentsRepository(
      initial: [assignment],
      analyzeResult: const {
        'completionPercent': 75.0,
        'missingParts': ['問3の計算過程'],
        'advice': '途中式も書きましょう。',
        'highRedactionWarning': true,
      },
    );
    final rawHeic = Uint8List.fromList([9, 8, 7]);
    final convertedJpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0]);
    var converterCalls = 0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(fakeAuth),
          currentUserProvider.overrideWith((ref) => fakeAuth.currentUser),
          assignmentsRepositoryProvider.overrideWithValue(fakeAssign),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => ElevatedButton(
                onPressed: () => showAssignmentDetailSheet(
                  context,
                  ref,
                  assignment,
                  pickSubmissionFile: () async => (
                    name: 'IMG_1234.HEIC',
                    readBytes: () async => rawHeic,
                  ),
                  convertHeicToJpeg: (bytes) async {
                    converterCalls += 1;
                    expect(bytes, rawHeic);
                    return convertedJpeg;
                  },
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text(AppStrings.t('ai_check_btn')));
    await tester.tap(find.text(AppStrings.t('ai_check_btn')));
    await tester.pumpAndSettle();

    expect(converterCalls, 1);
    expect(fakeAssign.analyzeSubmissionCalls, 1);
    expect(fakeAssign.lastAnalyzeMimeType, 'image/jpeg');
    expect(fakeAssign.lastAnalyzeFileBase64, base64Encode(convertedJpeg));

    // High redaction warning banner and analysis result both appear
    expect(
      find.text(AppStrings.t('ai_high_redaction_warning'), skipOffstage: false),
      findsOneWidget,
    );
    expect(find.text('75%', skipOffstage: false), findsOneWidget);
  });
}
