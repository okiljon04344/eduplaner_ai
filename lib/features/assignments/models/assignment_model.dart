import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
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
        return '未着手';
      case AssignmentStatus.inProgress:
        return '進行中';
      case AssignmentStatus.completed:
        return '完了';
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

  bool get hasAiAnalysis => aiAnalyzedAt != null;

  String get dueDateLabel => DateHelper.dueDateLabel(dueDate);

  Color get dueDateColor => DateHelper.dueDateColor(dueDate);

  Color get dueDateBgColor => DateHelper.dueDateBgColor(dueDate);
}
