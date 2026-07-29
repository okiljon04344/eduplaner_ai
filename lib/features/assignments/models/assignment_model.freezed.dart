// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'assignment_model.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

AssignmentModel _$AssignmentModelFromJson(Map<String, dynamic> json) {
  return _AssignmentModel.fromJson(json);
}

/// @nodoc
mixin _$AssignmentModel {
  String get id => throw _privateConstructorUsedError;
  String get userId => throw _privateConstructorUsedError;
  String get title => throw _privateConstructorUsedError;
  String get subject => throw _privateConstructorUsedError;
  String? get description => throw _privateConstructorUsedError;
  DateTime get dueDate => throw _privateConstructorUsedError;
  AssignmentStatus get status => throw _privateConstructorUsedError;
  int get difficulty => throw _privateConstructorUsedError;
  double get progress => throw _privateConstructorUsedError;
  DateTime get createdAt => throw _privateConstructorUsedError;

  /// Serializes this AssignmentModel to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of AssignmentModel
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $AssignmentModelCopyWith<AssignmentModel> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $AssignmentModelCopyWith<$Res> {
  factory $AssignmentModelCopyWith(
          AssignmentModel value, $Res Function(AssignmentModel) then) =
      _$AssignmentModelCopyWithImpl<$Res, AssignmentModel>;
  @useResult
  $Res call(
      {String id,
      String userId,
      String title,
      String subject,
      String? description,
      DateTime dueDate,
      AssignmentStatus status,
      int difficulty,
      double progress,
      DateTime createdAt});
}

/// @nodoc
class _$AssignmentModelCopyWithImpl<$Res, $Val extends AssignmentModel>
    implements $AssignmentModelCopyWith<$Res> {
  _$AssignmentModelCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of AssignmentModel
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? userId = null,
    Object? title = null,
    Object? subject = null,
    Object? description = freezed,
    Object? dueDate = null,
    Object? status = null,
    Object? difficulty = null,
    Object? progress = null,
    Object? createdAt = null,
  }) {
    return _then(_value.copyWith(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      userId: null == userId
          ? _value.userId
          : userId // ignore: cast_nullable_to_non_nullable
              as String,
      title: null == title
          ? _value.title
          : title // ignore: cast_nullable_to_non_nullable
              as String,
      subject: null == subject
          ? _value.subject
          : subject // ignore: cast_nullable_to_non_nullable
              as String,
      description: freezed == description
          ? _value.description
          : description // ignore: cast_nullable_to_non_nullable
              as String?,
      dueDate: null == dueDate
          ? _value.dueDate
          : dueDate // ignore: cast_nullable_to_non_nullable
              as DateTime,
      status: null == status
          ? _value.status
          : status // ignore: cast_nullable_to_non_nullable
              as AssignmentStatus,
      difficulty: null == difficulty
          ? _value.difficulty
          : difficulty // ignore: cast_nullable_to_non_nullable
              as int,
      progress: null == progress
          ? _value.progress
          : progress // ignore: cast_nullable_to_non_nullable
              as double,
      createdAt: null == createdAt
          ? _value.createdAt
          : createdAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$AssignmentModelImplCopyWith<$Res>
    implements $AssignmentModelCopyWith<$Res> {
  factory _$$AssignmentModelImplCopyWith(_$AssignmentModelImpl value,
          $Res Function(_$AssignmentModelImpl) then) =
      __$$AssignmentModelImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String id,
      String userId,
      String title,
      String subject,
      String? description,
      DateTime dueDate,
      AssignmentStatus status,
      int difficulty,
      double progress,
      DateTime createdAt});
}

/// @nodoc
class __$$AssignmentModelImplCopyWithImpl<$Res>
    extends _$AssignmentModelCopyWithImpl<$Res, _$AssignmentModelImpl>
    implements _$$AssignmentModelImplCopyWith<$Res> {
  __$$AssignmentModelImplCopyWithImpl(
      _$AssignmentModelImpl _value, $Res Function(_$AssignmentModelImpl) _then)
      : super(_value, _then);

  /// Create a copy of AssignmentModel
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? userId = null,
    Object? title = null,
    Object? subject = null,
    Object? description = freezed,
    Object? dueDate = null,
    Object? status = null,
    Object? difficulty = null,
    Object? progress = null,
    Object? createdAt = null,
  }) {
    return _then(_$AssignmentModelImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      userId: null == userId
          ? _value.userId
          : userId // ignore: cast_nullable_to_non_nullable
              as String,
      title: null == title
          ? _value.title
          : title // ignore: cast_nullable_to_non_nullable
              as String,
      subject: null == subject
          ? _value.subject
          : subject // ignore: cast_nullable_to_non_nullable
              as String,
      description: freezed == description
          ? _value.description
          : description // ignore: cast_nullable_to_non_nullable
              as String?,
      dueDate: null == dueDate
          ? _value.dueDate
          : dueDate // ignore: cast_nullable_to_non_nullable
              as DateTime,
      status: null == status
          ? _value.status
          : status // ignore: cast_nullable_to_non_nullable
              as AssignmentStatus,
      difficulty: null == difficulty
          ? _value.difficulty
          : difficulty // ignore: cast_nullable_to_non_nullable
              as int,
      progress: null == progress
          ? _value.progress
          : progress // ignore: cast_nullable_to_non_nullable
              as double,
      createdAt: null == createdAt
          ? _value.createdAt
          : createdAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$AssignmentModelImpl extends _AssignmentModel {
  const _$AssignmentModelImpl(
      {required this.id,
      required this.userId,
      required this.title,
      required this.subject,
      this.description,
      required this.dueDate,
      required this.status,
      this.difficulty = 1,
      this.progress = 0.0,
      required this.createdAt})
      : super._();

  factory _$AssignmentModelImpl.fromJson(Map<String, dynamic> json) =>
      _$$AssignmentModelImplFromJson(json);

  @override
  final String id;
  @override
  final String userId;
  @override
  final String title;
  @override
  final String subject;
  @override
  final String? description;
  @override
  final DateTime dueDate;
  @override
  final AssignmentStatus status;
  @override
  @JsonKey()
  final int difficulty;
  @override
  @JsonKey()
  final double progress;
  @override
  final DateTime createdAt;

  @override
  String toString() {
    return 'AssignmentModel(id: $id, userId: $userId, title: $title, subject: $subject, description: $description, dueDate: $dueDate, status: $status, difficulty: $difficulty, progress: $progress, createdAt: $createdAt)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$AssignmentModelImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.userId, userId) || other.userId == userId) &&
            (identical(other.title, title) || other.title == title) &&
            (identical(other.subject, subject) || other.subject == subject) &&
            (identical(other.description, description) ||
                other.description == description) &&
            (identical(other.dueDate, dueDate) || other.dueDate == dueDate) &&
            (identical(other.status, status) || other.status == status) &&
            (identical(other.difficulty, difficulty) ||
                other.difficulty == difficulty) &&
            (identical(other.progress, progress) ||
                other.progress == progress) &&
            (identical(other.createdAt, createdAt) ||
                other.createdAt == createdAt));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, id, userId, title, subject,
      description, dueDate, status, difficulty, progress, createdAt);

  /// Create a copy of AssignmentModel
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$AssignmentModelImplCopyWith<_$AssignmentModelImpl> get copyWith =>
      __$$AssignmentModelImplCopyWithImpl<_$AssignmentModelImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$AssignmentModelImplToJson(
      this,
    );
  }
}

abstract class _AssignmentModel extends AssignmentModel {
  const factory _AssignmentModel(
      {required final String id,
      required final String userId,
      required final String title,
      required final String subject,
      final String? description,
      required final DateTime dueDate,
      required final AssignmentStatus status,
      final int difficulty,
      final double progress,
      required final DateTime createdAt}) = _$AssignmentModelImpl;
  const _AssignmentModel._() : super._();

  factory _AssignmentModel.fromJson(Map<String, dynamic> json) =
      _$AssignmentModelImpl.fromJson;

  @override
  String get id;
  @override
  String get userId;
  @override
  String get title;
  @override
  String get subject;
  @override
  String? get description;
  @override
  DateTime get dueDate;
  @override
  AssignmentStatus get status;
  @override
  int get difficulty;
  @override
  double get progress;
  @override
  DateTime get createdAt;

  /// Create a copy of AssignmentModel
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$AssignmentModelImplCopyWith<_$AssignmentModelImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
