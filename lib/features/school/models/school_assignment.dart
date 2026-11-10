import 'package:cloud_firestore/cloud_firestore.dart';

/// 課題配布 (§9.2-3): a teacher's assignment handed to one class, or to every
/// course of a grade when [course] is null. Written by `publishSchoolAssignment`.
class SchoolAssignment {
  final String id;
  final String domain;
  final int grade;
  final String? course;
  final String subject;
  final String title;
  final String description;
  final DateTime dueAt;
  final String createdBy;
  final String createdByName;
  final DateTime? createdAt;
  final int total;

  const SchoolAssignment({
    required this.id,
    required this.grade,
    required this.subject,
    required this.title,
    required this.dueAt,
    this.domain = '',
    this.course,
    this.description = '',
    this.createdBy = '',
    this.createdByName = '',
    this.createdAt,
    this.total = 0,
  });

  /// Whether a student of [grade]/[course] is an addressee.
  bool appliesTo(int grade, String course) =>
      this.grade == grade && (this.course == null || this.course == course);

  factory SchoolAssignment.fromMap(String id, Map m) => SchoolAssignment(
        id: id,
        domain: m['domain'] as String? ?? '',
        grade: (m['grade'] as num?)?.toInt() ?? 0,
        course: m['course'] as String?,
        subject: m['subject'] as String? ?? '',
        title: m['title'] as String? ?? '',
        description: m['description'] as String? ?? '',
        dueAt: (m['dueAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
        createdBy: m['createdBy'] as String? ?? '',
        createdByName: m['createdByName'] as String? ?? '',
        createdAt: (m['createdAt'] as Timestamp?)?.toDate(),
        total: (m['total'] as num?)?.toInt() ?? 0,
      );

  factory SchoolAssignment.fromFirestore(DocumentSnapshot doc) =>
      SchoolAssignment.fromMap(doc.id, (doc.data() as Map?) ?? const {});
}

/// One student's progress record on a distributed assignment, readable by
/// the school's teachers. Written and mirrored only by Cloud Functions.
class AssignmentProgress {
  final String id;
  final String domain;
  final String sourceId;
  final String uid;
  final String name;
  final String status;
  final double progress;
  final DateTime? updatedAt;

  const AssignmentProgress({
    required this.id,
    required this.sourceId,
    required this.uid,
    this.domain = '',
    this.name = '',
    this.status = 'notStarted',
    this.progress = 0.0,
    this.updatedAt,
  });

  factory AssignmentProgress.fromMap(String id, Map m) => AssignmentProgress(
        id: id,
        domain: m['domain'] as String? ?? '',
        sourceId: m['sourceId'] as String? ?? '',
        uid: m['uid'] as String? ?? '',
        name: m['name'] as String? ?? '',
        status: m['status'] as String? ?? 'notStarted',
        progress: (m['progress'] as num?)?.toDouble() ?? 0.0,
        updatedAt: (m['updatedAt'] as Timestamp?)?.toDate(),
      );

  factory AssignmentProgress.fromFirestore(DocumentSnapshot doc) =>
      AssignmentProgress.fromMap(doc.id, (doc.data() as Map?) ?? const {});
}

/// Aggregates progress counts and completion rate across a list of student records.
({int total, int completed, int inProgress, int notStarted, double rate}) summarizeProgress(
    List<AssignmentProgress> items) {
  final total = items.length;
  var completed = 0;
  var inProgress = 0;
  var notStarted = 0;
  for (final item in items) {
    switch (item.status) {
      case 'completed':
        completed++;
        break;
      case 'inProgress':
        inProgress++;
        break;
      case 'notStarted':
      default:
        notStarted++;
        break;
    }
  }
  final rate = total > 0 ? completed / total : 0.0;
  return (
    total: total,
    completed: completed,
    inProgress: inProgress,
    notStarted: notStarted,
    rate: rate,
  );
}
