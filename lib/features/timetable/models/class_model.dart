import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import '../../../core/constants/periods.dart';
import '../../../core/l10n/app_strings.dart';

part 'class_model.freezed.dart';
part 'class_model.g.dart';

/// Canonical storage/comparison keys for weekdays (Mon–Fri).
///
/// Always Japanese kanji regardless of the app's display locale — this is
/// the value written to and matched against in Firestore. UI code must
/// localize what it *displays* (see `DayTabRow.days`) but always compare
/// and store against this fixed list, never a localized label.
///
/// UZ: Hafta kunlari (Dush–Juma) uchun kanonik saqlash/solishtirish kalitlari.
///
/// Ilovaning ko'rsatish lokalidan qat'i nazar, har doim yapon kanjisi — bu Firestore'ga yoziladigan
/// va unga qarshi solishtiriladigan qiymatdir. UI kodi nima *ko'rsatishini* mahalliylashtirishi kerak
/// (`DayTabRow.days`ga qarang), lekin har doim mahalliylashtirilgan yorliqqa emas, ushbu qat'iy
/// ro'yxatga qarab solishtirishi va saqlashi kerak.
const List<String> kWeekdayKanji = ['月', '火', '水', '木', '金'];

/// Localized (locale-aware) display label for a canonical [kWeekdayKanji] value.
///
/// Falls back to the kanji itself if [kanji] isn't one of the five weekdays.
///
/// UZ: Kanonik [kWeekdayKanji] qiymati uchun mahalliylashtirilgan (lokalga mos) ko'rsatish yorlig'i.
///
/// Agar [kanji] beshta hafta kunidan biri bo'lmasa, kanjining o'ziga qaytadi.
String weekdayLabel(String kanji) {
  const keys = ['day_mon', 'day_tue', 'day_wed', 'day_thu', 'day_fri'];
  final index = kWeekdayKanji.indexOf(kanji);
  return index == -1 ? kanji : AppStrings.t(keys[index]);
}

/// `DateTime.monday..friday` for a canonical [kWeekdayKanji] value, or null
/// for anything else.
///
/// UZ: Kanonik [kWeekdayKanji] qiymati uchun `DateTime.monday..friday`, boshqa har qanday narsa uchun null.
int? weekdayFromKanji(String kanji) {
  final index = kWeekdayKanji.indexOf(kanji);
  return index == -1 ? null : index + 1;
}

/// Local-midnight date of the next time a class on [dayOfWeek] / [period]
/// takes place, as seen at [now].
///
/// That is today when the class's weekday is today and its period hasn't
/// ended yet, otherwise the next date with a matching weekday. A cancellation
/// or change reported now applies to this date — not to the report time.
/// Returns null for a [dayOfWeek] outside Mon–Fri.
///
/// UZ: [now] holatiga ko'ra [dayOfWeek] / [period] dagi dars keyingi safar o'tkaziladigan
/// mahalliy yarim tundagi sana.
///
/// Agar darsning hafta kuni bugun bo'lsa va uning dars soati hali tugamagan bo'lsa, u bugun bo'ladi,
/// aks holda mos keladigan hafta kuniga ega keyingi sana. Hozir xabar qilingan bekor qilish yoki
/// o'zgartirish hisobot vaqtiga emas, ushbu sanaga nisbatan qo'llaniladi.
/// Dush–Juma oralig'idan tashqaridagi [dayOfWeek] uchun null qaytaradi.
DateTime? nextClassDate({required String dayOfWeek, required int period, DateTime? now}) {
  final weekday = weekdayFromKanji(dayOfWeek);
  if (weekday == null) return null;
  final at = now ?? DateTime.now();
  final today = DateTime(at.year, at.month, at.day);
  var daysAhead = (weekday - today.weekday) % 7;
  if (daysAhead == 0) {
    final end = periodEndOn(today, period);
    if (end != null && !at.isBefore(end)) daysAhead = 7;
  }
  // Calendar arithmetic (not `+ Duration`) so a DST change can't shift the date.
  // UZ: Taqvim arifmetikasi (`+ Duration` emas), shunda DST o'zgarishi sanani siljita olmaydi.
  return DateTime(today.year, today.month, today.day + daysAhead);
}

