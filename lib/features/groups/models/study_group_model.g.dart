// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'study_group_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$StudyGroupModelImpl _$$StudyGroupModelImplFromJson(
        Map<String, dynamic> json) =>
    _$StudyGroupModelImpl(
      id: json['id'] as String,
      name: json['name'] as String,
      code: json['code'] as String,
      ownerId: json['ownerId'] as String,
      memberIds:
          (json['memberIds'] as List<dynamic>).map((e) => e as String).toList(),
      createdAt: DateTime.parse(json['createdAt'] as String),
    );

Map<String, dynamic> _$$StudyGroupModelImplToJson(
        _$StudyGroupModelImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'code': instance.code,
      'ownerId': instance.ownerId,
      'memberIds': instance.memberIds,
      'createdAt': instance.createdAt.toIso8601String(),
    };
