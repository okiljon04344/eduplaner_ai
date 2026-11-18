import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:edu_planner_ai/features/school/models/school.dart';
import 'package:edu_planner_ai/features/school/school_providers.dart';
import 'package:edu_planner_ai/features/timetable/models/timetable_import_failure.dart';
import 'package:edu_planner_ai/features/timetable/models/timetable_import_models.dart';
import 'package:edu_planner_ai/features/timetable/providers/timetable_import_provider.dart';
import 'package:edu_planner_ai/features/timetable/repositories/timetable_import_repository.dart';

class FakeTimetableImportRepository implements TimetableImportRepository {
  TimetableImportPreview? previewToReturn;
  ImportResult? resultToReturn;
  RevertResult? revertResultToReturn;
  Object? errorToThrow;

  int previewCallCount = 0;
  int confirmCallCount = 0;
  int revertCallCount = 0;

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
    previewCallCount++;
    if (errorToThrow != null) throw errorToThrow!;
    return previewToReturn ??
        const TimetableImportPreview(
          draftId: 'test-draft',
          diff: ImportDiff(),
          changedDaysCount: 1,
        );
  }

  @override
  Future<ImportResult> confirmImport({
    required String draftId,
    required bool notifyStudents,
    String? pushSummary,
  }) async {
    confirmCallCount++;
    if (errorToThrow != null) throw errorToThrow!;
    return resultToReturn ??
        const ImportResult(
          importId: 'test-import',
          appliedDays: 1,
        );
  }

  @override
  Future<RevertResult> revertImport({required String importId}) async {
    revertCallCount++;
    if (errorToThrow != null) throw errorToThrow!;
    return revertResultToReturn ??
        const RevertResult(
          success: true,
          restoredDaysCount: 1,
        );
  }
}

