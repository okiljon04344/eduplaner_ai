import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/constants/periods.dart';

/// Schedule state for a school timetable slot, such as normal, cancelled, or special event.
///
/// UZ: Maktab dars jadvali katakchasi holati, masalan normal, bekor qilingan yoki maxsus tadbir.
enum SchoolSlotStatus {
  normal,
  cancelled,
  event,
  tbd,
  elective;

  /// Unknown or missing values fall back to [normal].
  ///
  /// UZ: Noma'lum yoki mavjud bo'lmagan qiymatlar [normal] ga qaytadi.
  static SchoolSlotStatus parse(String? s) => SchoolSlotStatus.values
      .firstWhere((v) => v.name == s, orElse: () => SchoolSlotStatus.normal);
}

String _str(Object? v) => v is String ? v : '';

List<Map> _maps(Object? v) => v is List ? v.whereType<Map>().toList() : const [];

List<String> _strings(Object? v) => v is List ? v.whereType<String>().toList() : const [];

/// `'HH:MM'` -> [Hm]; malformed values become `(0, 0)`.
///
/// UZ: `'HH:MM'` -> [Hm]; noto'g'ri shakllangan qiymatlar `(0, 0)` ga aylanadi.
Hm _parseHm(Object? v) {
  final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(_str(v));
  if (m == null) return (0, 0);
  return (int.parse(m.group(1)!), int.parse(m.group(2)!));
}

DateTime? _ts(Object? v) => v is Timestamp ? v.toDate() : null;

/// Represents a class period slot with identifier key, display name, and start/end clock times.
///
/// UZ: Identifikator kaliti, ko'rsatiladigan nomi va boshlanish/tugash vaqtlari bilan dars soati katakchasini ifodalaydi.
class SchoolPeriod {
  final String key, label;
  final Hm start, end;
  const SchoolPeriod(
      {required this.key,
      required this.label,
      required this.start,
      required this.end});

  factory SchoolPeriod.fromMap(Map m) => SchoolPeriod(
        key: _str(m['key']),
        label: _str(m['label']),
        start: _parseHm(m['start']),
        end: _parseHm(m['end']),
      );
}

/// Represents a scheduled class lesson slot within a school day, including subject, instructor,
/// classroom location, schedule status, and optional teacher overrides.
///
/// UZ: O'quv kunidagi rejalashtirilgan dars katakchasini ifodalaydi, jumladan fan, o'qituvchi,
/// xona joylashuvi, jadval holati va o'qituvchi tomonidan kiritilgan ixtiyoriy o'zgarishlar.
class SchoolSlot {
  final String period, subject, teacher, room, note;
  final SchoolSlotStatus status;

  /// Set when a teacher's input (school_overrides) changed this lesson.
  ///
  /// UZ: O'qituvchining kiritishi (school_overrides) ushbu darsni o'zgartirganda o'rnatiladi.
  final SchoolOverrideKind? teacherKind;

  bool get byTeacher => teacherKind != null;
  const SchoolSlot({
    required this.period,
    required this.subject,
    required this.teacher,
    required this.room,
    required this.note,
    required this.status,
    this.teacherKind,
  });

  SchoolSlot _teacher(SchoolOverrideKind kind, {String? room, String? note, SchoolSlotStatus? status}) =>
      SchoolSlot(
        period: period,
        subject: subject,
        teacher: teacher,
        room: room ?? this.room,
        note: note ?? this.note,
        status: status ?? this.status,
        teacherKind: kind,
      );

  factory SchoolSlot.fromMap(Map m) => SchoolSlot(
        period: _str(m['period']),
        subject: _str(m['subject']),
        teacher: _str(m['teacher']),
        room: _str(m['room']),
        note: _str(m['note']),
        status: SchoolSlotStatus.parse(_str(m['status'])),
      );
}

