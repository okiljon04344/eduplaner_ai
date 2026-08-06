// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'study_group_model.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

StudyGroupModel _$StudyGroupModelFromJson(Map<String, dynamic> json) {
  return _StudyGroupModel.fromJson(json);
}

/// @nodoc
mixin _$StudyGroupModel {
  String get id => throw _privateConstructorUsedError;
  String get name => throw _privateConstructorUsedError;
  String get code => throw _privateConstructorUsedError;
  String get ownerId => throw _privateConstructorUsedError;
  List<String> get memberIds => throw _privateConstructorUsedError;
  DateTime get createdAt => throw _privateConstructorUsedError;

  /// Serializes this StudyGroupModel to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of StudyGroupModel
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $StudyGroupModelCopyWith<StudyGroupModel> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $StudyGroupModelCopyWith<$Res> {
  factory $StudyGroupModelCopyWith(
          StudyGroupModel value, $Res Function(StudyGroupModel) then) =
      _$StudyGroupModelCopyWithImpl<$Res, StudyGroupModel>;
  @useResult
  $Res call(
      {String id,
      String name,
      String code,
      String ownerId,
      List<String> memberIds,
      DateTime createdAt});
}

/// @nodoc
class _$StudyGroupModelCopyWithImpl<$Res, $Val extends StudyGroupModel>
    implements $StudyGroupModelCopyWith<$Res> {
  _$StudyGroupModelCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of StudyGroupModel
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? code = null,
    Object? ownerId = null,
    Object? memberIds = null,
    Object? createdAt = null,
  }) {
    return _then(_value.copyWith(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      code: null == code
          ? _value.code
          : code // ignore: cast_nullable_to_non_nullable
              as String,
      ownerId: null == ownerId
          ? _value.ownerId
          : ownerId // ignore: cast_nullable_to_non_nullable
              as String,
      memberIds: null == memberIds
          ? _value.memberIds
          : memberIds // ignore: cast_nullable_to_non_nullable
              as List<String>,
      createdAt: null == createdAt
          ? _value.createdAt
          : createdAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$StudyGroupModelImplCopyWith<$Res>
    implements $StudyGroupModelCopyWith<$Res> {
  factory _$$StudyGroupModelImplCopyWith(_$StudyGroupModelImpl value,
          $Res Function(_$StudyGroupModelImpl) then) =
      __$$StudyGroupModelImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String id,
      String name,
      String code,
      String ownerId,
      List<String> memberIds,
      DateTime createdAt});
}

/// @nodoc
class __$$StudyGroupModelImplCopyWithImpl<$Res>
    extends _$StudyGroupModelCopyWithImpl<$Res, _$StudyGroupModelImpl>
    implements _$$StudyGroupModelImplCopyWith<$Res> {
  __$$StudyGroupModelImplCopyWithImpl(
      _$StudyGroupModelImpl _value, $Res Function(_$StudyGroupModelImpl) _then)
      : super(_value, _then);

  /// Create a copy of StudyGroupModel
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? code = null,
    Object? ownerId = null,
    Object? memberIds = null,
    Object? createdAt = null,
  }) {
    return _then(_$StudyGroupModelImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      code: null == code
          ? _value.code
          : code // ignore: cast_nullable_to_non_nullable
              as String,
      ownerId: null == ownerId
          ? _value.ownerId
          : ownerId // ignore: cast_nullable_to_non_nullable
              as String,
      memberIds: null == memberIds
          ? _value._memberIds
          : memberIds // ignore: cast_nullable_to_non_nullable
              as List<String>,
      createdAt: null == createdAt
          ? _value.createdAt
          : createdAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$StudyGroupModelImpl extends _StudyGroupModel {
  const _$StudyGroupModelImpl(
      {required this.id,
      required this.name,
      required this.code,
      required this.ownerId,
      required final List<String> memberIds,
      required this.createdAt})
      : _memberIds = memberIds,
        super._();

  factory _$StudyGroupModelImpl.fromJson(Map<String, dynamic> json) =>
      _$$StudyGroupModelImplFromJson(json);

  @override
  final String id;
  @override
  final String name;
  @override
  final String code;
  @override
  final String ownerId;
  final List<String> _memberIds;
  @override
  List<String> get memberIds {
    if (_memberIds is EqualUnmodifiableListView) return _memberIds;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_memberIds);
  }

  @override
  final DateTime createdAt;

  @override
  String toString() {
    return 'StudyGroupModel(id: $id, name: $name, code: $code, ownerId: $ownerId, memberIds: $memberIds, createdAt: $createdAt)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$StudyGroupModelImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.code, code) || other.code == code) &&
            (identical(other.ownerId, ownerId) || other.ownerId == ownerId) &&
            const DeepCollectionEquality()
                .equals(other._memberIds, _memberIds) &&
            (identical(other.createdAt, createdAt) ||
                other.createdAt == createdAt));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, id, name, code, ownerId,
      const DeepCollectionEquality().hash(_memberIds), createdAt);

  /// Create a copy of StudyGroupModel
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$StudyGroupModelImplCopyWith<_$StudyGroupModelImpl> get copyWith =>
      __$$StudyGroupModelImplCopyWithImpl<_$StudyGroupModelImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$StudyGroupModelImplToJson(
      this,
    );
  }
}

abstract class _StudyGroupModel extends StudyGroupModel {
  const factory _StudyGroupModel(
      {required final String id,
      required final String name,
      required final String code,
      required final String ownerId,
      required final List<String> memberIds,
      required final DateTime createdAt}) = _$StudyGroupModelImpl;
  const _StudyGroupModel._() : super._();

  factory _StudyGroupModel.fromJson(Map<String, dynamic> json) =
      _$StudyGroupModelImpl.fromJson;

  @override
  String get id;
  @override
  String get name;
  @override
  String get code;
  @override
  String get ownerId;
  @override
  List<String> get memberIds;
  @override
  DateTime get createdAt;

  /// Create a copy of StudyGroupModel
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$StudyGroupModelImplCopyWith<_$StudyGroupModelImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
