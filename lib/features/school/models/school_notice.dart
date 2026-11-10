import 'package:cloud_firestore/cloud_firestore.dart';

/// お知らせボード (§9.2-4): a teacher's message to one class, or to every
/// course of a grade when [course] is null. Written by `publishSchoolNotice`.
class SchoolNotice {
  final String id, title, body, authorName, createdBy;
  final int grade;
  final String? course;
  final bool urgent;
  final DateTime? createdAt;

  const SchoolNotice({
    required this.id,
    required this.grade,
    required this.title,
    this.course,
    this.body = '',
    this.urgent = false,
    this.authorName = '',
    this.createdBy = '',
    this.createdAt,
  });

  /// Whether a student of [grade]/[course] is an addressee.
  bool appliesTo(int grade, String course) =>
      this.grade == grade && (this.course == null || this.course == course);

  factory SchoolNotice.fromMap(String id, Map m) => SchoolNotice(
        id: id,
        grade: (m['grade'] as num?)?.toInt() ?? 0,
        course: m['course'] as String?,
        title: m['title'] as String? ?? '',
        body: m['body'] as String? ?? '',
        urgent: m['priority'] == 'urgent',
        authorName: m['createdByName'] as String? ?? '',
        createdBy: m['createdBy'] as String? ?? '',
        createdAt: (m['createdAt'] as Timestamp?)?.toDate(),
      );

  factory SchoolNotice.fromFirestore(DocumentSnapshot doc) =>
      SchoolNotice.fromMap(doc.id, (doc.data() as Map?) ?? const {});
}