/// Daily timetable structure containing the date string and all scheduled period slots.
///
/// UZ: Sana qatori va barcha rejalashtirilgan dars soati katakchalarini o'z ichiga olgan kunlik dars jadvali tuzilmasi.
class SchoolDay {
  final String date;
  final List<SchoolSlot> slots;
  const SchoolDay({required this.date, required this.slots});

  factory SchoolDay.fromMap(Map m) => SchoolDay(
        date: _str(m['date']),
        slots: _maps(m['slots']).map(SchoolSlot.fromMap).toList(),
      );

  factory SchoolDay.fromFirestore(DocumentSnapshot doc) =>
      SchoolDay.fromMap((doc.data() as Map?) ?? const {});
}

/// Metadata and operational rules for a school, managing academic periods, grades,
/// courses, teacher authorization profiles, and editing permissions.
///
/// UZ: Maktab uchun metama'lumotlar va operatsion qoidalar: o'quv soatlari, sinflar/bosqichlar,
/// kurslar, o'qituvchilar vakolatlari profillari va tahrirlash huquqlarini boshqaradi.
class SchoolInfo {
  final String domain, name;
  final List<SchoolPeriod> periods;
  final List<int> grades;
  final List<String> courses;
  final DateTime? lastSyncAt;

  /// Admin uids and registered teacher emails (lowercase).
  ///
  /// UZ: Admin uid lari va ro'yxatdan o'tgan o'qituvchi elektron pochtalari (kichik harflarda).
  final List<String> admins, teachers;

  /// Per teacher email: the name as written in the timetable file and the
  /// homeroom class (担任). Edit scope (§9.3) is derived from these.
  ///
  /// UZ: Har bir o'qituvchi elektron pochtasi bo'yicha: dars jadvali faylida yozilgan ism
  /// va rahbarlik sinfi (担任). Tahrirlash ko'lami (§9.3) shulardan olinadi.
  final Map<String, TeacherProfile> teacherProfiles;

  /// Admin switch: may students change their own 学年/コース once set?
  ///
  /// UZ: Admin kaliti: talabalar o'zlarining 学年/コース larini o'rnatilgandan so'ng o'zgartira oladimi?
  final bool allowStudentEdit;

  const SchoolInfo({
    required this.domain,
    required this.name,
    required this.periods,
    required this.grades,
    required this.courses,
    this.lastSyncAt,
    this.admins = const [],
    this.teachers = const [],
    this.teacherProfiles = const {},
    this.allowStudentEdit = false,
  });

  bool isAdmin(String? uid) => uid != null && admins.contains(uid);

  bool isTeacher(String? uid, String? email) =>
      isAdmin(uid) || (email != null && teachers.contains(email.toLowerCase()));

  /// A linked student's saved 学年/コース stay fixed unless the admin allows
  /// changes. Open when either is still empty, or when the saved course is
  /// not one of this school's (stale or mistyped data must stay fixable).
  ///
  /// UZ: Bog'langan talabaning saqlangan 学年/コース lari, agar admin o'zgartirishga ruxsat
  /// bermasa, qat'iy qoladi. Ulardan biri hali bo'sh bo'lganda yoki saqlangan kurs ushbu maktabnikiga
  /// tegishli bo'lmaganda ochiq bo'ladi (eski yoki noto'g'ri kiritilgan ma'lumotlar tuzatiladigan bo'lib qolishi kerak).
  bool locksStudentClass({String? grade, String? course}) =>
      !allowStudentEdit && (grade?.isNotEmpty ?? false) && courses.contains(course);

  TeacherProfile? profileOf(String? email) => email == null ? null : teacherProfiles[email.toLowerCase()];

