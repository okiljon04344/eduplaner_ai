import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:intl/intl.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_helper.dart';

part 'assignment_model.freezed.dart';
part 'assignment_model.g.dart';

enum AssignmentStatus {
  notStarted,
  inProgress,
  completed;

  String get label {
    switch (this) {
      case AssignmentStatus.notStarted:
        return AppStrings.t('status_not_started');
      case AssignmentStatus.inProgress:
        return AppStrings.t('status_in_progress');
      case AssignmentStatus.completed:
        return AppStrings.t('status_completed');
    }
  }

  Color get bgColor {
    switch (this) {
      case AssignmentStatus.notStarted:
        return AppColors.dangerLight;
      case AssignmentStatus.inProgress:
        return AppColors.warningLight;
      case AssignmentStatus.completed:
        return AppColors.successLight;
    }
  }

  Color get textColor {
    switch (this) {
      case AssignmentStatus.notStarted:
        return AppColors.danger;
      case AssignmentStatus.inProgress:
        return const Color(0xFFC2410C);
      case AssignmentStatus.completed:
        return const Color(0xFF15803D);
    }
  }

  Color get borderColor {
    switch (this) {
      case AssignmentStatus.notStarted:
        return const Color(0xFFFECACA);
      case AssignmentStatus.inProgress:
        return const Color(0xFFFED7AA);
      case AssignmentStatus.completed:
        return const Color(0xFFBBF7D0);
    }
  }

  String get firestoreValue {
    switch (this) {
      case AssignmentStatus.notStarted:
        return 'notStarted';
      case AssignmentStatus.inProgress:
        return 'inProgress';
      case AssignmentStatus.completed:
        return 'completed';
    }
  }

  static AssignmentStatus fromString(String value) {
    switch (value) {
      case 'inProgress':
        return AssignmentStatus.inProgress;
      case 'completed':
        return AssignmentStatus.completed;
      default:
        return AssignmentStatus.notStarted;
    }
  }
}

@freezed
class AssignmentModel with _$AssignmentModel {
  const factory AssignmentModel({
    required String id,
    required String userId,
    required String title,
    required String subject,
    String? description,
    required DateTime dueDate,
    required AssignmentStatus status,
    @Default(1) int difficulty,
    @Default(0.0) double progress,
    required DateTime createdAt,
    double? aiCompletionPercent,
    @Default([]) List<String> aiMissingParts,
    String? aiAdvice,
    DateTime? aiAnalyzedAt,
  }) = _AssignmentModel;

  factory AssignmentModel.fromJson(Map<String, dynamic> json) => _$AssignmentModelFromJson(json);

  factory AssignmentModel.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    return AssignmentModel(
      id: doc.id,
      userId: d['userId'] as String? ?? '',
      title: d['title'] as String? ?? '',
      subject: d['subject'] as String? ?? '',
      description: d['description'] as String?,
      dueDate: (d['dueDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      status: AssignmentStatus.fromString(d['status'] as String? ?? 'notStarted'),
      difficulty: (d['difficulty'] as num?)?.toInt() ?? 1,
      progress: (d['progress'] as num?)?.toDouble() ?? 0.0,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      aiCompletionPercent: (d['aiCompletionPercent'] as num?)?.toDouble(),
      aiMissingParts: (d['aiMissingParts'] as List<dynamic>? ?? []).map((e) => e.toString()).toList(),
      aiAdvice: d['aiAdvice'] as String?,
      aiAnalyzedAt: (d['aiAnalyzedAt'] as Timestamp?)?.toDate(),
    );
  }

  const AssignmentModel._();

  Map<String, dynamic> toFirestore() => {
        'userId': userId,
        'title': title,
        'subject': subject,
        'description': description,
        'dueDate': Timestamp.fromDate(dueDate),
        'status': status.firestoreValue,
        'difficulty': difficulty,
        'progress': progress,
        'createdAt': Timestamp.fromDate(createdAt),
        'aiCompletionPercent': aiCompletionPercent,
        'aiMissingParts': aiMissingParts,
        'aiAdvice': aiAdvice,
        'aiAnalyzedAt': aiAnalyzedAt == null ? null : Timestamp.fromDate(aiAnalyzedAt!),
      };

  /// The single status ⇄ progress rule, applied wherever either changes.
  ///
  /// Progress that goes with [status]: completed → 1.0, notStarted → 0.0,
  /// inProgress keeps [progress] but clamped into (0, 1) exclusive (0 → 0.1,
  /// 1.0 → 0.9) so an in-progress item never reads as 0% or 100%.
  static double progressForStatus(AssignmentStatus status, double progress) {
    switch (status) {
      case AssignmentStatus.completed:
        return 1.0;
      case AssignmentStatus.notStarted:
        return 0.0;
      case AssignmentStatus.inProgress:
        if (progress <= 0) return 0.1;
        if (progress >= 1) return 0.9;
        return progress;
    }
  }

  /// Status implied by [progress]: 0 → notStarted, >= 1 → completed, else inProgress.
  static AssignmentStatus statusForProgress(double progress) {
    if (progress <= 0) return AssignmentStatus.notStarted;
    if (progress >= 1) return AssignmentStatus.completed;
    return AssignmentStatus.inProgress;
  }

  /// Copy with [status] applied and [progress] adjusted to match.
  AssignmentModel withStatus(AssignmentStatus status) =>
      copyWith(status: status, progress: progressForStatus(status, progress));

  /// Copy with [progress] applied and the status derived from it.
  AssignmentModel withProgress(double progress) =>
      copyWith(progress: progress, status: statusForProgress(progress));

  bool get hasAiAnalysis => aiAnalyzedAt != null;

  // Finished work is never "overdue" / "due today": show the plain date, muted.
  bool get _isDone => status == AssignmentStatus.completed;

  String get dueDateLabel =>
      _isDone ? DateFormat.MMMd(AppStrings.currentLocale).format(dueDate) : DateHelper.dueDateLabel(dueDate);

  Color get dueDateColor => _isDone ? AppColors.textMuted : DateHelper.dueDateColor(dueDate);

  Color get dueDateBgColor =>
      _isDone ? AppColors.textMuted.withValues(alpha: 0.12) : DateHelper.dueDateBgColor(dueDate);
}
