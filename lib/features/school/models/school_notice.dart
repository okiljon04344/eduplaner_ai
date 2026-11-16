import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/l10n/app_strings.dart';

/// Board category; wire names match `NOTICE_CATEGORIES` in notices.js.
///
/// UZ: Doska toifasi; uzatiladigan nomlar notices.js dagi `NOTICE_CATEGORIES` ga mos keladi.
enum NoticeCategory {
  change,
  contact,
  assignment;

  String get label => AppStrings.t('board_cat_$name');

  /// Unknown or missing values (notices sent before categories) are 連絡.
  ///
  /// UZ: Noma'lum yoki yetishmayotgan qiymatlar (toifalar joriy qilinishidan oldin yuborilgan
  /// bildirishnomalar) 連絡 hisoblanadi.
  static NoticeCategory parse(Object? v) =>
      values.firstWhere((c) => c.name == v, orElse: () => NoticeCategory.contact);
}

/// お知らせボード (§9.2-4): a teacher's message to one class, or to every
/// course of a grade when [course] is null. Written by `publishSchoolNotice`.
///
/// UZ: お知らせボード (§9.2-4): o'qituvchining bitta sinfga yoki [course] null bo'lganida bosqichning
/// har bir kursiga yuborgan xabari. `publishSchoolNotice` tomonidan yoziladi.
class SchoolNotice {
  final String id, title, body, authorName, createdBy;

  /// Optional subject tag (科目) and https link; empty when unset.
  ///
  /// UZ: Ixtiyoriy fan tegi (科目) va https havolasi; o'rnatilmaganda bo'sh bo'ladi.
  final String subject, link;
  final NoticeCategory category;

  /// Set when the author corrected the notice after sending (訂正).
  ///
  /// UZ: Muallif yuborilganidan so'ng bildirishnomaga tuzatish kiritganda o'rnatiladi (訂正).
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
  ///
  /// UZ: Ushbu bildirishnoma [subject] bilan belgilanganligi (harflar registri va tashqi
  /// bo'shliqlar inobatga olinmaydi).
  bool hasSubject(String subject) => this.subject.isNotEmpty && _norm(this.subject) == _norm(subject);

  /// The link if it is a plain https URL, else null (never open anything else).
  ///
  /// UZ: Agar oddiy https URL bo'lsa havola, aks holda null (boshqa hech narsani ochmang).
  Uri? get safeLink {
    final u = Uri.tryParse(link);
    return u != null && u.scheme == 'https' && u.host.isNotEmpty ? u : null;
  }

  /// Whether a student of [grade]/[course] is an addressee.
  ///
  /// UZ: [grade]/[course] o'quvchisi qabul qiluvchi hisoblanishi.
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
