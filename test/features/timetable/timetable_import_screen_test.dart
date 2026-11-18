import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toastification/toastification.dart';
import 'package:edu_planner_ai/core/l10n/app_strings.dart';
import 'package:edu_planner_ai/core/providers/clock_provider.dart';
import 'package:edu_planner_ai/core/theme/app_colors.dart';
import 'package:edu_planner_ai/features/auth/models/user_model.dart';
import 'package:edu_planner_ai/features/auth/providers/auth_provider.dart';
import 'package:edu_planner_ai/features/school/models/school.dart';
import 'package:edu_planner_ai/features/school/school_providers.dart';
import 'package:edu_planner_ai/features/school/screens/teacher_screen.dart';
import 'package:edu_planner_ai/features/school/teacher_overview_providers.dart';
import 'package:edu_planner_ai/features/timetable/models/timetable_import_failure.dart';
import 'package:edu_planner_ai/features/timetable/models/timetable_import_models.dart';
import 'package:edu_planner_ai/features/timetable/providers/timetable_import_provider.dart';
import 'package:edu_planner_ai/features/timetable/repositories/timetable_import_repository.dart';
import 'package:edu_planner_ai/features/timetable/screens/timetable_import_screen.dart';

class _FakeRepo implements TimetableImportRepository {
  TimetableImportPreview? previewToReturn;
  ImportResult? resultToReturn;
  RevertResult? revertToReturn;
  Object? previewError;
  Object? confirmError;
  Object? revertError;

  int previewCalls = 0;
  int confirmCalls = 0;
  int revertCalls = 0;
  String? lastMode;

  @override
  Future<TimetableImportPreview> previewImport({
    required int grade,
    required String? course,
    required String mode,
    required String fileName,
    required String mimeType,
    required Uint8List fileBytes,
    required String startDate,
    required String endDate,
    bool includeNonSchoolDays = false,
  }) async {
    previewCalls++;
    lastMode = mode;
    if (previewError != null) throw previewError!;
    return previewToReturn ?? _samplePreview();
  }

  @override
  Future<ImportResult> confirmImport({
    required String draftId,
    required bool notifyStudents,
    String? pushSummary,
  }) async {
    confirmCalls++;
    if (confirmError != null) throw confirmError!;
    return resultToReturn ??
        const ImportResult(
          ok: true,
          importId: 'tokyo.ac.jp_imp-001',
          appliedDays: 12,
          pushedCount: 28,
        );
  }

  @override
  Future<RevertResult> revertImport({required String importId}) async {
    revertCalls++;
    if (revertError != null) throw revertError!;
    return revertToReturn ??
        const RevertResult(success: true, restoredDaysCount: 12);
  }
}

TimetableImportPreview _samplePreview({
  int removed = 1,
  bool usedAi = true,
  String mode = 'merge',
}) {
  return TimetableImportPreview(
    draftId: 'tokyo.ac.jp_draft-42',
    expiresAt: DateTime.utc(2026, 6, 1, 12, 30),
    mode: mode,
    grade: 1,
    course: '農業',
    parseMethod: usedAi ? ParseMethod.ai : ParseMethod.headerMapper,
    usedAi: usedAi,
    maskedPreviewText:
        '月曜 1限 数学 [PERSON_1]\n火曜 2限 英語 [PERSON_2]',
    diff: ImportDiff(
      summary: ImportDiffSummary(
        added: 2,
        changed: 1,
        removed: removed,
        unchanged: 4,
      ),
      preview: [
        const ImportDiffItem(
          date: '2026-06-01',
          weekday: '月',
          period: '1',
          kind: DiffKind.added,
          after: SchoolSlot(
            period: '1',
            subject: '数学I',
            teacher: '田中',
            room: '101',
            note: '',
            status: SchoolSlotStatus.normal,
          ),
        ),
        const ImportDiffItem(
          date: '2026-06-02',
          weekday: '火',
          period: '2',
          kind: DiffKind.changed,
          before: SchoolSlot(
            period: '2',
            subject: '英語I',
            teacher: '佐藤',
            room: '102',
            note: '',
            status: SchoolSlotStatus.normal,
          ),
          after: SchoolSlot(
            period: '2',
            subject: '英語II',
            teacher: '佐藤',
            room: '204',
            note: '',
            status: SchoolSlotStatus.normal,
          ),
        ),
        if (removed > 0)
          const ImportDiffItem(
            date: '2026-06-03',
            weekday: '水',
            period: '3',
            kind: DiffKind.removed,
            before: SchoolSlot(
              period: '3',
              subject: '物理基礎',
              teacher: '鈴木',
              room: '理科室',
              note: '',
              status: SchoolSlotStatus.normal,
            ),
          ),
        const ImportDiffItem(
          date: '2026-06-04',
          weekday: '木',
          period: '4',
          kind: DiffKind.unchanged,
          before: SchoolSlot(
            period: '4',
            subject: '現代文',
            teacher: '高橋',
            room: '101',
            note: '',
            status: SchoolSlotStatus.normal,
          ),
          after: SchoolSlot(
            period: '4',
            subject: '現代文',
            teacher: '高橋',
            room: '101',
            note: '',
            status: SchoolSlotStatus.normal,
          ),
        ),
      ],
    ),
    changedDaysCount: 3,
    excludedDates: const [
      ExcludedDate(
        date: '2028-03-20',
        reason: ExcludedDateReason.holiday,
        label: '春分の日',
        provisional: true,
      ),
      ExcludedDate(
        date: '2026-06-07',
        reason: ExcludedDateReason.nonSchoolDay,
        label: '日',
        provisional: false,
      ),
    ],
    invalidRows: const [
      InvalidRow(rowNumber: 14, reason: 'Invalid period: 9', rawText: '9限 体育'),
    ],
    notifyStudentsDefault: true,
  );
}

