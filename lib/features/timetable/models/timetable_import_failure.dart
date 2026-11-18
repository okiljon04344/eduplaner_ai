import 'package:cloud_functions/cloud_functions.dart';
import '../../../core/l10n/app_strings.dart';

/// Sealed exception hierarchy for timetable import operations.
///
/// Maps every Cloud Functions error code and `details['reason']` tag
/// to a typed domain exception so the UI and state layers can handle
/// conflicts and edge cases deterministically.
sealed class TimetableImportFailure implements Exception {
  final String message;
  final String? serverReason;

  const TimetableImportFailure(this.message, {this.serverReason});

  @override
  String toString() =>
      '$runtimeType: $message${serverReason != null ? ' (reason: $serverReason)' : ''}';

  /// Maps any caught [Object] (typically [FirebaseFunctionsException]) into
  /// a specific [TimetableImportFailure] subclass.
  factory TimetableImportFailure.fromException(Object error) {
    if (error is TimetableImportFailure) return error;

    if (error is FirebaseFunctionsException) {
      final details = error.details;
      final reason = details is Map ? details['reason']?.toString() : null;

      // 1. Reason-specific mappings (must stay in parity with shared/error_reasons.json)
      switch (reason) {
        case 'scanned_pdf':
          return ScannedPdfFailure(
            error.message ?? AppStrings.t('tt_import_err_scanned_pdf'),
            serverReason: reason,
          );
        case 'unsupported_heic':
          return UnsupportedHeicFailure(
            error.message ?? AppStrings.t('tt_import_err_unsupported_heic'),
            serverReason: reason,
          );
        case 'sjis_unsupported_runtime':
          return ShiftJisUnsupportedFailure(
            error.message ?? AppStrings.t('tt_import_err_sjis_unsupported'),
            serverReason: reason,
          );
        case 'ocr_failed':
          return OcrFailedFailure(
            error.message ?? AppStrings.t('tt_import_err_ocr_failed'),
            serverReason: reason,
          );
        case 'timetable_changed':
          return TimetableChangedFailure(
            error.message ?? AppStrings.t('tt_import_err_timetable_changed'),
            serverReason: reason,
          );
        case 'policy_changed':
          return PolicyChangedFailure(
            error.message ?? AppStrings.t('tt_import_err_policy_changed'),
            serverReason: reason,
          );
        case 'policy_disallows_replace':
          return PolicyDisallowsReplaceFailure(
            error.message ?? AppStrings.t('tt_import_err_replace_disallowed'),
            serverReason: reason,
          );
        case 'invalid_date_range':
        case 'range_too_large':
          return InvalidDateRangeFailure(
            error.message ?? AppStrings.t('tt_import_err_invalid_date_range'),
            serverReason: reason,
          );
        case 'file_too_large':
        case 'image_too_large_for_provider':
          return FileTooLargeFailure(
            error.message ?? AppStrings.t('tt_import_err_file_too_large'),
            serverReason: reason,
          );
        case 'draft_expired_or_not_found':
          return DraftExpiredFailure(
            error.message ?? AppStrings.t('tt_import_err_draft_expired'),
            serverReason: reason,
          );
        case 'undo_window_expired':
          return RevertWindowExpiredFailure(
            error.message ?? AppStrings.t('tt_import_err_undo_expired'),
            serverReason: reason,
          );
        case 'already_reverted':
          return AlreadyRevertedFailure(
            error.message ?? AppStrings.t('tt_import_err_already_reverted'),
            serverReason: reason,
          );
        case 'ai_quota_exceeded':
          return QuotaExceededFailure(
            error.message ?? AppStrings.t('err_ai_limit_reached'),
            serverReason: reason,
          );
        case 'ai_budget_exceeded':
          return QuotaExceededFailure(
            AppStrings.t('err_ai_budget_exceeded'),
            serverReason: reason,
          );
        case 'ai_temporarily_unavailable':
          return NetworkUnavailableFailure(
            AppStrings.t('err_ai_temporarily_unavailable'),
            serverReason: reason,
          );
      }

      // 2. Code-based mappings when reason is absent or unknown
      switch (error.code) {
        case 'permission-denied':
          return PermissionDeniedFailure(
            error.message ?? AppStrings.t('tt_import_err_permission_denied'),
            serverReason: reason,
          );
        case 'resource-exhausted':
          return QuotaExceededFailure(
            error.message ?? AppStrings.t('err_ai_limit_reached'),
            serverReason: reason,
          );
        case 'not-found':
          return DraftExpiredFailure(
            error.message ?? AppStrings.t('tt_import_err_draft_expired'),
            serverReason: reason,
          );
        case 'aborted':
          return TimetableChangedFailure(
            error.message ?? AppStrings.t('tt_import_err_timetable_changed'),
            serverReason: reason,
          );
        case 'deadline-exceeded':
          return TimeoutFailure(
            error.message ?? AppStrings.t('err_timeout'),
            serverReason: reason,
          );
        case 'unavailable':
          return NetworkUnavailableFailure(
            error.message ?? AppStrings.t('err_network'),
            serverReason: reason,
          );
        case 'unauthenticated':
          return UnauthenticatedFailure(
            error.message ?? AppStrings.t('err_login_required'),
            serverReason: reason,
          );
        default:
          return UnknownFailure(
            reason,
            message: AppStrings.t('tt_import_err_unknown'),
            code: error.code,
          );
      }
    }

    return UnknownFailure(
      null,
      message: AppStrings.t('tt_import_err_unknown'),
      code: 'unknown',
    );
  }
}