/// Operating status of a timetable class entry, supporting normal, cancelled, or changed state.
///
/// UZ: Oddiy (normal), bekor qilingan (cancelled) yoki o'zgartirilgan (changed) holatni qo'llab-quvvatlovchi dars jadvali yozuvining ish holati.
enum ClassStatus {
  normal,
  cancelled,
  changed;

  String get label {
    switch (this) {
      case ClassStatus.normal:
        return AppStrings.t('class_status_normal');
      case ClassStatus.cancelled:
        return AppStrings.t('class_status_cancelled');
      case ClassStatus.changed:
        return AppStrings.t('class_status_changed');
    }
  }

  String get firestoreValue => name;

  static ClassStatus fromString(String value) {
    switch (value) {
      case 'cancelled':
        return ClassStatus.cancelled;
      case 'changed':
        return ClassStatus.changed;
      default:
        return ClassStatus.normal;
    }
  }
}

/// Represents a recurring timetable class entry, specifying subject, teacher, classroom,
/// day of week, period index, and current status.
///
/// UZ: Fan, o'qituvchi, xona, hafta kuni, dars soati indeksi va joriy holatni ko'rsatadigan
/// takrorlanuvchi dars jadvali yozuvini ifodalaydi.
@freezed
class ClassModel with _$ClassModel {
  const factory ClassModel({
    required String id,
    required String userId,
    required String subject,
    required String teacher,
    required String room,
    required String dayOfWeek,
    required int period,
    @Default('#4F46E5') String colorHex,
    required DateTime createdAt,
    String? groupId,
    @Default(ClassStatus.normal) ClassStatus status,
    String? statusNote,
    DateTime? statusDate,
  }) = _ClassModel;

  factory ClassModel.fromJson(Map<String, dynamic> json) => _$ClassModelFromJson(json);

  factory ClassModel.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    return ClassModel(
      id: doc.id,
      userId: d['userId'] as String? ?? '',
      subject: d['subject'] as String? ?? '',
      teacher: d['teacher'] as String? ?? '',
      room: d['room'] as String? ?? '',
      dayOfWeek: d['dayOfWeek'] as String? ?? kWeekdayKanji.first,
      period: (d['period'] as num?)?.toInt() ?? 1,
      colorHex: d['colorHex'] as String? ?? '#4F46E5',
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      groupId: d['groupId'] as String?,
      status: ClassStatus.fromString(d['status'] as String? ?? 'normal'),
      statusNote: d['statusNote'] as String?,
      statusDate: (d['statusDate'] as Timestamp?)?.toDate(),
    );
  }

  const ClassModel._();

  Map<String, dynamic> toFirestore() => {
        'userId': userId,
        'subject': subject,
        'teacher': teacher,
        'room': room,
        'dayOfWeek': dayOfWeek,
        'period': period,
        'colorHex': colorHex,
        'createdAt': Timestamp.fromDate(createdAt),
        'groupId': groupId,
        'status': status.firestoreValue,
        'statusNote': statusNote,
        'statusDate': statusDate == null ? null : Timestamp.fromDate(statusDate!),
      };

  /// Whether a 休講/変更 status is set for the calendar day of [day].
  ///
  /// [statusDate] is the date of the affected class occurrence (see
  /// [nextClassDate]), not the time the status was reported.
  ///
  /// UZ: [day] taqvim kuni uchun 休講/変更 holati o'rnatilgan yoki o'rnatilmaganligi.
  ///
  /// [statusDate] holat xabar qilingan vaqt emas, balki ta'sirlangan darsning o'tkazilish
  /// sanasidir ([nextClassDate]ga qarang).
  bool statusAppliesTo(DateTime day) {
    final date = statusDate;
    if (status == ClassStatus.normal || date == null) return false;
    return date.year == day.year && date.month == day.month && date.day == day.day;
  }

  bool get hasStatusAlertToday => statusAppliesTo(DateTime.now());

  /// Whether a 休講/変更 status is set for today or a later date — i.e. it
  /// hasn't expired yet.
  ///
  /// UZ: Bugun yoki undan keyingi sana uchun 休講/変更 holati o'rnatilgan yoki o'rnatilmaganligi — ya'ni
  /// uning muddati hali tugamaganligi.
  bool get hasStatusAlertUpcoming {
    final date = statusDate;
    if (status == ClassStatus.normal || date == null) return false;
    final now = DateTime.now();
    return !DateTime(date.year, date.month, date.day).isBefore(DateTime(now.year, now.month, now.day));
  }
}
