import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'class_model.freezed.dart';
part 'class_model.g.dart';

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
      };
}
