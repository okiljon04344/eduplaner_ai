// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'class_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$ClassModelImpl _$$ClassModelImplFromJson(Map<String, dynamic> json) =>
    _$ClassModelImpl(
      id: json['id'] as String,
      userId: json['userId'] as String,
      subject: json['subject'] as String,
      teacher: json['teacher'] as String,
      room: json['room'] as String,
      dayOfWeek: json['dayOfWeek'] as String,
      period: (json['period'] as num).toInt(),
      colorHex: json['colorHex'] as String? ?? '#4F46E5',
      createdAt: DateTime.parse(json['createdAt'] as String),
      groupId: json['groupId'] as String?,
      status: $enumDecodeNullable(_$ClassStatusEnumMap, json['status']) ??
          ClassStatus.normal,
      statusNote: json['statusNote'] as String?,
      statusDate: json['statusDate'] == null
          ? null
          : DateTime.parse(json['statusDate'] as String),
    );

Map<String, dynamic> _$$ClassModelImplToJson(_$ClassModelImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'userId': instance.userId,
      'subject': instance.subject,
      'teacher': instance.teacher,
      'room': instance.room,
      'dayOfWeek': instance.dayOfWeek,
      'period': instance.period,
      'colorHex': instance.colorHex,
      'createdAt': instance.createdAt.toIso8601String(),
      'groupId': instance.groupId,
      'status': _$ClassStatusEnumMap[instance.status]!,
      'statusNote': instance.statusNote,
      'statusDate': instance.statusDate?.toIso8601String(),
    };

const _$ClassStatusEnumMap = {
  ClassStatus.normal: 'normal',
  ClassStatus.cancelled: 'cancelled',
  ClassStatus.changed: 'changed',
};