  /// Mirrors the server's canEditSlot: admin, the class's 担任, or the
  /// teacher named in the lesson. An empty slot (補講) also lets in anyone
  /// who teaches that class on [dayTeachers].
  ///
  /// UZ: Serverning canEditSlot funksiyasini aks ettiradi: admin, sinfning 担任 rahbari,
  /// yoki darsda nomi ko'rsatilgan o'qituvchi. Bo'sh katakcha (補講) shuningdek [dayTeachers]
  /// bo'yicha ushbu sinfga dars beradigan har qanday o'qituvchiga ruxsat beradi.
  bool canEdit({
    required String? uid,
    required String? email,
    required int grade,
    required String course,
    required SchoolSlot? slot,
    Iterable<String> dayTeachers = const [],
  }) {
    if (isAdmin(uid)) return true;
    final p = profileOf(email);
    if (p == null) return false;
    if (p.homeroomGrade == grade && p.homeroomCourse == course) return true;
    if (p.name.isEmpty) return false;
    if (slot != null) return slot.teacher.contains(p.name);
    return dayTeachers.any((t) => t.contains(p.name));
  }

  factory SchoolInfo.fromMap(String domain, Map m) {
    final sync = m['sync'];
    return SchoolInfo(
      domain: domain,
      name: _str(m['name']),
      periods: _maps(m['periods']).map(SchoolPeriod.fromMap).toList(),
      grades: m['grades'] is List
          ? (m['grades'] as List).whereType<num>().map((n) => n.toInt()).toList()
          : const [],
      courses: m['courses'] is List
          ? (m['courses'] as List).whereType<String>().toList()
          : const [],
      lastSyncAt: sync is Map ? _ts(sync['lastRunAt']) : null,
      admins: _strings(m['admins']),
      teachers: _strings(m['teachers']),
      teacherProfiles: m['teacherProfiles'] is Map
          ? {
              for (final e in (m['teacherProfiles'] as Map).entries)
                if (e.key is String && e.value is Map) e.key as String: TeacherProfile.fromMap(e.value as Map),
            }
          : const {},
      allowStudentEdit: m['allowStudentEdit'] == true,
    );
  }

  factory SchoolInfo.fromFirestore(DocumentSnapshot doc) =>
      SchoolInfo.fromMap(doc.id, (doc.data() as Map?) ?? const {});
}

/// Teacher identity model tracking the instructor display name and homeroom class assignment.
///
/// UZ: O'qituvchining ko'rsatiladigan ismi va rahbarlik sinfi biriktirilishini kuzatib boruvchi o'qituvchi shaxsi modeli.
class TeacherProfile {
  /// Name as written in the timetable file's lesson cells (e.g. 大谷).
  ///
  /// UZ: Dars jadvali faylining dars kataklarida yozilgan ism (masalan, 大谷).
  final String name;
  final int? homeroomGrade;
  final String? homeroomCourse;
  const TeacherProfile({this.name = '', this.homeroomGrade, this.homeroomCourse});

  factory TeacherProfile.fromMap(Map m) {
    final h = m['homeroom'];
    return TeacherProfile(
      name: _str(m['name']),
      homeroomGrade: h is Map && h['grade'] is num ? (h['grade'] as num).toInt() : null,
      homeroomCourse: h is Map && h['course'] is String ? h['course'] as String : null,
    );
  }
}

/// Record of a schedule adjustment or cancellation applied to a specific date and period.
///
/// UZ: Muayyan sana va dars soatiga tatbiq etilgan jadval o'zgarishi yoki bekor qilinishi yozuvi.
class SchoolChange {
  final String date, period, subject, what;
  final DateTime? at;
  const SchoolChange({
    required this.date,
    required this.period,
    required this.subject,
    required this.what,
    this.at,
  });

  factory SchoolChange.fromMap(Map m) => SchoolChange(
        date: _str(m['date']),
        period: _str(m['period']),
        subject: _str(m['subject']),
        what: _str(m['what']),
        at: _ts(m['at']),
      );
}

/// Types of slot overrides that an authorized instructor can submit for a lesson.
///
/// UZ: Vakolatli o'qituvchi dars uchun yuborishi mumkin bo'lgan katakcha o'zgarishlari turlari.
enum SchoolOverrideKind {
  cancelled,
  room,
  makeup,
  memo;

