import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'study_group_model.freezed.dart';
part 'study_group_model.g.dart';

@freezed
class StudyGroupModel with _$StudyGroupModel {
  const factory StudyGroupModel({
    required String id,
    required String name,
    required String code,
    required String ownerId,
    required List<String> memberIds,
    required DateTime createdAt,
  }) = _StudyGroupModel;

  factory StudyGroupModel.fromJson(Map<String, dynamic> json) => _$StudyGroupModelFromJson(json);

  factory StudyGroupModel.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    return StudyGroupModel(
      id: doc.id,
      name: d['name'] as String? ?? '',
      code: d['code'] as String? ?? '',
      ownerId: d['ownerId'] as String? ?? '',
      memberIds: (d['memberIds'] as List<dynamic>? ?? []).map((e) => e.toString()).toList(),
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  const StudyGroupModel._();

  Map<String, dynamic> toFirestore() => {
        'name': name,
        'code': code,
        'ownerId': ownerId,
        'memberIds': memberIds,
        'createdAt': Timestamp.fromDate(createdAt),
      };
}
