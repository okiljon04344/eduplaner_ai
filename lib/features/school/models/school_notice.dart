import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/l10n/app_strings.dart';

/// Board category; wire names match `NOTICE_CATEGORIES` in notices.js.
enum NoticeCategory {
  change,
  contact,
  assignment;

  String get label => AppStrings.t('board_cat_$name');

  /// Unknown or missing values (notices sent before categories) are 連絡.
  static NoticeCategory parse(Object? v) =>
      values.firstWhere((c) => c.name == v, orElse: () => NoticeCategory.contact);
}

/// お知らせボード (§9.2-4): a teacher's message to one class, or to every
/// course of a grade when [course] is null. Written by `publishSchoolNotice`.
class SchoolNotice {
  final String id, title, body, authorName, createdBy;

  /// Optional subject tag (科目) and https link; empty when unset.
  final String subject, link;
  final NoticeCategory category;

  /// Set when the author corrected the notice after sending (訂正).
  final DateTime? editedAt;
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
    this.subject = '',
    this.link = '',
    this.category = NoticeCategory.contact,
    this.editedAt,
  });

  static String _norm(String s) => s.trim().toLowerCase();

  /// Whether this notice is tagged with [subject] (case and outer spaces ignored).
  bool hasSubject(String subject) => this.subject.isNotEmpty && _norm(this.subject) == _norm(subject);

  /// The link if it is a plain https URL, else null (never open anything else).
  Uri? get safeLink {
    final u = Uri.tryParse(link);
    return u != null && u.scheme == 'https' && u.host.isNotEmpty ? u : null;
  }

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
        subject: m['subject'] as String? ?? '',
        link: m['link'] as String? ?? '',
        category: NoticeCategory.parse(m['category']),
        editedAt: (m['editedAt'] as Timestamp?)?.toDate(),
      );

  factory SchoolNotice.fromFirestore(DocumentSnapshot doc) =>
      SchoolNotice.fromMap(doc.id, (doc.data() as Map?) ?? const {});
}
