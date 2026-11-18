import 'package:flutter/material.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../models/timetable_import_failure.dart';
import '../providers/timetable_import_provider.dart';

/// Returns the actionable next-step guidance text for any [TimetableImportFailure].
String nextStepForFailure(TimetableImportFailure failure) => switch (failure) {
      ScannedPdfFailure() => AppStrings.t('tt_import_err_next_scanned_pdf'),
      UnsupportedHeicFailure() =>
        AppStrings.t('tt_import_err_next_unsupported_heic'),
      ShiftJisUnsupportedFailure() =>
        AppStrings.t('tt_import_err_next_sjis_unsupported'),
      OcrFailedFailure() => AppStrings.t('tt_import_err_next_ocr_failed'),
      TimetableChangedFailure() =>
        AppStrings.t('tt_import_err_next_timetable_changed'),
      PolicyChangedFailure() =>
        AppStrings.t('tt_import_err_next_policy_changed'),
      PolicyDisallowsReplaceFailure() =>
        AppStrings.t('tt_import_err_next_replace_disallowed'),
      InvalidDateRangeFailure() =>
        AppStrings.t('tt_import_err_next_invalid_date_range'),
      FileTooLargeFailure() =>
        AppStrings.t('tt_import_err_next_file_too_large'),
      DraftExpiredFailure() => AppStrings.t('tt_import_err_next_draft_expired'),
      RevertWindowExpiredFailure() =>
        AppStrings.t('tt_import_err_next_undo_expired'),
      AlreadyRevertedFailure() =>
        AppStrings.t('tt_import_err_next_already_reverted'),
      PermissionDeniedFailure() =>
        AppStrings.t('tt_import_err_next_permission_denied'),
      QuotaExceededFailure() =>
        AppStrings.t('tt_import_err_next_quota_exceeded'),
      NetworkUnavailableFailure() => AppStrings.t('tt_import_err_next_network'),
      TimeoutFailure() => AppStrings.t('tt_import_err_next_timeout'),
      UnauthenticatedFailure() =>
        AppStrings.t('tt_import_err_next_unauthenticated'),
      UnknownFailure() => AppStrings.t('tt_import_err_next_unknown'),
    };

class TimetableImportIdleCard extends StatelessWidget {
  final VoidCallback onPickFile;

  const TimetableImportIdleCard({super.key, required this.onPickFile});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.cardStroke),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.calendar_month_rounded,
              size: 28,
              color: AppColors.accentText,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            AppStrings.t('tt_import_idle_title'),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Text(
              AppStrings.t('tt_import_idle_desc'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                height: 1.55,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(height: 18),
          OutlinedButton.icon(
            onPressed: onPickFile,
            icon: const Icon(Icons.upload_file_rounded, size: 18),
            label: Text(AppStrings.t('tt_import_pick_file')),
          ),
        ],
      ),
    );
  }
}

class TimetableImportLoadingCard extends StatelessWidget {
  final TimetableImportStep step;

  const TimetableImportLoadingCard({super.key, required this.step});

  @override
  Widget build(BuildContext context) {
    final text = step == TimetableImportStep.confirming
        ? AppStrings.t('tt_import_confirming')
        : AppStrings.t('tt_import_uploading');

    return Container(
      padding: const EdgeInsets.all(36),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.cardStroke),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: AppColors.primary),
          const SizedBox(height: 18),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class TimetableImportDoneCard extends StatelessWidget {
  final TimetableImportState state;
  final VoidCallback onUndo;
  final VoidCallback onStartNew;

  const TimetableImportDoneCard({
    super.key,
    required this.state,
    required this.onUndo,
    required this.onStartNew,
  });

  String _formatRemaining(Duration? d) {
    if (d == null || d == Duration.zero) {
      return AppStrings.t('tt_import_undo_expired_label');
    }
    if (d.inDays >= 1) {
      return AppStrings.t('tt_import_undo_days_hours', {
        'd': d.inDays,
        'h': d.inHours.remainder(24),
      });
    }
    return AppStrings.t('tt_import_undo_hours_mins', {
      'h': d.inHours,
      'm': d.inMinutes.remainder(60),
    });
  }

  @override
  Widget build(BuildContext context) {
    final reverted = state.revertResult;
    if (reverted != null) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.cardSurface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.45)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.undo_rounded, size: 28, color: AppColors.accentText),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    AppStrings.t('tt_import_undone_title'),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              AppStrings.t(
                'tt_import_undone_days',
                {'n': reverted.restoredDaysCount},
              ),
              style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onStartNew,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: Text(AppStrings.t('tt_import_new_import_btn')),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.onPrimary,
              ),
            ),
          ],
        ),
      );
    }

    final result = state.result;
    final remaining = state.undoRemaining(DateTime.now());
    final isExpired = remaining != null && remaining == Duration.zero;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.check_circle_rounded,
                size: 28,
                color: AppColors.success,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  AppStrings.t('tt_import_done_title'),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            AppStrings.t(
              'tt_import_done_days',
              {'n': result?.appliedDays ?? 0},
            ),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          if ((result?.pushedCount ?? 0) > 0) ...[
            const SizedBox(height: 4),
            Text(
              AppStrings.t(
                'tt_import_done_pushed',
                {'n': result!.pushedCount},
              ),
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
          ],
          if (state.canUndo) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surfaceVar,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.cardStroke),
              ),
              child: Row(
                children: [
                  Icon(Icons.timer_outlined,
                      size: 16, color: AppColors.textSecondary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isExpired
                          ? AppStrings.t('tt_import_undo_expired_label')
                          : AppStrings.t('tt_import_undo_remaining', {
                              'time': _formatRemaining(remaining),
                            }),
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (state.error != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.dangerLight,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.danger),
              ),
              child: Text(
                '${state.error!.message}\n${nextStepForFailure(state.error!)}',
                style: TextStyle(fontSize: 12.5, color: AppColors.textPrimary),
              ),
            ),
          ],
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              if (state.canUndo && !isExpired)
                Semantics(
                  button: true,
                  label: AppStrings.t('tt_import_undo_btn'),
                  child: OutlinedButton.icon(
                    key: const Key('import_undo_button'),
                    onPressed: state.reverting ? null : onUndo,
                    icon: state.reverting
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.undo_rounded, size: 18),
                    label: Text(AppStrings.t('tt_import_undo_btn')),
                  ),
                ),
              FilledButton.icon(
                onPressed: onStartNew,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text(AppStrings.t('tt_import_new_import_btn')),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.onPrimary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class TimetableImportErrorCard extends StatelessWidget {
  final TimetableImportFailure failure;
  final VoidCallback onRetryPick;
  final VoidCallback onReset;

  const TimetableImportErrorCard({
    super.key,
    required this.failure,
    required this.onRetryPick,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    final nextStep = nextStepForFailure(failure);

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.error_outline_rounded,
                  size: 26, color: AppColors.danger),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  AppStrings.t('tt_import_error_title'),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            failure.message,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              height: 1.5,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surfaceVar,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.cardStroke),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppStrings.t('tt_import_error_next_step'),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: AppColors.accentText,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  nextStep,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: onRetryPick,
                icon: const Icon(Icons.upload_file_rounded, size: 18),
                label: Text(AppStrings.t('tt_import_reselect_file')),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.onPrimary,
                ),
              ),
              OutlinedButton(
                onPressed: onReset,
                child: Text(AppStrings.t('tt_import_cancel_btn')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
