import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../school/school_providers.dart';
import '../models/timetable_import_failure.dart';
import '../models/timetable_import_models.dart';
import '../repositories/timetable_import_file_helper.dart';
import '../repositories/timetable_import_repository.dart';

/// Progress steps of the timetable import flow.
enum TimetableImportStep {
  idle,
  picking,
  uploading,
  preview,
  confirming,
  done,
  error,
}

typedef PickedImportFile = ({
  String name,
  Future<Uint8List> Function() readBytes,
});

/// Default file picker using the system file picker dialog.
Future<PickedImportFile?> defaultPickImportFile() async {
  final allowed = isClientHeicConversionSupported
      ? const [
          'xlsx',
          'csv',
          'pdf',
          'jpg',
          'jpeg',
          'png',
          'webp',
          'heic',
          'heif',
        ]
      : const [
          'xlsx',
          'csv',
          'pdf',
          'jpg',
          'jpeg',
          'png',
          'webp',
        ];
  final file = await FilePicker.pickFile(
    type: FileType.custom,
    allowedExtensions: allowed,
  );
  if (file == null) return null;
  return (
    name: file.name,
    readBytes: file.readAsBytes,
  );
}

/// Immutable state holding the timetable import wizard status, inputs, and results.
@immutable
class TimetableImportState {
  final TimetableImportStep step;
  final TimetableImportPreview? preview;
  final ImportResult? result;
  final RevertResult? revertResult;
  final TimetableImportFailure? error;
  final DateTime? confirmedAt;
  final int undoWindowDays;
  final bool reverting;
  final bool showMaskedPreview;

  // Selected parameters
  final int? grade;
  final String? course;
  final String mode; // 'merge' | 'replace'
  final String? startDate;
  final String? endDate;
  final bool includeNonSchoolDays;
  final bool notifyStudents;

  // Buffered file info (cleared on cancel and dispose)
  final String? fileName;
  final String? mimeType;
  final Uint8List? fileBytes;

  const TimetableImportState({
    this.step = TimetableImportStep.idle,
    this.preview,
    this.result,
    this.revertResult,
    this.error,
    this.confirmedAt,
    this.undoWindowDays = 7,
    this.reverting = false,
    this.showMaskedPreview = false,
    this.grade,
    this.course,
    this.mode = 'merge',
    this.startDate,
    this.endDate,
    this.includeNonSchoolDays = false,
    this.notifyStudents = false,
    this.fileName,
    this.mimeType,
    this.fileBytes,
  });

  bool get canUndo =>
      step == TimetableImportStep.done &&
      result?.importId != null &&
      result!.importId!.isNotEmpty &&
      revertResult == null;

  Duration? undoRemaining(DateTime now) {
    final at = confirmedAt;
    if (at == null) return null;
    final expires = at.add(Duration(days: undoWindowDays));
    final diff = expires.difference(now);
    return diff.isNegative ? Duration.zero : diff;
  }

  TimetableImportState copyWith({
    TimetableImportStep? step,
    TimetableImportPreview? preview,
    bool clearPreview = false,
    ImportResult? result,
    bool clearResult = false,
    RevertResult? revertResult,
    bool clearRevertResult = false,
    TimetableImportFailure? error,
    bool clearError = false,
    DateTime? confirmedAt,
    bool clearConfirmedAt = false,
    int? undoWindowDays,
    bool? reverting,
    bool? showMaskedPreview,
    int? grade,
    String? course,
    bool clearCourse = false,
    String? mode,
    String? startDate,
    String? endDate,
    bool? includeNonSchoolDays,
    bool? notifyStudents,
    String? fileName,
    String? mimeType,
    Uint8List? fileBytes,
    bool clearFile = false,
  }) {
    return TimetableImportState(
      step: step ?? this.step,
      preview: clearPreview ? null : (preview ?? this.preview),
      result: clearResult ? null : (result ?? this.result),
      revertResult:
          clearRevertResult ? null : (revertResult ?? this.revertResult),
      error: clearError ? null : (error ?? this.error),
      confirmedAt: clearConfirmedAt ? null : (confirmedAt ?? this.confirmedAt),
      undoWindowDays: undoWindowDays ?? this.undoWindowDays,
      reverting: reverting ?? this.reverting,
      showMaskedPreview: showMaskedPreview ?? this.showMaskedPreview,
      grade: grade ?? this.grade,
      course: clearCourse ? null : (course ?? this.course),
      mode: mode ?? this.mode,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      includeNonSchoolDays: includeNonSchoolDays ?? this.includeNonSchoolDays,
      notifyStudents: notifyStudents ?? this.notifyStudents,
      fileName: clearFile ? null : (fileName ?? this.fileName),
      mimeType: clearFile ? null : (mimeType ?? this.mimeType),
      fileBytes: clearFile ? null : (fileBytes ?? this.fileBytes),
    );
  }
}

