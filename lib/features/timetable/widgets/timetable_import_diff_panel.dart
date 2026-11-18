import 'package:flutter/material.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../school/models/school.dart';
import '../models/timetable_import_failure.dart';
import '../models/timetable_import_models.dart';
import '../providers/timetable_import_provider.dart';

/// Displays the parsed diff summary, per-slot diff preview (with Icon + Text
/// + Color for every status), excluded dates (marking provisional holidays),
/// unparsed rows, AI masked-text toggle, and Confirm / Cancel buttons.
class TimetableImportDiffPanel extends StatelessWidget {
  final TimetableImportState state;
  final TimetableImportPreview preview;
  final VoidCallback onToggleMaskedPreview;
  final VoidCallback onConfirmPressed;
  final VoidCallback onCancel;
  final VoidCallback onRepickFile;

  const TimetableImportDiffPanel({
    super.key,
    required this.state,
    required this.preview,
    required this.onToggleMaskedPreview,
    required this.onConfirmPressed,
    required this.onCancel,
    required this.onRepickFile,
  });

  @override
  Widget build(BuildContext context) {
    final isConflict = state.error is TimetableChangedFailure;
    final hasMasked = (preview.maskedPreviewText ?? '').trim().isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.cardStroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                AppStrings.t('tt_import_preview_title'),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              _InfoPill(
                icon: Icons.event_available_outlined,
                label: AppStrings.t(
                  'tt_import_changed_days',
                  {'n': preview.changedDaysCount},
                ),
                color: AppColors.accentText,
                bg: AppColors.primary.withValues(alpha: 0.14),
              ),
              _InfoPill(
                icon: Icons.settings_suggest_outlined,
                label: AppStrings.t(
                  'tt_import_parse_method',
                  {'method': preview.parseMethod.wireName},
                ),
                color: AppColors.textSecondary,
                bg: AppColors.surfaceVar,
              ),
              if (preview.usedAi)
                _InfoPill(
                  icon: Icons.auto_awesome_rounded,
                  label: AppStrings.t('tt_import_used_ai_badge'),
                  color: AppColors.cyanDeep,
                  bg: AppColors.cyan.withValues(alpha: 0.14),
                ),
            ],
          ),

          if (preview.usedAi && hasMasked) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('toggle_masked_preview_button'),
                onPressed: onToggleMaskedPreview,
                icon: Icon(
                  state.showMaskedPreview
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  size: 16,
                ),
                label: Text(
                  AppStrings.t(
                    state.showMaskedPreview
                        ? 'tt_import_hide_masked'
                        : 'tt_import_view_masked',
                  ),
                ),
              ),
            ),
            if (state.showMaskedPreview)
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surfaceVar,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.cardStroke),
                ),
                child: SelectableText(
                  preview.maskedPreviewText!,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    height: 1.45,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
          ],

          const SizedBox(height: 14),

          // Summary chips (Icon + Text Label + Color)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _DiffStatusChip(
                kind: DiffKind.added,
                count: preview.diff.added,
              ),
              _DiffStatusChip(
                kind: DiffKind.changed,
                count: preview.diff.changed,
              ),
              _DiffStatusChip(
                kind: DiffKind.removed,
                count: preview.diff.removed,
              ),
              _DiffStatusChip(
                kind: DiffKind.unchanged,
                count: preview.diff.unchanged,
              ),
            ],
          ),

          if (isConflict) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.dangerLight,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.danger),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.sync_problem_rounded,
                          size: 18, color: AppColors.danger),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          state.error!.message,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    AppStrings.t('tt_import_err_next_timetable_changed'),
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.45,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: onRepickFile,
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    label: Text(AppStrings.t('tt_import_retry_preview_btn')),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 16),

          // Diff items list
          if (preview.diff.preview.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surfaceVar,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.cardStroke),
              ),
              child: Text(
                AppStrings.t('tt_import_diff_empty'),
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
            )
          else ...[
            for (final item in preview.diff.preview) _DiffItemTile(item: item),
            if (preview.diff.preview.length >= 200)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  AppStrings.t('tt_import_diff_truncated'),
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
              ),
          ],

          // Excluded dates section
          if (preview.excludedDates.isNotEmpty) ...[
            const SizedBox(height: 16),
            _ExcludedDatesCard(excludedDates: preview.excludedDates),
          ],

          // Invalid rows expandable section
          if (preview.invalidRows.isNotEmpty) ...[
            const SizedBox(height: 14),
            _InvalidRowsCard(invalidRows: preview.invalidRows),
          ],

          const SizedBox(height: 20),

          // Footer action bar
          Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.end,
            children: [
              Semantics(
                button: true,
                label: AppStrings.t('tt_import_cancel_btn'),
                child: OutlinedButton(
                  key: const Key('import_cancel_button'),
                  onPressed: onCancel,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 46),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(AppStrings.t('tt_import_cancel_btn')),
                ),
              ),
              Semantics(
                button: true,
                label: AppStrings.t('tt_import_confirm_btn'),
                child: FilledButton.icon(
                  key: const Key('import_confirm_button'),
                  onPressed: preview.diff.totalMutations == 0 &&
                          preview.changedDaysCount == 0
                      ? null
                      : onConfirmPressed,
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: Text(
                    AppStrings.t('tt_import_confirm_btn'),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: (state.mode == 'replace' ||
                            preview.diff.removed > 0)
                        ? AppColors.danger
                        : AppColors.primary,
                    foregroundColor: (state.mode == 'replace' ||
                            preview.diff.removed > 0)
                        ? Colors.white
                        : AppColors.onPrimary,
                    minimumSize: const Size(0, 46),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

({IconData icon, String label, Color fg, Color bg}) _diffVisuals(DiffKind kind) {
  switch (kind) {
    case DiffKind.added:
      return (
        icon: Icons.add_circle_outline_rounded,
        label: AppStrings.t('tt_import_diff_added'),
        fg: AppColors.success,
        bg: AppColors.successLight,
      );
    case DiffKind.changed:
      return (
        icon: Icons.edit_outlined,
        label: AppStrings.t('tt_import_diff_changed'),
        fg: AppColors.amberDeep,
        bg: AppColors.warningLight,
      );
    case DiffKind.removed:
      return (
        icon: Icons.remove_circle_outline_rounded,
        label: AppStrings.t('tt_import_diff_removed'),
        fg: AppColors.danger,
        bg: AppColors.dangerLight,
      );
    case DiffKind.unchanged:
      return (
        icon: Icons.check_circle_outline_rounded,
        label: AppStrings.t('tt_import_diff_unchanged'),
        fg: AppColors.textSecondary,
        bg: AppColors.surfaceVar,
      );
  }
}

class _DiffStatusChip extends StatelessWidget {
  final DiffKind kind;
  final int count;

  const _DiffStatusChip({required this.kind, required this.count});

  @override
  Widget build(BuildContext context) {
    final v = _diffVisuals(kind);
    return Semantics(
      label: '${v.label}: $count',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: v.bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: v.fg.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(v.icon, size: 15, color: v.fg),
            const SizedBox(width: 6),
            Text(
              '${v.label}: $count',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: v.fg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DiffItemTile extends StatelessWidget {
  final ImportDiffItem item;

  const _DiffItemTile({required this.item});

  String _formatSlot(SchoolSlot? s) {
    if (s == null || s.subject.isEmpty) {
      return AppStrings.t('tt_import_empty_slot_label');
    }
    final extras = [
      if (s.teacher.isNotEmpty) s.teacher,
      if (s.room.isNotEmpty) s.room,
    ].join(' · ');
    return extras.isEmpty ? s.subject : '${s.subject} ($extras)';
  }

  @override
  Widget build(BuildContext context) {
    final v = _diffVisuals(item.kind);
    final header = item.weekday.isNotEmpty
        ? '${item.date} (${item.weekday}) · ${AppStrings.t('tt_period', {'n': item.period})}'
        : '${item.date} · ${AppStrings.t('tt_period', {'n': item.period})}';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceVar,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: v.fg.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  header,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: v.bg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(v.icon, size: 13, color: v.fg),
                    const SizedBox(width: 4),
                    Text(
                      v.label,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: v.fg,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (item.kind == DiffKind.added)
            Text(
              _formatSlot(item.after),
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            )
          else if (item.kind == DiffKind.removed)
            Text(
              _formatSlot(item.before),
              style: const TextStyle(
                fontSize: 13.5,
                decoration: TextDecoration.lineThrough,
                color: AppColors.danger,
              ),
            )
          else if (item.kind == DiffKind.changed)
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  _formatSlot(item.before),
                  style: TextStyle(
                    fontSize: 13,
                    decoration: TextDecoration.lineThrough,
                    color: AppColors.textMuted,
                  ),
                ),
                const Icon(Icons.arrow_forward_rounded,
                    size: 14, color: AppColors.amberDeep),
                Text(
                  _formatSlot(item.after),
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            )
          else
            Text(
              _formatSlot(item.after ?? item.before),
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
        ],
      ),
    );
  }
}

class _ExcludedDatesCard extends StatelessWidget {
  final List<ExcludedDate> excludedDates;

  const _ExcludedDatesCard({required this.excludedDates});

  String _reasonLabel(ExcludedDateReason reason) => switch (reason) {
        ExcludedDateReason.holiday => AppStrings.t('tt_import_excluded_holiday'),
        ExcludedDateReason.closedDateRange =>
          AppStrings.t('tt_import_excluded_closed'),
        ExcludedDateReason.nonSchoolDay =>
          AppStrings.t('tt_import_excluded_non_school'),
        ExcludedDateReason.manual => AppStrings.t('tt_import_excluded_manual'),
        ExcludedDateReason.unknown => AppStrings.t('tt_import_excluded_manual'),
      };

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceVar,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: AppColors.cardStroke),
      ),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        initiallyExpanded: excludedDates.any((d) => d.provisional),
        shape: const Border(),
        collapsedShape: const Border(),
        leading: Icon(Icons.event_busy_outlined, color: AppColors.textSecondary),
        title: Text(
          AppStrings.t(
            'tt_import_excluded_dates_title',
            {'n': excludedDates.length},
          ),
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        children: [
          for (final d in excludedDates)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Text(
                    d.date,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      d.label.isNotEmpty
                          ? '${_reasonLabel(d.reason)} · ${d.label}'
                          : _reasonLabel(d.reason),
                      style: TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  if (d.provisional)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.warningLight,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: AppColors.warning.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.schedule_outlined,
                            size: 12,
                            color: AppColors.warning,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            AppStrings.t('tt_import_provisional'),
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: AppColors.amberDeep,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _InvalidRowsCard extends StatelessWidget {
  final List<InvalidRow> invalidRows;

  const _InvalidRowsCard({required this.invalidRows});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.warningLight,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: AppColors.warning.withValues(alpha: 0.55)),
      ),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        initiallyExpanded: true,
        shape: const Border(),
        collapsedShape: const Border(),
        leading: const Icon(Icons.warning_amber_rounded, color: AppColors.warning),
        title: Text(
          AppStrings.t(
            'tt_import_invalid_rows_title',
            {'n': invalidRows.length},
          ),
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        children: [
          for (final row in invalidRows)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppStrings.t('tt_import_row_number', {'n': row.rowNumber}),
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.amberDeep,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      row.rawText.isNotEmpty
                          ? '${row.reason} (${row.rawText})'
                          : row.reason,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Color bg;

  const _InfoPill({
    required this.icon,
    required this.label,
    required this.color,
    required this.bg,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
