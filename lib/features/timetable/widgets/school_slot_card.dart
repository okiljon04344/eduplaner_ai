import 'package:flutter/material.dart';
import '../../../core/constants/periods.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../school/models/school.dart';

/// `09:00–10:30` for [p].
String schoolPeriodTimes(SchoolPeriod p) =>
    '${formatHm(p.start)}–${formatHm(p.end)}';

/// Accent colour for [slot]'s state (cancelled, teacher change, event…).
Color schoolSlotAccent(SchoolSlot slot) => switch (slot.status) {
      SchoolSlotStatus.cancelled => AppColors.danger,
      _ when slot.byTeacher => AppColors.warning,
      SchoolSlotStatus.event => AppColors.warning,
      SchoolSlotStatus.tbd => AppColors.textMuted,
      SchoolSlotStatus.elective => AppColors.primaryMid,
      SchoolSlotStatus.normal => AppColors.primary,
    };

/// Short badge for [slot]'s state, or null for an ordinary lesson.
String? schoolSlotBadge(SchoolSlot slot) => switch (slot.status) {
      SchoolSlotStatus.cancelled => AppStrings.t('school_slot_cancelled'),
      SchoolSlotStatus.event => AppStrings.t('school_slot_event'),
      SchoolSlotStatus.tbd => AppStrings.t('school_slot_tbd'),
      _ => switch (slot.teacherKind) {
          SchoolOverrideKind.room => AppStrings.t('teacher_kind_room'),
          SchoolOverrideKind.makeup => AppStrings.t('teacher_kind_makeup'),
          null => null,
          _ => AppStrings.t('school_slot_teacher'),
        },
    };

/// One school lesson. [period] is the matching [SchoolPeriod] (null when the
/// slot's key isn't in the school's period list). [compact] drops the period
/// header for use inside a week-grid cell, where the row already names it.
class SchoolSlotCard extends StatelessWidget {
  final SchoolSlot slot;
  final SchoolPeriod? period;
  final bool compact;
  const SchoolSlotCard(
      {super.key,
      required this.slot,
      required this.period,
      this.compact = false});

  Color get _accent => schoolSlotAccent(slot);

  String? get _badge => schoolSlotBadge(slot);

  @override
  Widget build(BuildContext context) {
    final badge = _badge;
    final elective = slot.status == SchoolSlotStatus.elective;
    // Electives are stored as just the group letter (X/Y/Z).
    final subject = elective
        ? AppStrings.t('school_slot_elective', {'label': slot.subject})
        : slot.subject;
    final who =
        [slot.teacher, slot.room].where((s) => s.isNotEmpty).join(' · ');
    final small = compact ? 10.0 : 12.0;

    // In compact cells the badge goes on its own line so a narrow column
    // doesn't squeeze the subject down to an ellipsis.
    final subjectText = Text(
      subject,
      maxLines: compact ? 3 : 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: compact ? 12 : 14,
        fontWeight: FontWeight.w800,
        color: AppColors.textPrimary,
        decoration: slot.status == SchoolSlotStatus.cancelled
            ? TextDecoration.lineThrough
            : null,
      ),
    );
    final badgeChip = badge == null
        ? null
        : Container(
            padding: EdgeInsets.symmetric(
                horizontal: compact ? 6 : 10, vertical: compact ? 2 : 4),
            decoration: BoxDecoration(
              color: _accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(badge,
                style: TextStyle(
                    fontSize: compact ? 9 : 10,
                    fontWeight: FontWeight.w700,
                    color: _accent)),
          );
    final radius = BorderRadius.circular(compact ? 10 : 18);
    return Container(
      margin: EdgeInsets.only(bottom: compact ? 4 : 14),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: radius,
        border: Border.all(color: AppColors.cardStroke),
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: compact ? 3 : 4, color: _accent),
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(
                    horizontal: compact ? 8 : 16, vertical: compact ? 6 : 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!compact)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Wrap(
                          spacing: 8,
                          children: [
                            Text(period?.label ?? slot.period,
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.accentText)),
                            if (period != null)
                              Text(schoolPeriodTimes(period!),
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                      color: AppColors.textSecondary)),
                          ],
                        ),
                      ),
                    if (compact) ...[
                      subjectText,
                      if (badgeChip != null)
                        Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: badgeChip),
                    ] else
                      Row(
                        children: [
                          Expanded(child: subjectText),
                          if (badgeChip != null) ...[
                            const SizedBox(width: 6),
                            badgeChip,
                          ],
                        ],
                      ),
                    if (who.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(who,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: small,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textSecondary)),
                    ],
                    if (slot.note.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(slot.note,
                          maxLines: compact ? 2 : 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: small - 1, color: AppColors.textMuted)),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