const _testSchool = SchoolInfo(
  domain: 'tokyo.ac.jp',
  name: '東京農業高校',
  periods: [
    SchoolPeriod(key: '1', label: '1限', start: (9, 0), end: (10, 30)),
    SchoolPeriod(key: '2', label: '2限', start: (10, 40), end: (12, 10)),
    SchoolPeriod(key: '3', label: '3限', start: (13, 0), end: (14, 30)),
    SchoolPeriod(key: '4', label: '4限', start: (14, 40), end: (16, 10)),
  ],
  grades: [1, 2, 3],
  courses: ['農業', '観光'],
  admins: ['admin_uid'],
  teachers: ['admin@tokyo.ac.jp', 'homeroom@tokyo.ac.jp', 'regular@tokyo.ac.jp'],
  teacherProfiles: {
    'homeroom@tokyo.ac.jp': TeacherProfile(
      name: '担任先生',
      homeroomGrade: 1,
      homeroomCourse: '農業',
    ),
    'regular@tokyo.ac.jp': TeacherProfile(name: '一般先生'),
  },
  policy: SchoolPolicy(
    allowedImporters: 'homeroom_and_admins',
    replaceMode: 'admins_only',
    notifyStudentsDefault: true,
    undoWindowDays: 7,
  ),
);

UserModel _makeUser(String uid, String email, {String name = 'Teacher'}) =>
    UserModel(
      uid: uid,
      name: name,
      email: email,
      createdAt: DateTime(2026, 1, 1),
    );

Widget _buildHarness({
  required _FakeRepo repo,
  required UserModel user,
  ({bool teacher, bool admin}) role = const (teacher: true, admin: true),
  SchoolInfo? school = _testSchool,
  bool canImport = true,
  Future<PickedImportFile?> Function()? filePickerOverride,
  Widget? child,
  Key? captureKey,
}) {
  final target = child ??
      TimetableImportScreen(filePickerOverride: filePickerOverride);
  final wrapped = captureKey != null
      ? RepaintBoundary(key: captureKey, child: target)
      : target;

  return ProviderScope(
    overrides: [
      timetableImportRepositoryProvider.overrideWithValue(repo),
      currentUserProvider.overrideWithValue(user),
      schoolDomainProvider.overrideWithValue(null),
      schoolInfoProvider.overrideWith((_) => Stream.value(school)),
      schoolRoleProvider.overrideWithValue(role),
      canImportTimetableProvider.overrideWithValue(canImport),
      todayProvider.overrideWith((_) => Stream.value(DateTime(2026, 6, 1))),
      minuteTickProvider
          .overrideWith((_) => Stream.value(DateTime(2026, 6, 1, 10, 0))),
      weekChangesProvider.overrideWithValue(const WeekChangesSummary()),
      myNoticesReadSummaryProvider
          .overrideWithValue(const NoticesReadSummary()),
      todayTeacherLessonsProgressProvider
          .overrideWithValue((total: 4, done: 1, progress: 0.25)),
    ],
    child: ToastificationWrapper(
      child: MaterialApp(
        theme: ThemeData(
          brightness: Brightness.dark,
          fontFamily: 'Plus Jakarta Sans',
          fontFamilyFallback: const ['NotoSansJP'],
        ),
        home: wrapped,
      ),
    ),
  );
}