/// PDF contains too little extractable text (<50 chars/page); user must upload an image.
class ScannedPdfFailure extends TimetableImportFailure {
  const ScannedPdfFailure(super.message, {super.serverReason});
}

/// Server received raw HEIC/HEIF bytes or client platform lacks HEIC support.
class UnsupportedHeicFailure extends TimetableImportFailure {
  const UnsupportedHeicFailure(super.message, {super.serverReason});
}

/// Node.js runtime lacks Shift_JIS (CP932) TextDecoder support.
class ShiftJisUnsupportedFailure extends TimetableImportFailure {
  const ShiftJisUnsupportedFailure(super.message, {super.serverReason});
}

/// Google Cloud Vision API failed during document text detection.
class OcrFailedFailure extends TimetableImportFailure {
  const OcrFailedFailure(super.message, {super.serverReason});
}

/// Optimistic concurrency conflict: timetable was modified by another teacher.
class TimetableChangedFailure extends TimetableImportFailure {
  const TimetableChangedFailure(super.message, {super.serverReason});
}

/// School policy changed after the draft preview was created.
class PolicyChangedFailure extends TimetableImportFailure {
  const PolicyChangedFailure(super.message, {super.serverReason});
}

/// Current school policy forbids `mode: 'replace'` for this user.
class PolicyDisallowsReplaceFailure extends TimetableImportFailure {
  const PolicyDisallowsReplaceFailure(super.message, {super.serverReason});
}

/// User lacks authorization to import for this school, grade, or course.
class PermissionDeniedFailure extends TimetableImportFailure {
  const PermissionDeniedFailure(super.message, {super.serverReason});
}

/// AI daily quota has been exhausted.
class QuotaExceededFailure extends TimetableImportFailure {
  const QuotaExceededFailure(super.message, {super.serverReason});
}

/// Uploaded file exceeds the 10 MB limit.
class FileTooLargeFailure extends TimetableImportFailure {
  const FileTooLargeFailure(super.message, {super.serverReason});
}

/// Invalid or oversized date range (>366 days).
class InvalidDateRangeFailure extends TimetableImportFailure {
  const InvalidDateRangeFailure(super.message, {super.serverReason});
}

/// Preview draft expired (TTL 30 min) or does not exist.
class DraftExpiredFailure extends TimetableImportFailure {
  const DraftExpiredFailure(super.message, {super.serverReason});
}

/// Revert window has expired.
class RevertWindowExpiredFailure extends TimetableImportFailure {
  const RevertWindowExpiredFailure(super.message, {super.serverReason});
}

/// Import was already reverted.
class AlreadyRevertedFailure extends TimetableImportFailure {
  const AlreadyRevertedFailure(super.message, {super.serverReason});
}

/// Network connectivity issue or backend service unavailable.
class NetworkUnavailableFailure extends TimetableImportFailure {
  const NetworkUnavailableFailure(super.message, {super.serverReason});
}

/// Request timed out.
class TimeoutFailure extends TimetableImportFailure {
  const TimeoutFailure(super.message, {super.serverReason});
}

/// User is not authenticated.
class UnauthenticatedFailure extends TimetableImportFailure {
  const UnauthenticatedFailure(super.message, {super.serverReason});
}

/// Fallback for unexpected or unknown server reasons — never crashes the UI.
class UnknownFailure extends TimetableImportFailure {
  final String code;
  const UnknownFailure(
    String? reason, {
    String? message,
    this.code = 'unknown',
  }) : super(
          message ?? 'Unknown error',
          serverReason: reason,
        );

  @override
  String toString() =>
      'UnknownFailure: $message [code: $code${serverReason != null ? ', reason: $serverReason' : ''}]';
}