void main() {
  late FakeTimetableImportRepository fakeRepo;
  late ProviderContainer container;

  setUp(() {
    fakeRepo = FakeTimetableImportRepository();
    container = ProviderContainer(
      overrides: [
        timetableImportRepositoryProvider.overrideWithValue(fakeRepo),
        schoolPolicyProvider.overrideWithValue(
          const SchoolPolicy(
            notifyStudentsDefault: true,
            replaceMode: 'admins_only',
            undoWindowDays: 7,
          ),
        ),
      ],
    );
  });

  tearDown(() {
    container.dispose();
  });

  test('initial state reads notifyStudents default and undoWindowDays from policy', () {
    final state = container.read(timetableImportProvider);
    expect(state.step, TimetableImportStep.idle);
    expect(state.notifyStudents, true);
    expect(state.undoWindowDays, 7);
    expect(state.preview, isNull);
    expect(state.fileBytes, isNull);
    expect(state.error, isNull);
  });

  test('setParams updates configuration immutably', () {
    final notifier = container.read(timetableImportProvider.notifier);
    notifier.setParams(
      grade: 2,
      course: '農業',
      mode: 'replace',
      startDate: '2026-06-01',
      endDate: '2026-06-30',
      notifyStudents: false,
    );

    final state = container.read(timetableImportProvider);
    expect(state.grade, 2);
    expect(state.course, '農業');
    expect(state.mode, 'replace');
    expect(state.startDate, '2026-06-01');
    expect(state.endDate, '2026-06-30');
    expect(state.notifyStudents, false);
  });

  test('cancel clears buffered file bytes, preview, and resets to idle', () async {
    final notifier = container.read(timetableImportProvider.notifier);
    fakeRepo.previewToReturn = const TimetableImportPreview(
      draftId: 'draft-xyz',
      diff: ImportDiff(),
      changedDaysCount: 2,
    );

    await notifier.previewFromBytes(
      fileName: 'test.csv',
      bytes: Uint8List.fromList([1, 2, 3]),
    );

    var state = container.read(timetableImportProvider);
    expect(state.step, TimetableImportStep.preview);
    expect(state.preview?.draftId, 'draft-xyz');
    expect(state.fileBytes, isNotNull);

    notifier.cancel();

    state = container.read(timetableImportProvider);
    expect(state.step, TimetableImportStep.idle);
    expect(state.preview, isNull);
    expect(state.fileBytes, isNull);
    expect(state.fileName, isNull);
    expect(state.error, isNull);
  });

  test('pickAndPreviewFile user cancels file picker returns to idle', () async {
    final notifier = container.read(timetableImportProvider.notifier);
    await notifier.pickAndPreviewFile(
      filePicker: () async => null,
    );

    final state = container.read(timetableImportProvider);
    expect(state.step, TimetableImportStep.idle);
    expect(fakeRepo.previewCallCount, 0);
  });

  test('pickAndPreviewFile successful cycle transitions to preview', () async {
    final notifier = container.read(timetableImportProvider.notifier);
    fakeRepo.previewToReturn = const TimetableImportPreview(
      draftId: 'draft-abc',
      diff: ImportDiff(),
      changedDaysCount: 5,
      parseMethod: ParseMethod.headerMapper,
    );

    final bytes = Uint8List.fromList([10, 20, 30]);
    await notifier.pickAndPreviewFile(
      filePicker: () async => (
        name: 'import.xlsx',
        readBytes: () async => bytes,
      ),
    );

    final state = container.read(timetableImportProvider);
    expect(state.step, TimetableImportStep.preview);
    expect(state.preview?.draftId, 'draft-abc');
    expect(state.preview?.parseMethod, ParseMethod.headerMapper);
    expect(state.fileName, 'import.xlsx');
    expect(state.fileBytes, bytes);
    expect(fakeRepo.previewCallCount, 1);
  });

  test('pickAndPreviewFile rejects HEIC on Desktop/Web BEFORE calling repository', () async {
    final notifier = container.read(timetableImportProvider.notifier);
    await notifier.previewFromBytes(
      fileName: 'schedule.heic',
      bytes: Uint8List.fromList([1, 2, 3]),
      supportsClientHeicConversion: false,
    );

    final state = container.read(timetableImportProvider);
    expect(state.step, TimetableImportStep.error);
    expect(state.error, isA<UnsupportedHeicFailure>());
    expect(fakeRepo.previewCallCount, 0);
  });

  test('pickAndPreviewFile failure transitions to error with typed exception', () async {
    final notifier = container.read(timetableImportProvider.notifier);
    fakeRepo.errorToThrow = const ScannedPdfFailure(
      'Scanned PDF',
      serverReason: 'scanned_pdf',
    );

    await notifier.previewFromBytes(
      fileName: 'scanned.pdf',
      bytes: Uint8List.fromList([1, 2, 3]),
    );

    final state = container.read(timetableImportProvider);
    expect(state.step, TimetableImportStep.error);
    expect(state.error, isA<ScannedPdfFailure>());
    expect(state.preview, isNull);
  });

  test('confirmImport success transitions to done, sets confirmedAt, and clears buffered file bytes', () async {
    final notifier = container.read(timetableImportProvider.notifier);
    fakeRepo.previewToReturn = const TimetableImportPreview(
      draftId: 'draft-done',
      diff: ImportDiff(),
      changedDaysCount: 3,
    );
    fakeRepo.resultToReturn = const ImportResult(
      importId: 'import-777',
      appliedDays: 3,
      pushedCount: 12,
    );

    await notifier.previewFromBytes(
      fileName: 'classes.csv',
      bytes: Uint8List.fromList([1, 2, 3]),
    );

    expect(container.read(timetableImportProvider).step, TimetableImportStep.preview);
    expect(container.read(timetableImportProvider).fileBytes, isNotNull);

    await notifier.confirmImport(pushSummary: 'Updated 3 days');

    final state = container.read(timetableImportProvider);
    expect(state.step, TimetableImportStep.done);
    expect(state.result?.importId, 'import-777');
    expect(state.result?.appliedDays, 3);
    expect(state.result?.pushedCount, 12);
    expect(state.confirmedAt, isNotNull);
    expect(state.canUndo, true);
    expect(state.undoRemaining(state.confirmedAt!), const Duration(days: 7));
    // Buffered file bytes cleared on done
    expect(state.fileBytes, isNull);
  });

  test('confirmImport on timetable_changed conflict returns to preview with error set', () async {
    final notifier = container.read(timetableImportProvider.notifier);
    fakeRepo.previewToReturn = const TimetableImportPreview(
      draftId: 'draft-conflict',
      diff: ImportDiff(),
      changedDaysCount: 2,
    );

    await notifier.previewFromBytes(
      fileName: 'classes.csv',
      bytes: Uint8List.fromList([1, 2, 3]),
    );

    expect(container.read(timetableImportProvider).step, TimetableImportStep.preview);

    // Simulate concurrent modification by another teacher
    fakeRepo.errorToThrow = const TimetableChangedFailure(
      'Timetable was modified concurrently',
      serverReason: 'timetable_changed',
    );

    await notifier.confirmImport();

    final state = container.read(timetableImportProvider);
    // Crucial requirement: returns to preview step so user context & preview are preserved!
    expect(state.step, TimetableImportStep.preview);
    expect(state.preview?.draftId, 'draft-conflict');
    expect(state.error, isA<TimetableChangedFailure>());
  });

  test('confirmImport on other failure transitions to error', () async {
    final notifier = container.read(timetableImportProvider.notifier);
    fakeRepo.previewToReturn = const TimetableImportPreview(
      draftId: 'draft-expired',
      diff: ImportDiff(),
      changedDaysCount: 1,
    );

    await notifier.previewFromBytes(
      fileName: 'classes.csv',
      bytes: Uint8List.fromList([1, 2, 3]),
    );

    fakeRepo.errorToThrow = const DraftExpiredFailure(
      'Draft expired',
      serverReason: 'draft_expired_or_not_found',
    );

    await notifier.confirmImport();

    final state = container.read(timetableImportProvider);
    expect(state.step, TimetableImportStep.error);
    expect(state.error, isA<DraftExpiredFailure>());
  });

  test('toggleMaskedPreview toggles showMaskedPreview', () {
    final notifier = container.read(timetableImportProvider.notifier);
    expect(container.read(timetableImportProvider).showMaskedPreview, false);
    notifier.toggleMaskedPreview();
    expect(container.read(timetableImportProvider).showMaskedPreview, true);
    notifier.toggleMaskedPreview();
    expect(container.read(timetableImportProvider).showMaskedPreview, false);
  });

  test('revertCurrentImport reverts confirmed import and updates state', () async {
    final notifier = container.read(timetableImportProvider.notifier);
    fakeRepo.previewToReturn = const TimetableImportPreview(
      draftId: 'draft-undo',
      diff: ImportDiff(),
      changedDaysCount: 2,
    );
    fakeRepo.resultToReturn = const ImportResult(
      importId: 'import-undo',
      appliedDays: 2,
    );
    fakeRepo.revertResultToReturn = const RevertResult(
      success: true,
      restoredDaysCount: 2,
    );

    await notifier.previewFromBytes(
      fileName: 'classes.csv',
      bytes: Uint8List.fromList([1, 2, 3]),
    );
    await notifier.confirmImport();
    expect(container.read(timetableImportProvider).canUndo, true);

    final res = await notifier.revertCurrentImport();
    expect(res?.success, true);
    expect(res?.restoredDaysCount, 2);

    final state = container.read(timetableImportProvider);
    expect(state.revertResult?.restoredDaysCount, 2);
    expect(state.canUndo, false);
    expect(fakeRepo.revertCallCount, 1);
  });

  test('revertImport calls repository and returns result', () async {
    final notifier = container.read(timetableImportProvider.notifier);
    fakeRepo.revertResultToReturn = const RevertResult(
      success: true,
      restoredDaysCount: 8,
    );

    final res = await notifier.revertImport('import-xyz');
    expect(res.success, true);
    expect(res.restoredDaysCount, 8);
    expect(fakeRepo.revertCallCount, 1);
  });
}
