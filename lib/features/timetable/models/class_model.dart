import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import '../../../core/constants/periods.dart';
import '../../../core/l10n/app_strings.dart';

part 'class_model.freezed.dart';
part 'class_model.g.dart';

/// Weekday keys (Mon–Fri) as stored in Firestore. Always kanji regardless of
/// locale: display via [weekdayLabel], but store and compare against this list.
const List<String> kWeekdayKanji = ['月', '火', '水', '木', '金'];

/// Localized label for a [kWeekdayKanji] value; returns [kanji] unchanged if unknown.
String weekdayLabel(String kanji) {
  const keys = ['day_mon', 'day_tue', 'day_wed', 'day_thu', 'day_fri'];
  final index = kWeekdayKanji.indexOf(kanji);
  return index == -1 ? kanji : AppStrings.t(keys[index]);
}

/// `DateTime.monday..friday` for a [kWeekdayKanji] value, or null.
int? weekdayFromKanji(String kanji) {
  final index = kWeekdayKanji.indexOf(kanji);
  return index == -1 ? null : index + 1;
}

/// Local-midnight date of the next occurrence of a class, as seen at [now]:
/// today if the weekday matches and the period hasn't ended, else the next
/// matching weekday. A cancellation reported now applies to this date, not to
/// the report time. Null for a [dayOfWeek] outside Mon–Fri.
DateTime? nextClassDate(
    {required String dayOfWeek, required int period, DateTime? now}) {
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
  return DateTime(today.year, today.month, today.day + daysAhead);
}

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

  factory ClassModel.fromJson(Map<String, dynamic> json) =>
      _$ClassModelFromJson(json);

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
        'statusDate':
            statusDate == null ? null : Timestamp.fromDate(statusDate!),
      };

  /// Whether a cancellation/change is set for the calendar day of [day].
  /// [statusDate] is the affected occurrence (see [nextClassDate]), not the report time.
  bool statusAppliesTo(DateTime day) {
    final date = statusDate;
    if (status == ClassStatus.normal || date == null) return false;
    return date.year == day.year &&
        date.month == day.month &&
        date.day == day.day;
  }

  bool get hasStatusAlertToday => statusAppliesTo(DateTime.now());

  /// Whether a cancellation/change is set for today or later (not yet expired).
  bool get hasStatusAlertUpcoming {
    final date = statusDate;
    if (status == ClassStatus.normal || date == null) return false;
    final now = DateTime.now();
    return !DateTime(date.year, date.month, date.day)
        .isBefore(DateTime(now.year, now.month, now.day));
  }
}