void _setViewport(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _loadAppFontsForScreenshots() async {
  Future<void> loadFamily(String family, List<String> paths) async {
    final loader = FontLoader(family);
    for (final p in paths) {
      final bytes = await File(p).readAsBytes();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  }

  await loadFamily('Plus Jakarta Sans', [
    'assets/fonts/PlusJakartaSans-Regular.ttf',
    'assets/fonts/PlusJakartaSans-SemiBold.ttf',
    'assets/fonts/PlusJakartaSans-Bold.ttf',
    'assets/fonts/PlusJakartaSans-ExtraBold.ttf',
  ]);
  await loadFamily('NotoSansJP', [
    'assets/fonts/NotoSansJP-Regular.ttf',
    'assets/fonts/NotoSansJP-Bold.ttf',
  ]);
}

Future<void> _captureBoundaryToFile(
    WidgetTester tester, Key key, String outPath) async {
  final boundary =
      tester.renderObject(find.byKey(key)) as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: 1.0);
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  final file = File(outPath);
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(byteData!.buffer.asUint8List());
}

void main() {
  setUp(() async {
    AppColors.applyBrightness(Brightness.dark);
    SharedPreferences.setMockInitialValues({});
    await AppStrings.load('ja');
  });

  group('TimetableImportScreen responsive layout & preview features', () {
    testWidgets('Desktop (>=1100) renders 2-pane layout with diff, provisional holiday, invalid rows & AI masked toggle',
        (tester) async {
      _setViewport(tester, const Size(1280, 800));
      final repo = _FakeRepo()..previewToReturn = _samplePreview(removed: 1);

      await tester.pumpWidget(
        _buildHarness(
          repo: repo,
          user: _makeUser('admin_uid', 'admin@tokyo.ac.jp', name: '管理者'),
          filePickerOverride: () async => (
            name: 'schedule.pdf',
            readBytes: () async => Uint8List.fromList([1, 2, 3]),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Desktop shows config card & idle guide simultaneously side by side
      expect(find.text(AppStrings.t('tt_import_config_title')), findsOneWidget);
      expect(find.text(AppStrings.t('tt_import_idle_title')), findsOneWidget);

      // Pick file
      await tester.tap(find.byKey(const Key('pick_import_file_button')));
      await tester.pumpAndSettle();

      // Preview loaded
      expect(find.text(AppStrings.t('tt_import_preview_title')), findsOneWidget);
      // Icon + text label for all 4 diff kinds
      expect(find.textContaining(AppStrings.t('tt_import_diff_added')), findsWidgets);
      expect(find.textContaining(AppStrings.t('tt_import_diff_changed')), findsWidgets);
      expect(find.textContaining(AppStrings.t('tt_import_diff_removed')), findsWidgets);
      expect(find.textContaining(AppStrings.t('tt_import_diff_unchanged')), findsWidgets);

      // Provisional badge on 2028-03-20 equinox
      expect(find.text('2028-03-20'), findsOneWidget);
      expect(find.text(AppStrings.t('tt_import_provisional')), findsOneWidget);

      // Invalid rows section
      expect(find.textContaining('Invalid period: 9'), findsOneWidget);

      // AI badge + masked text toggle
      expect(find.text(AppStrings.t('tt_import_used_ai_badge')), findsOneWidget);
      expect(find.textContaining('[PERSON_1]'), findsNothing);
      await tester.tap(find.byKey(const Key('toggle_masked_preview_button')));
      await tester.pumpAndSettle();
      expect(find.textContaining('[PERSON_1]'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Mobile (<1100) renders single-column layout without overflow',
        (tester) async {
      _setViewport(tester, const Size(390, 844));
      final repo = _FakeRepo()..previewToReturn = _samplePreview(removed: 0);

      await tester.pumpWidget(
        _buildHarness(
          repo: repo,
          user: _makeUser('admin_uid', 'admin@tokyo.ac.jp', name: '管理者'),
          filePickerOverride: () async => (
            name: 'schedule.csv',
            readBytes: () async => Uint8List.fromList([1, 2, 3]),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('pick_import_file_button')));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.t('tt_import_preview_title')), findsOneWidget);
      expect(find.text('2028-03-20'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Destructive guard & Enter shortcut blocking', () {
    testWidgets('removed > 0 opens 2nd confirmation dialog; Enter key does NOT confirm while tap DOES confirm',
        (tester) async {
      _setViewport(tester, const Size(1280, 900));
      final repo = _FakeRepo()..previewToReturn = _samplePreview(removed: 3);

      await tester.pumpWidget(
        _buildHarness(
          repo: repo,
          user: _makeUser('admin_uid', 'admin@tokyo.ac.jp', name: '管理者'),
          filePickerOverride: () async => (
            name: 'schedule.csv',
            readBytes: () async => Uint8List.fromList([1, 2, 3]),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('pick_import_file_button')));
      await tester.pumpAndSettle();

      // Tap Confirm -> opens 2nd confirmation dialog instead of calling confirmImport directly
      await tester.ensureVisible(find.byKey(const Key('import_confirm_button')));
      await tester.tap(find.byKey(const Key('import_confirm_button')));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.t('tt_import_destructive_title')), findsOneWidget);
      expect(
        find.text(AppStrings.t('tt_import_destructive_body', {'n': 3})),
        findsOneWidget,
      );
      expect(repo.confirmCalls, 0);

      // Press Enter & NumpadEnter -> MUST NOT confirm!
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.numpadEnter);
      await tester.pumpAndSettle();
      expect(repo.confirmCalls, 0);
      expect(find.text(AppStrings.t('tt_import_destructive_title')), findsOneWidget);

      // Explicit click/tap on destructive confirm button -> DOES confirm!
      await tester.tap(find.byKey(const Key('destructive_confirm_button')));
      await tester.pumpAndSettle();
      expect(repo.confirmCalls, 1);
      expect(find.text(AppStrings.t('tt_import_done_title')), findsOneWidget);
    });
  });

  group('Keyboard shortcuts, Undo, and Error next-steps', () {
    testWidgets('Ctrl+I picks file and Esc cancels preview back to idle',
        (tester) async {
      _setViewport(tester, const Size(1280, 800));
      final repo = _FakeRepo()..previewToReturn = _samplePreview(removed: 0);
      var pickCount = 0;

      await tester.pumpWidget(
        _buildHarness(
          repo: repo,
          user: _makeUser('admin_uid', 'admin@tokyo.ac.jp', name: '管理者'),
          filePickerOverride: () async {
            pickCount++;
            return (
              name: 'shortcut.xlsx',
              readBytes: () async => Uint8List.fromList([1, 2, 3]),
            );
          },
        ),
      );
      await tester.pumpAndSettle();

      // Ctrl+I triggers file picker
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyI);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      expect(pickCount, 1);
      expect(find.text(AppStrings.t('tt_import_preview_title')), findsOneWidget);

      // Esc cancels preview back to idle
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.t('tt_import_idle_title')), findsOneWidget);
    });

    testWidgets('Done card shows remaining undo window and Undo button reverts import',
        (tester) async {
      _setViewport(tester, const Size(1280, 900));
      final repo = _FakeRepo()..previewToReturn = _samplePreview(removed: 0);

      await tester.pumpWidget(
        _buildHarness(
          repo: repo,
          user: _makeUser('admin_uid', 'admin@tokyo.ac.jp', name: '管理者'),
          filePickerOverride: () async => (
            name: 'merge.csv',
            readBytes: () async => Uint8List.fromList([1, 2, 3]),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('pick_import_file_button')));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(const Key('import_confirm_button')));
      await tester.tap(find.byKey(const Key('import_confirm_button')));
      await tester.pumpAndSettle();

      expect(repo.confirmCalls, 1);
      expect(find.text(AppStrings.t('tt_import_done_title')), findsOneWidget);
      expect(find.byKey(const Key('import_undo_button')), findsOneWidget);

      await tester.tap(find.byKey(const Key('import_undo_button')));
      await tester.pumpAndSettle();

      expect(repo.revertCalls, 1);
      expect(find.text(AppStrings.t('tt_import_undone_title')), findsOneWidget);
    });

    testWidgets('Error card shows actionable next step for ScannedPdfFailure, and conflict keeps preview',
        (tester) async {
      _setViewport(tester, const Size(1280, 900));
      final repo = _FakeRepo()
        ..previewError = const ScannedPdfFailure(
          'Scanned PDF detected',
          serverReason: 'scanned_pdf',
        );

      await tester.pumpWidget(
        _buildHarness(
          repo: repo,
          user: _makeUser('admin_uid', 'admin@tokyo.ac.jp', name: '管理者'),
          filePickerOverride: () async => (
            name: 'scan.pdf',
            readBytes: () async => Uint8List.fromList([1, 2, 3]),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('pick_import_file_button')));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.t('tt_import_error_title')), findsOneWidget);
      expect(find.text(AppStrings.t('tt_import_err_next_scanned_pdf')), findsOneWidget);

      // Now return a valid preview, then fail confirm with TimetableChangedFailure
      repo.previewError = null;
      repo.previewToReturn = _samplePreview(removed: 0);
      repo.confirmError = const TimetableChangedFailure(
        'Changed concurrently',
        serverReason: 'timetable_changed',
      );

      await tester.tap(find.text(AppStrings.t('tt_import_reselect_file')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('import_confirm_button')));
      await tester.tap(find.byKey(const Key('import_confirm_button')));
      await tester.pumpAndSettle();

      // Stays on preview screen with conflict guidance banner
      expect(find.text(AppStrings.t('tt_import_preview_title')), findsOneWidget);
      expect(find.text(AppStrings.t('tt_import_err_next_timetable_changed')), findsOneWidget);
    });
  });

  group('TeacherScreen import button gating', () {
    testWidgets('hides import button when canImportTimetableProvider is false and shows when true',
        (tester) async {
      _setViewport(tester, const Size(1280, 800));
      final repo = _FakeRepo();

      await tester.pumpWidget(
        _buildHarness(
          repo: repo,
          user: _makeUser('regular_uid', 'regular@tokyo.ac.jp', name: '一般先生'),
          role: const (teacher: true, admin: false),
          canImport: false,
          child: const TeacherScreen(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('open_timetable_import_button')), findsNothing);

      await tester.pumpWidget(
        _buildHarness(
          repo: repo,
          user: _makeUser('admin_uid', 'admin@tokyo.ac.jp', name: '管理者'),
          role: const (teacher: true, admin: true),
          canImport: true,
          child: const TeacherScreen(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('open_timetable_import_button')), findsOneWidget);
    });
  });

  if (Platform.environment['CAPTURE_SCREENSHOTS'] == '1') {
    testWidgets('capture Desktop and Mobile preview screenshots', (tester) async {
      await tester.runAsync(_loadAppFontsForScreenshots);

      final repo = _FakeRepo()..previewToReturn = _samplePreview(removed: 1);
      final user = _makeUser('admin_uid', 'admin@tokyo.ac.jp', name: '田中 管理者');

      // 1) Desktop (1280x800)
      _setViewport(tester, const Size(1280, 800));
      const desktopKey = Key('capture_desktop');
      await tester.pumpWidget(
        _buildHarness(
          repo: repo,
          user: user,
          captureKey: desktopKey,
          filePickerOverride: () async => (
            name: '2026_1年農業_時間割.pdf',
            readBytes: () async => Uint8List.fromList([1, 2, 3]),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pick_import_file_button')));
      await tester.pumpAndSettle();
      await tester.runAsync(() => _captureBoundaryToFile(
            tester,
            desktopKey,
            '/home/yashiloyceo/.gemini/antigravity-acp/brain/fa3ee847-cbc8-433e-9406-5ef0313467c5/scratch/import_preview_desktop.png',
          ));

      // 2) Mobile (390x844) — fresh ProviderScope key so state starts at idle
      _setViewport(tester, const Size(390, 844));
      const mobileKey = Key('capture_mobile');
      await tester.pumpWidget(
        KeyedSubtree(
          key: const Key('mobile_capture_scope'),
          child: _buildHarness(
            repo: repo,
            user: user,
            captureKey: mobileKey,
            filePickerOverride: () async => (
              name: '2026_1年農業_時間割.pdf',
              readBytes: () async => Uint8List.fromList([1, 2, 3]),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('pick_import_file_button')));
      await tester.tap(find.byKey(const Key('pick_import_file_button')));
      await tester.pumpAndSettle();
      await tester.runAsync(() => _captureBoundaryToFile(
            tester,
            mobileKey,
            '/home/yashiloyceo/.gemini/antigravity-acp/brain/fa3ee847-cbc8-433e-9406-5ef0313467c5/scratch/import_preview_mobile.png',
          ));
    });
  }
}
