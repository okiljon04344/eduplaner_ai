// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'assignment_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$AssignmentModelImpl _$$AssignmentModelImplFromJson(
        Map<String, dynamic> json) =>
    _$AssignmentModelImpl(
      id: json['id'] as String,
      userId: json['userId'] as String,
      title: json['title'] as String,
      subject: json['subject'] as String,
      description: json['description'] as String?,
      dueDate: DateTime.parse(json['dueDate'] as String),
      status: $enumDecode(_$AssignmentStatusEnumMap, json['status']),
      difficulty: (json['difficulty'] as num?)?.toInt() ?? 1,
      progress: (json['progress'] as num?)?.toDouble() ?? 0.0,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );

Map<String, dynamic> _$$AssignmentModelImplToJson(
        _$AssignmentModelImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'userId': instance.userId,
      'title': instance.title,
      'subject': instance.subject,
      'description': instance.description,
      'dueDate': instance.dueDate.toIso8601String(),
      'status': _$AssignmentStatusEnumMap[instance.status]!,
      'difficulty': instance.difficulty,
      'progress': instance.progress,
      'createdAt': instance.createdAt.toIso8601String(),
    };

const _$AssignmentStatusEnumMap = {
  AssignmentStatus.notStarted: 'notStarted',
  AssignmentStatus.inProgress: 'inProgress',
  AssignmentStatus.completed: 'completed',
};
