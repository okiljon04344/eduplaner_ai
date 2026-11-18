import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/functions_service.dart';
import '../models/timetable_import_failure.dart';
import '../models/timetable_import_models.dart';

abstract class TimetableImportRepository {
  Future<TimetableImportPreview> previewImport({
    required int grade,
    required String? course,
    required String mode, // 'merge' | 'replace'
    required String fileName,
    required String mimeType,
    required Uint8List fileBytes,
    required String startDate,
    required String endDate,
    bool includeNonSchoolDays = false,
  });

  Future<ImportResult> confirmImport({
    required String draftId,
    required bool notifyStudents,
    String? pushSummary,
  });

  Future<RevertResult> revertImport({
    required String importId,
  });
}

class CloudFunctionsTimetableImportRepository implements TimetableImportRepository {
  const CloudFunctionsTimetableImportRepository();

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
    try {
      final res = await FunctionsService.callable('previewTimetableImport').call<Map>({
        'grade': grade,
        'course': course,
        'mode': mode,
        'fileName': fileName,
        'mimeType': mimeType,
        'fileBase64': base64Encode(fileBytes),
        'dateRange': {
          'start': startDate,
          'end': endDate,
        },
        'includeNonSchoolDays': includeNonSchoolDays,
      });
      return TimetableImportPreview.fromMap(res.data);
    } catch (e) {
      throw TimetableImportFailure.fromException(e);
    }
  }

  @override
  Future<ImportResult> confirmImport({
    required String draftId,
    required bool notifyStudents,
    String? pushSummary,
  }) async {
    try {
      final res = await FunctionsService.callable('confirmTimetableImport').call<Map>({
        'draftId': draftId,
        'notifyStudents': notifyStudents,
        if (pushSummary != null && pushSummary.isNotEmpty) 'pushSummary': pushSummary,
      });
      return ImportResult.fromMap(res.data);
    } catch (e) {
      throw TimetableImportFailure.fromException(e);
    }
  }

  @override
  Future<RevertResult> revertImport({
    required String importId,
  }) async {
    try {
      final res = await FunctionsService.callable('revertTimetableImport').call<Map>({
        'importId': importId,
      });
      return RevertResult.fromMap(res.data);
    } catch (e) {
      throw TimetableImportFailure.fromException(e);
    }
  }
}

final timetableImportRepositoryProvider = Provider<TimetableImportRepository>((ref) {
  return const CloudFunctionsTimetableImportRepository();
});
