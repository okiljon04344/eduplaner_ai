import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'class_model.freezed.dart';
part 'class_model.g.dart';

enum ClassStatus {
  normal,
  cancelled,
  changed;

  String get label {
    switch (this) {
      case ClassStatus.normal:
        return '通常';
      case ClassStatus.cancelled:
        return '休講';
      case ClassStatus.changed:
        return '変更あり';
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

  factory ClassModel.fromJson(Map<String, dynamic> json) => _$ClassModelFromJson(json);

  factory ClassModel.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    return ClassModel(
      id: doc.id,
      userId: d['userId'] as String? ?? '',
      subject: d['subject'] as String? ?? '',
      teacher: d['teacher'] as String? ?? '',
      room: d['room'] as String? ?? '',
      dayOfWeek: d['dayOfWeek'] as String? ?? '月',
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

  bool get hasStatusAlertToday {
    if (status == ClassStatus.normal || statusDate == null) return false;
    final now = DateTime.now();
    return statusDate!.year == now.year && statusDate!.month == now.month && statusDate!.day == now.day;
  }
}