/// Auto-disposing notifier for timetable import operations.
///
/// Ensures zero UI setState, memory safety by clearing buffers on cancel
/// or dispose, and seamless return to preview on concurrent edits.
class TimetableImportNotifier extends AutoDisposeNotifier<TimetableImportState> {
  @override
  TimetableImportState build() {
    ref.onDispose(() {
      _clearBuffers();
    });

    final policy = ref.watch(schoolPolicyProvider);
    return TimetableImportState(
      notifyStudents: policy.notifyStudentsDefault,
      undoWindowDays: policy.undoWindowDays,
    );
  }

  void _clearBuffers() {
    // References cleared when provider is disposed.
  }

  /// Updates user parameters (grade, course, mode, dates, push toggle).
  void setParams({
    int? grade,
    String? course,
    bool clearCourse = false,
    String? mode,
    String? startDate,
    String? endDate,
    bool? includeNonSchoolDays,
    bool? notifyStudents,
  }) {
    state = state.copyWith(
      grade: grade,
      course: course,
      clearCourse: clearCourse,
      mode: mode,
      startDate: startDate,
      endDate: endDate,
      includeNonSchoolDays: includeNonSchoolDays,
      notifyStudents: notifyStudents,
    );
  }

  void toggleMaskedPreview() {
    state = state.copyWith(showMaskedPreview: !state.showMaskedPreview);
  }

  /// Cancels the current import flow, clearing all loaded bytes and preview data.
  void cancel() {
    state = state.copyWith(
      step: TimetableImportStep.idle,
      clearPreview: true,
      clearResult: true,
      clearRevertResult: true,
      clearConfirmedAt: true,
      clearError: true,
      clearFile: true,
      showMaskedPreview: false,
    );
  }

  /// Resets back to idle state with initial parameters.
  void reset() {
    final policy = ref.read(schoolPolicyProvider);
    state = TimetableImportState(
      notifyStudents: policy.notifyStudentsDefault,
      undoWindowDays: policy.undoWindowDays,
    );
  }

  /// Picks a timetable file, runs client validations / HEIC conversion, and
  /// requests an import diff preview from Cloud Functions.
  Future<void> pickAndPreviewFile({
    PickedImportFile? prePickedFile,
    Future<PickedImportFile?> Function()? filePicker,
    HeicToJpegConverter? heicConverter,
    @visibleForTesting bool? supportsClientHeicConversion,
    int? defaultGrade,
    String? defaultCourse,
  }) async {
    state = state.copyWith(
      step: TimetableImportStep.picking,
      clearError: true,
      clearResult: true,
      clearRevertResult: true,
      clearConfirmedAt: true,
      showMaskedPreview: false,
      grade: state.grade ?? defaultGrade,
      course: state.course ?? defaultCourse,
    );

    try {
      final picked =
          prePickedFile ?? await (filePicker ?? defaultPickImportFile)();
      if (picked == null) {
        state = state.copyWith(
          step: state.preview != null
              ? TimetableImportStep.preview
              : TimetableImportStep.idle,
        );
        return;
      }

      final rawBytes = await picked.readBytes();
      final prepared = await prepareImportFile(
        rawFileName: picked.name,
        rawBytes: rawBytes,
        heicConverter: heicConverter,
        supportsClientHeicConversion: supportsClientHeicConversion,
      );

      state = state.copyWith(
        step: TimetableImportStep.uploading,
        fileName: prepared.fileName,
        mimeType: prepared.mimeType,
        fileBytes: prepared.bytes,
      );

      final now = DateTime.now();
      final defaultStart = state.startDate ??
          "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
      final endTarget = now.add(const Duration(days: 90));
      final defaultEnd = state.endDate ??
          "${endTarget.year}-${endTarget.month.toString().padLeft(2, '0')}-${endTarget.day.toString().padLeft(2, '0')}";

      final repo = ref.read(timetableImportRepositoryProvider);
      final preview = await repo.previewImport(
        grade: state.grade ?? defaultGrade ?? 1,
        course: state.course ?? defaultCourse,
        mode: state.mode,
        fileName: prepared.fileName,
        mimeType: prepared.mimeType,
        fileBytes: prepared.bytes,
        startDate: defaultStart,
        endDate: defaultEnd,
        includeNonSchoolDays: state.includeNonSchoolDays,
      );

      state = state.copyWith(
        step: TimetableImportStep.preview,
        preview: preview,
        clearError: true,
      );
    } catch (e) {
      final failure = e is TimetableImportFailure
          ? e
          : TimetableImportFailure.fromException(e);
      state = state.copyWith(
        step: TimetableImportStep.error,
        error: failure,
      );
    }
  }

