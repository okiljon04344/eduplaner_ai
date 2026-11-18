import 'package:flutter/material.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../school/models/school.dart';
import '../providers/timetable_import_provider.dart';
import '../repositories/timetable_import_file_helper.dart';

/// Left-pane (Desktop) or top (Mobile) configuration card for selecting
/// class, import mode, date range, notification toggles, and source file.
class TimetableImportConfigCard extends StatelessWidget {
  final SchoolInfo info;
  final SchoolPolicy policy;
  final bool isAdmin;
  final TimetableImportState state;
  final int effectiveGrade;
  final String? effectiveCourse;
  final String effectiveStartDate;
  final String effectiveEndDate;
  final void Function({
    int? grade,
    String? course,
    String? mode,
    String? startDate,
    String? endDate,
    bool? includeNonSchoolDays,
    bool? notifyStudents,
  }) onUpdateParams;
  final VoidCallback onPickFile;

  const TimetableImportConfigCard({
    super.key,
    required this.info,
    required this.policy,
    required this.isAdmin,
    required this.state,
    required this.effectiveGrade,
    required this.effectiveCourse,
    required this.effectiveStartDate,
    required this.effectiveEndDate,
    required this.onUpdateParams,
    required this.onPickFile,
  });

  bool get _isBusy =>
      state.step == TimetableImportStep.picking ||
      state.step == TimetableImportStep.uploading ||
      state.step == TimetableImportStep.confirming;

  @override
  Widget build(BuildContext context) {
    final canReplace = policy.canUserUseReplace(isAdmin: isAdmin);
    final replaceDisabledReason = policy.replaceMode == 'disabled'
        ? AppStrings.t('tt_import_mode_replace_disabled')
        : AppStrings.t('tt_import_mode_replace_admin_only');
    final grades = info.grades.isEmpty ? const [1, 2, 3] : info.grades;

    return Material(
      color: AppColors.cardSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: AppColors.cardStroke),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.tune_rounded, size: 18, color: AppColors.accentText),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  AppStrings.t('tt_import_config_title'),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Grade selector
          Text(
            AppStrings.t('tt_import_grade'),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final g in grades)
                ChoiceChip(
                  label: Text(AppStrings.t('teacher_grade', {'n': g})),
                  selected: g == effectiveGrade,
                  onSelected: _isBusy ? null : (_) => onUpdateParams(grade: g),
                ),
            ],
          ),

          if (info.courses.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              AppStrings.t('tt_import_course'),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in info.courses)
                  ChoiceChip(
                    label: Text(c),
                    selected: c == effectiveCourse,
                    onSelected:
                        _isBusy ? null : (_) => onUpdateParams(course: c),
                  ),
              ],
            ),
          ],

          const SizedBox(height: 16),
          Text(
            AppStrings.t('tt_import_mode'),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: Text(AppStrings.t('tt_import_mode_merge')),
                selected: state.mode == 'merge',
                onSelected:
                    _isBusy ? null : (_) => onUpdateParams(mode: 'merge'),
              ),
              ChoiceChip(
                label: Text(AppStrings.t('tt_import_mode_replace')),
                selected: state.mode == 'replace',
                onSelected: (_isBusy || !canReplace)
                    ? null
                    : (_) => onUpdateParams(mode: 'replace'),
              ),
            ],
          ),
          if (!canReplace) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.lock_outline_rounded,
                    size: 14, color: AppColors.textMuted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    replaceDisabledReason,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textMuted,
                    ),
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(height: 16),
          Text(
            AppStrings.t('tt_import_date_range'),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: _DateFieldButton(
                  label: AppStrings.t('tt_import_start_date'),
                  value: effectiveStartDate,
                  enabled: !_isBusy,
                  onPick: (picked) => onUpdateParams(startDate: picked),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _DateFieldButton(
                  label: AppStrings.t('tt_import_end_date'),
                  value: effectiveEndDate,
                  enabled: !_isBusy,
                  onPick: (picked) => onUpdateParams(endDate: picked),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: state.includeNonSchoolDays,
            onChanged: _isBusy
                ? null
                : (v) => onUpdateParams(includeNonSchoolDays: v),
            title: Text(
              AppStrings.t('tt_import_include_non_school_days'),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: state.notifyStudents,
            onChanged:
                _isBusy ? null : (v) => onUpdateParams(notifyStudents: v),
            title: Text(
              AppStrings.t('tt_import_notify_students'),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),

          const Divider(height: 20),
          Text(
            AppStrings.t('tt_import_supported_formats'),
            style: TextStyle(
              fontSize: 12,
              height: 1.45,
              color: AppColors.textSecondary,
            ),
          ),
          if (!isClientHeicConversionSupported) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.surfaceVar,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.cardStroke),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded,
                      size: 16, color: AppColors.textSecondary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      AppStrings.t('tt_import_heic_desktop_note'),
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.4,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 14),
          Semantics(
            button: true,
            label: state.preview == null
                ? AppStrings.t('tt_import_pick_file')
                : AppStrings.t('tt_import_reselect_file'),
            child: FilledButton.icon(
              key: const Key('pick_import_file_button'),
              onPressed: _isBusy ? null : onPickFile,
              icon: const Icon(Icons.upload_file_rounded, size: 18),
              label: Text(
                state.preview == null
                    ? AppStrings.t('tt_import_pick_file')
                    : AppStrings.t('tt_import_reselect_file'),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.onPrimary,
                minimumSize: const Size(0, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
          if (state.fileName != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.description_outlined,
                    size: 15, color: AppColors.accentText),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    state.fileName!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Text(
            AppStrings.t('tt_import_shortcut_hint'),
            style: TextStyle(
              fontSize: 11,
              color: AppColors.textMuted,
            ),
          ),
        ],
        ),
      ),
    );
  }
}

class _DateFieldButton extends StatelessWidget {
  final String label;
  final String value;
  final bool enabled;
  final ValueChanged<String> onPick;

  const _DateFieldButton({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: !enabled
          ? null
          : () async {
              final initial = DateTime.tryParse(value) ?? DateTime.now();
              final picked = await showDatePicker(
                context: context,
                initialDate: initial,
                firstDate: DateTime(2024, 1, 1),
                lastDate: DateTime(2032, 12, 31),
              );
              if (picked != null) {
                final iso =
                    '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
                onPick(iso);
              }
            },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.bgInput,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.cardStroke),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                Expanded(
                  child: Text(
                    value,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                Icon(Icons.calendar_today_outlined,
                    size: 14, color: AppColors.textSecondary),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
