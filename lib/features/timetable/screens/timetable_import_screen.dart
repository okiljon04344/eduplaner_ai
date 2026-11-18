import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../school/school_providers.dart';
import '../../school/widgets/teacher_scaffold.dart';
import '../models/timetable_import_failure.dart';
import '../providers/timetable_import_provider.dart';
import '../widgets/timetable_import_config_card.dart';
import '../widgets/timetable_import_dialogs.dart';
import '../widgets/timetable_import_diff_panel.dart';
import '../widgets/timetable_import_status_panels.dart';

String _isoDate(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Teacher Mode Timetable Import screen (Stage 4c).
///
/// Responsive 2-pane layout on Desktop (`>= 1100`px) and single-column layout
/// on Mobile (`< 1100`px). All import state lives in [timetableImportProvider]
/// (zero `setState`).
class TimetableImportScreen extends ConsumerWidget {
  final Future<PickedImportFile?> Function()? filePickerOverride;

  const TimetableImportScreen({
    super.key,
    this.filePickerOverride,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(schoolInfoProvider).valueOrNull;
    final policy = ref.watch(schoolPolicyProvider);
    final role = ref.watch(schoolRoleProvider);
    final canImport = ref.watch(canImportTimetableProvider);
    final state = ref.watch(timetableImportProvider);
    final notifier = ref.read(timetableImportProvider.notifier);

    if (info == null) {
      return TeacherScaffold(
        section: TeacherSection.timetable,
        title: AppStrings.t('tt_import_title'),
        body: _CenteredMessage(AppStrings.t('teacher_no_school')),
      );
    }

    if (!canImport) {
      return TeacherScaffold(
        section: TeacherSection.timetable,
        title: AppStrings.t('tt_import_title'),
        body: _CenteredMessage(AppStrings.t('tt_import_err_permission_denied')),
      );
    }

    final me = ref.watch(schoolUserIdentityProvider);
    final mine = info.profileOf(me.email);
    final effectiveGrade = state.grade ??
        (info.grades.contains(mine?.homeroomGrade)
            ? mine!.homeroomGrade!
            : (info.grades.isNotEmpty ? info.grades.first : 1));
    final effectiveCourse = state.course ??
        (info.courses.contains(mine?.homeroomCourse)
            ? mine!.homeroomCourse!
            : (info.courses.isNotEmpty ? info.courses.first : null));

    final now = DateTime.now();
    final effectiveStart = state.startDate ?? _isoDate(now);
    final effectiveEnd =
        state.endDate ?? _isoDate(now.add(const Duration(days: 90)));

    final isBusy = state.step == TimetableImportStep.picking ||
        state.step == TimetableImportStep.uploading ||
        state.step == TimetableImportStep.confirming;

    Future<void> triggerPickFile() async {
      if (isBusy) return;
      await notifier.pickAndPreviewFile(
        filePicker: filePickerOverride,
        defaultGrade: effectiveGrade,
        defaultCourse: effectiveCourse,
      );
    }

    void handleEscape() {
      if (state.step != TimetableImportStep.idle) {
        notifier.cancel();
      } else if (context.canPop()) {
        context.pop();
      } else {
        context.go('/teacher/timetable');
      }
    }

    Future<void> handleConfirmPressed() async {
      final preview = state.preview;
      if (preview == null) return;
      final isReplace = state.mode == 'replace';
      final removedCount = preview.diff.removed;
      if (isReplace || removedCount > 0) {
        final confirmed = await showDestructiveImportConfirmDialog(
          context,
          removedCount: removedCount,
          isReplaceMode: isReplace,
        );
        if (!confirmed || !context.mounted) return;
      }
      await notifier.confirmImport();
    }

    final configCard = TimetableImportConfigCard(
      info: info,
      policy: policy,
      isAdmin: role.admin,
      state: state,
      effectiveGrade: effectiveGrade,
      effectiveCourse: effectiveCourse,
      effectiveStartDate: effectiveStart,
      effectiveEndDate: effectiveEnd,
      onUpdateParams: ({
        grade,
        course,
        mode,
        startDate,
        endDate,
        includeNonSchoolDays,
        notifyStudents,
      }) {
        notifier.setParams(
          grade: grade,
          course: course,
          mode: mode,
          startDate: startDate,
          endDate: endDate,
          includeNonSchoolDays: includeNonSchoolDays,
          notifyStudents: notifyStudents,
        );
      },
      onPickFile: triggerPickFile,
    );

    final stepPanel = _buildStepPanel(
      state: state,
      notifier: notifier,
      onPickFile: triggerPickFile,
      onConfirmPressed: handleConfirmPressed,
    );

    final body = CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyI, control: true):
            triggerPickFile,
        const SingleActivator(LogicalKeyboardKey.keyI, meta: true):
            triggerPickFile,
        const SingleActivator(LogicalKeyboardKey.escape): handleEscape,
      },
      child: Focus(
        autofocus: true,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isDesktop = MediaQuery.sizeOf(context).width >= 1100 &&
                constraints.maxWidth >= 720;

            if (isDesktop) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 24, 24),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 370,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.only(bottom: 24),
                        child: configCard,
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.only(bottom: 24),
                        child: stepPanel,
                      ),
                    ),
                  ],
                ),
              );
            }

            final showStepFirst = state.step != TimetableImportStep.idle;
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: showStepFirst
                  ? [
                      stepPanel,
                      const SizedBox(height: 16),
                      configCard,
                    ]
                  : [
                      configCard,
                      const SizedBox(height: 16),
                      stepPanel,
                    ],
            );
          },
        ),
      ),
    );

    return TeacherScaffold(
      section: TeacherSection.timetable,
      title: AppStrings.t('tt_import_title'),
      actions: [
        if (state.step != TimetableImportStep.idle)
          TextButton.icon(
            onPressed: handleEscape,
            icon: const Icon(Icons.close_rounded, size: 18),
            label: Text(AppStrings.t('tt_import_cancel_btn')),
          ),
      ],
      body: body,
    );
  }

  Widget _buildStepPanel({
    required TimetableImportState state,
    required TimetableImportNotifier notifier,
    required VoidCallback onPickFile,
    required VoidCallback onConfirmPressed,
  }) {
    switch (state.step) {
      case TimetableImportStep.idle:
        return TimetableImportIdleCard(onPickFile: onPickFile);
      case TimetableImportStep.picking:
      case TimetableImportStep.uploading:
      case TimetableImportStep.confirming:
        return TimetableImportLoadingCard(step: state.step);
      case TimetableImportStep.preview:
        final preview = state.preview;
        if (preview == null) {
          return TimetableImportIdleCard(onPickFile: onPickFile);
        }
        return TimetableImportDiffPanel(
          state: state,
          preview: preview,
          onToggleMaskedPreview: notifier.toggleMaskedPreview,
          onConfirmPressed: onConfirmPressed,
          onCancel: notifier.cancel,
          onRepickFile: onPickFile,
        );
      case TimetableImportStep.done:
        return TimetableImportDoneCard(
          state: state,
          onUndo: notifier.revertCurrentImport,
          onStartNew: notifier.reset,
        );
      case TimetableImportStep.error:
        return TimetableImportErrorCard(
          failure: state.error ?? const UnknownFailure(null),
          onRetryPick: onPickFile,
          onReset: notifier.cancel,
        );
    }
  }
}

class _CenteredMessage extends StatelessWidget {
  final String text;
  const _CenteredMessage(this.text);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
        ),
      ),
    );
  }
}