  /// Directly loads preview from in-memory bytes (useful for tests or drag-and-drop).
  Future<void> previewFromBytes({
    required String fileName,
    required Uint8List bytes,
    HeicToJpegConverter? heicConverter,
    @visibleForTesting bool? supportsClientHeicConversion,
  }) async {
    return pickAndPreviewFile(
      prePickedFile: (
        name: fileName,
        readBytes: () async => bytes,
      ),
      heicConverter: heicConverter,
      supportsClientHeicConversion: supportsClientHeicConversion,
    );
  }

  /// Confirms the current draft preview and applies changes to school_days.
  ///
  /// On [TimetableChangedFailure], the step stays in [TimetableImportStep.preview]
  /// with [state.error] populated so the user does not lose their context.
  Future<void> confirmImport({String? pushSummary}) async {
    final preview = state.preview;
    if (preview == null) {
      state = state.copyWith(
        step: TimetableImportStep.error,
        error: const DraftExpiredFailure('No active import preview to confirm'),
      );
      return;
    }

    state = state.copyWith(
      step: TimetableImportStep.confirming,
      clearError: true,
    );

    try {
      final repo = ref.read(timetableImportRepositoryProvider);
      final result = await repo.confirmImport(
        draftId: preview.draftId,
        notifyStudents: state.notifyStudents,
        pushSummary: pushSummary,
      );

      state = state.copyWith(
        step: TimetableImportStep.done,
        result: result,
        confirmedAt: DateTime.now(),
        clearError: true,
        clearFile: true,
      );
    } catch (e) {
      final failure = e is TimetableImportFailure
          ? e
          : TimetableImportFailure.fromException(e);

      if (failure is TimetableChangedFailure) {
        state = state.copyWith(
          step: TimetableImportStep.preview,
          error: failure,
        );
      } else {
        state = state.copyWith(
          step: TimetableImportStep.error,
          error: failure,
        );
      }
    }
  }

  /// Reverts the just-confirmed import, updating state with [RevertResult] or error.
  Future<RevertResult?> revertCurrentImport() async {
    final importId = state.result?.importId;
    if (importId == null || importId.isEmpty || state.reverting) return null;
    state = state.copyWith(reverting: true, clearError: true);
    try {
      final repo = ref.read(timetableImportRepositoryProvider);
      final res = await repo.revertImport(importId: importId);
      state = state.copyWith(
        reverting: false,
        revertResult: res,
      );
      return res;
    } catch (e) {
      final failure = e is TimetableImportFailure
          ? e
          : TimetableImportFailure.fromException(e);
      state = state.copyWith(
        reverting: false,
        error: failure,
      );
      return null;
    }
  }

  /// Reverts a confirmed timetable import using its import history ID.
  Future<RevertResult> revertImport(String importId) async {
    try {
      final repo = ref.read(timetableImportRepositoryProvider);
      return await repo.revertImport(importId: importId);
    } catch (e) {
      throw e is TimetableImportFailure
          ? e
          : TimetableImportFailure.fromException(e);
    }
  }
}

/// Provider for timetable import state and operations.
final timetableImportProvider = AutoDisposeNotifierProvider<
    TimetableImportNotifier, TimetableImportState>(
  TimetableImportNotifier.new,
);
