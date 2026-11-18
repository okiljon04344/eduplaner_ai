import 'dart:convert';
import 'dart:io';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:edu_planner_ai/features/timetable/models/timetable_import_failure.dart';

void main() {
  FirebaseFunctionsException makeEx({
    required String code,
    String? message,
    String? reason,
  }) {
    return FirebaseFunctionsException(
      code: code,
      message: message ?? 'Failed',
      details: reason != null ? {'reason': reason} : null,
    );
  }

  group('Shared error_reasons.json parity', () {
    test('every reason code in shared/error_reasons.json maps to a specific non-Unknown failure', () {
      final raw = File('shared/error_reasons.json').readAsStringSync();
      final reasonsMap = jsonDecode(raw) as Map<String, dynamic>;
      expect(reasonsMap, isNotEmpty);

      for (final entry in reasonsMap.entries) {
        final reason = entry.value as String;
        final failure = TimetableImportFailure.fromException(
          makeEx(code: 'failed-precondition', reason: reason),
        );
        expect(
          failure,
          isNot(isA<UnknownFailure>()),
          reason: 'Reason "$reason" (${entry.key}) must map to a concrete failure subclass',
        );
        expect(failure.serverReason, reason);
      }
    });
  });

  group('TimetableImportFailure.fromException reason-specific mapping', () {
    test('scanned_pdf -> ScannedPdfFailure', () {
      final failure = TimetableImportFailure.fromException(
        makeEx(code: 'failed-precondition', reason: 'scanned_pdf'),
      );
      expect(failure, isA<ScannedPdfFailure>());
      expect(failure.serverReason, 'scanned_pdf');
    });

    test('unsupported_heic -> UnsupportedHeicFailure', () {
      final failure = TimetableImportFailure.fromException(
        makeEx(code: 'failed-precondition', reason: 'unsupported_heic'),
      );
      expect(failure, isA<UnsupportedHeicFailure>());
      expect(failure.serverReason, 'unsupported_heic');
    });

    test('sjis_unsupported_runtime -> ShiftJisUnsupportedFailure', () {
      final failure = TimetableImportFailure.fromException(
        makeEx(code: 'failed-precondition', reason: 'sjis_unsupported_runtime'),
      );
      expect(failure, isA<ShiftJisUnsupportedFailure>());
      expect(failure.serverReason, 'sjis_unsupported_runtime');
    });

    test('ocr_failed -> OcrFailedFailure', () {
      final failure = TimetableImportFailure.fromException(
        makeEx(code: 'failed-precondition', reason: 'ocr_failed'),
      );
      expect(failure, isA<OcrFailedFailure>());
      expect(failure.serverReason, 'ocr_failed');
    });

    test('timetable_changed -> TimetableChangedFailure', () {
      final failure = TimetableImportFailure.fromException(
        makeEx(code: 'aborted', reason: 'timetable_changed'),
      );
      expect(failure, isA<TimetableChangedFailure>());
      expect(failure.serverReason, 'timetable_changed');
    });

    test('policy_changed -> PolicyChangedFailure', () {
      final failure = TimetableImportFailure.fromException(
        makeEx(code: 'failed-precondition', reason: 'policy_changed'),
      );
      expect(failure, isA<PolicyChangedFailure>());
      expect(failure.serverReason, 'policy_changed');
    });

    test('policy_disallows_replace -> PolicyDisallowsReplaceFailure', () {
      final failure = TimetableImportFailure.fromException(
        makeEx(code: 'failed-precondition', reason: 'policy_disallows_replace'),
      );
      expect(failure, isA<PolicyDisallowsReplaceFailure>());
      expect(failure.serverReason, 'policy_disallows_replace');
    });

    test('invalid_date_range & range_too_large -> InvalidDateRangeFailure', () {
      final failure1 = TimetableImportFailure.fromException(
        makeEx(code: 'invalid-argument', reason: 'invalid_date_range'),
      );
      expect(failure1, isA<InvalidDateRangeFailure>());

      final failure2 = TimetableImportFailure.fromException(
        makeEx(code: 'invalid-argument', reason: 'range_too_large'),
      );
      expect(failure2, isA<InvalidDateRangeFailure>());
    });

    test('file_too_large -> FileTooLargeFailure', () {
      final failure = TimetableImportFailure.fromException(
        makeEx(code: 'invalid-argument', reason: 'file_too_large'),
      );
      expect(failure, isA<FileTooLargeFailure>());
    });

    test('draft_expired_or_not_found -> DraftExpiredFailure', () {
      final failure = TimetableImportFailure.fromException(
        makeEx(code: 'not-found', reason: 'draft_expired_or_not_found'),
      );
      expect(failure, isA<DraftExpiredFailure>());
    });

    test('undo_window_expired -> RevertWindowExpiredFailure', () {
      final failure = TimetableImportFailure.fromException(
        makeEx(code: 'failed-precondition', reason: 'undo_window_expired'),
      );
      expect(failure, isA<RevertWindowExpiredFailure>());
    });

    test('already_reverted -> AlreadyRevertedFailure', () {
      final failure = TimetableImportFailure.fromException(
        makeEx(code: 'failed-precondition', reason: 'already_reverted'),
      );
      expect(failure, isA<AlreadyRevertedFailure>());
    });

    test('ai_quota_exceeded -> QuotaExceededFailure', () {
      final failure = TimetableImportFailure.fromException(
        makeEx(code: 'resource-exhausted', reason: 'ai_quota_exceeded'),
      );
      expect(failure, isA<QuotaExceededFailure>());
    });

    test('ai_budget_exceeded -> QuotaExceededFailure with serverReason', () {
      final failure = TimetableImportFailure.fromException(
        makeEx(code: 'resource-exhausted', reason: 'ai_budget_exceeded'),
      );
      expect(failure, isA<QuotaExceededFailure>());
      expect(failure.serverReason, 'ai_budget_exceeded');
    });

    test('ai_temporarily_unavailable -> NetworkUnavailableFailure with serverReason', () {
      final failure = TimetableImportFailure.fromException(
        makeEx(code: 'unavailable', reason: 'ai_temporarily_unavailable'),
      );
      expect(failure, isA<NetworkUnavailableFailure>());
      expect(failure.serverReason, 'ai_temporarily_unavailable');
    });
  });

  group('TimetableImportFailure.fromException code-level & UnknownFailure fallback', () {
    test('permission-denied -> PermissionDeniedFailure', () {
      final failure = TimetableImportFailure.fromException(
        makeEx(code: 'permission-denied'),
      );
      expect(failure, isA<PermissionDeniedFailure>());
    });

    test('resource-exhausted -> QuotaExceededFailure', () {
      final failure = TimetableImportFailure.fromException(
        makeEx(code: 'resource-exhausted'),
      );
      expect(failure, isA<QuotaExceededFailure>());
    });

    test('not-found -> DraftExpiredFailure', () {
      final failure = TimetableImportFailure.fromException(
        makeEx(code: 'not-found'),
      );
      expect(failure, isA<DraftExpiredFailure>());
    });

    test('aborted -> TimetableChangedFailure', () {
      final failure = TimetableImportFailure.fromException(
        makeEx(code: 'aborted'),
      );
      expect(failure, isA<TimetableChangedFailure>());
    });

    test('deadline-exceeded -> TimeoutFailure', () {
      final failure = TimetableImportFailure.fromException(
        makeEx(code: 'deadline-exceeded'),
      );
      expect(failure, isA<TimeoutFailure>());
    });

    test('unavailable -> NetworkUnavailableFailure', () {
      final failure = TimetableImportFailure.fromException(
        makeEx(code: 'unavailable'),
      );
      expect(failure, isA<NetworkUnavailableFailure>());
    });

    test('unauthenticated -> UnauthenticatedFailure', () {
      final failure = TimetableImportFailure.fromException(
        makeEx(code: 'unauthenticated'),
      );
      expect(failure, isA<UnauthenticatedFailure>());
    });

    test('unknown reason & code -> UnknownFailure(reason) without throwing', () {
      final failure = TimetableImportFailure.fromException(
        makeEx(code: 'internal', reason: 'future_unrecognized_reason'),
      );
      expect(failure, isA<UnknownFailure>());
      final unk = failure as UnknownFailure;
      expect(unk.serverReason, 'future_unrecognized_reason');
      expect(unk.code, 'internal');
      expect(unk.message, isNotEmpty);
    });

    test('non-functions exception -> UnknownFailure', () {
      final failure = TimetableImportFailure.fromException(
        Exception('Generic error'),
      );
      expect(failure, isA<UnknownFailure>());
    });
  });
}