  static SchoolOverrideKind? parse(String? s) =>
      SchoolOverrideKind.values.where((v) => v.name == s).firstOrNull;
}

/// One teacher input for a slot (`school_overrides/{dayId}.items[period]`).
///
/// UZ: Katakcha uchun bitta o'qituvchi kiritmasi (`school_overrides/{dayId}.items[period]`).
class SchoolOverride {
  final SchoolOverrideKind kind;
  final String subject, teacher, room, note;

  /// The school file now shows the same thing; the file wins again.
  ///
  /// UZ: Maktab fayli endi xuddi shu narsani ko'rsatmoqda; yana fayl ustun keladi.
  final bool resolved;
  const SchoolOverride({
    required this.kind,
    this.subject = '',
    this.teacher = '',
    this.room = '',
    this.note = '',
    this.resolved = false,
  });

  /// Period key -> input; items with an unknown kind are dropped.
  ///
  /// UZ: Dars soati kaliti -> kiritma; noma'lum turdagi elementlar tashlab yuboriladi.
  static Map<String, SchoolOverride> itemsFromFirestore(DocumentSnapshot doc) {
    final items = (doc.data() as Map?)?['items'];
    if (items is! Map) return const {};
    return {
      for (final e in items.entries)
        if (e.key is String && e.value is Map)
          if (SchoolOverrideKind.parse(_str((e.value as Map)['kind'])) case final kind?)
            e.key as String: SchoolOverride(
              kind: kind,
              subject: _str(e.value['subject']),
              teacher: _str(e.value['teacher']),
              room: _str(e.value['room']),
              note: _str(e.value['note']),
              resolved: e.value['resolved'] == true,
            ),
    };
  }
}

int _periodOrder(String key) => int.tryParse(key.split(RegExp(r'\D')).first) ?? 99;

/// [day] with the unresolved teacher inputs applied (§9.3: teacher input wins
/// until the file shows the same). A 補講 may fill a period with no lesson,
/// so a day can exist from overrides alone. Returns null when nothing is left.
///
/// UZ: Hal qilinmagan o'qituvchi kiritmalari qo'llanilgan [day] (§9.3: faylda xuddi shu narsa
/// ko'ringuncha o'qituvchi kiritmasi ustun turadi). 補講 darsi bo'lmagan soatni to'ldirishi mumkin,
/// shuning uchun kun faqat o'zgarishlarning o'zidan ham mavjud bo'lishi mumkin. Hech narsa qolmasa null qaytaradi.
SchoolDay? applyOverrides(SchoolDay? day, Map<String, SchoolOverride> overrides, String date) {
  final active = {
    for (final e in overrides.entries)
      if (!e.value.resolved) e.key: e.value
  };
  if (active.isEmpty) return day;
  final slots = {for (final s in day?.slots ?? const <SchoolSlot>[]) s.period: s};
  active.forEach((period, o) {
    final base = slots[period];
    final note = o.note.isEmpty ? null : o.note;
    switch (o.kind) {
      case SchoolOverrideKind.makeup:
        slots[period] = SchoolSlot(
            period: period,
            subject: o.subject,
            teacher: o.teacher,
            room: o.room,
            note: o.note,
            status: SchoolSlotStatus.normal,
            teacherKind: o.kind);
      case SchoolOverrideKind.cancelled:
        if (base != null) slots[period] = base._teacher(o.kind, status: SchoolSlotStatus.cancelled, note: note);
      case SchoolOverrideKind.room:
        if (base != null) slots[period] = base._teacher(o.kind, room: o.room, note: note);
      case SchoolOverrideKind.memo:
        if (base != null) slots[period] = base._teacher(o.kind, note: o.note);
    }
  });
  if (slots.isEmpty) return null;
  final sorted = slots.values.toList()
    ..sort((a, b) => _periodOrder(a.period).compareTo(_periodOrder(b.period)));
  return SchoolDay(date: day?.date ?? date, slots: sorted);
}
