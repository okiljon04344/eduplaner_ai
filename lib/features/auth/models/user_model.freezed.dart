// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'user_model.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

UserModel _$UserModelFromJson(Map<String, dynamic> json) {
  return _UserModel.fromJson(json);
}

/// @nodoc
mixin _$UserModel {
  String get uid => throw _privateConstructorUsedError;
  String get name => throw _privateConstructorUsedError;
  String get email => throw _privateConstructorUsedError;
  String? get photoUrl => throw _privateConstructorUsedError;
  String? get classId => throw _privateConstructorUsedError;
  String? get school => throw _privateConstructorUsedError;
  String? get schoolType => throw _privateConstructorUsedError;
  String? get grade => throw _privateConstructorUsedError;
  String? get program => throw _privateConstructorUsedError;
  String? get faculty => throw _privateConstructorUsedError;
  String? get department => throw _privateConstructorUsedError;
  String? get course => throw _privateConstructorUsedError;
  DateTime get createdAt => throw _privateConstructorUsedError;

  /// Serializes this UserModel to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of UserModel
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $UserModelCopyWith<UserModel> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $UserModelCopyWith<$Res> {
  factory $UserModelCopyWith(UserModel value, $Res Function(UserModel) then) =
      _$UserModelCopyWithImpl<$Res, UserModel>;
  @useResult
  $Res call(
      {String uid,
      String name,
      String email,
      String? photoUrl,
      String? classId,
      String? school,
      String? schoolType,
      String? grade,
      String? program,
      String? faculty,
      String? department,
      String? course,
      DateTime createdAt});
}

/// @nodoc
class _$UserModelCopyWithImpl<$Res, $Val extends UserModel>
    implements $UserModelCopyWith<$Res> {
  _$UserModelCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of UserModel
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? uid = null,
    Object? name = null,
    Object? email = null,
    Object? photoUrl = freezed,
    Object? classId = freezed,
    Object? school = freezed,
    Object? schoolType = freezed,
    Object? grade = freezed,
    Object? program = freezed,
    Object? faculty = freezed,
    Object? department = freezed,
    Object? course = freezed,
    Object? createdAt = null,
  }) {
    return _then(_value.copyWith(
      uid: null == uid
          ? _value.uid
          : uid // ignore: cast_nullable_to_non_nullable
              as String,
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      email: null == email
          ? _value.email
          : email // ignore: cast_nullable_to_non_nullable
              as String,
      photoUrl: freezed == photoUrl
          ? _value.photoUrl
          : photoUrl // ignore: cast_nullable_to_non_nullable
              as String?,
      classId: freezed == classId
          ? _value.classId
          : classId // ignore: cast_nullable_to_non_nullable
              as String?,
      school: freezed == school
          ? _value.school
          : school // ignore: cast_nullable_to_non_nullable
              as String?,
      schoolType: freezed == schoolType
          ? _value.schoolType
          : schoolType // ignore: cast_nullable_to_non_nullable
              as String?,
      grade: freezed == grade
          ? _value.grade
          : grade // ignore: cast_nullable_to_non_nullable
              as String?,
      program: freezed == program
          ? _value.program
          : program // ignore: cast_nullable_to_non_nullable
              as String?,
      faculty: freezed == faculty
          ? _value.faculty
          : faculty // ignore: cast_nullable_to_non_nullable
              as String?,
      department: freezed == department
          ? _value.department
          : department // ignore: cast_nullable_to_non_nullable
              as String?,
      course: freezed == course
          ? _value.course
          : course // ignore: cast_nullable_to_non_nullable
              as String?,
      createdAt: null == createdAt
          ? _value.createdAt
          : createdAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$UserModelImplCopyWith<$Res>
    implements $UserModelCopyWith<$Res> {
  factory _$$UserModelImplCopyWith(
          _$UserModelImpl value, $Res Function(_$UserModelImpl) then) =
      __$$UserModelImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String uid,
      String name,
      String email,
      String? photoUrl,
      String? classId,
      String? school,
      String? schoolType,
      String? grade,
      String? program,
      String? faculty,
      String? department,
      String? course,
      DateTime createdAt});
}

/// @nodoc
class __$$UserModelImplCopyWithImpl<$Res>
    extends _$UserModelCopyWithImpl<$Res, _$UserModelImpl>
    implements _$$UserModelImplCopyWith<$Res> {
  __$$UserModelImplCopyWithImpl(
      _$UserModelImpl _value, $Res Function(_$UserModelImpl) _then)
      : super(_value, _then);

  /// Create a copy of UserModel
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? uid = null,
    Object? name = null,
    Object? email = null,
    Object? photoUrl = freezed,
    Object? classId = freezed,
    Object? school = freezed,
    Object? schoolType = freezed,
    Object? grade = freezed,
    Object? program = freezed,
    Object? faculty = freezed,
    Object? department = freezed,
    Object? course = freezed,
    Object? createdAt = null,
  }) {
    return _then(_$UserModelImpl(
      uid: null == uid
          ? _value.uid
          : uid // ignore: cast_nullable_to_non_nullable
              as String,
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      email: null == email
          ? _value.email
          : email // ignore: cast_nullable_to_non_nullable
              as String,
      photoUrl: freezed == photoUrl
          ? _value.photoUrl
          : photoUrl // ignore: cast_nullable_to_non_nullable
              as String?,
      classId: freezed == classId
          ? _value.classId
          : classId // ignore: cast_nullable_to_non_nullable
              as String?,
      school: freezed == school
          ? _value.school
          : school // ignore: cast_nullable_to_non_nullable
              as String?,
      schoolType: freezed == schoolType
          ? _value.schoolType
          : schoolType // ignore: cast_nullable_to_non_nullable
              as String?,
      grade: freezed == grade
          ? _value.grade
          : grade // ignore: cast_nullable_to_non_nullable
              as String?,
      program: freezed == program
          ? _value.program
          : program // ignore: cast_nullable_to_non_nullable
              as String?,
      faculty: freezed == faculty
          ? _value.faculty
          : faculty // ignore: cast_nullable_to_non_nullable
              as String?,
      department: freezed == department
          ? _value.department
          : department // ignore: cast_nullable_to_non_nullable
              as String?,
      course: freezed == course
          ? _value.course
          : course // ignore: cast_nullable_to_non_nullable
              as String?,
      createdAt: null == createdAt
          ? _value.createdAt
          : createdAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$UserModelImpl extends _UserModel {
  const _$UserModelImpl(
      {required this.uid,
      required this.name,
      required this.email,
      this.photoUrl,
      this.classId,
      this.school,
      this.schoolType,
      this.grade,
      this.program,
      this.faculty,
      this.department,
      this.course,
      required this.createdAt})
      : super._();

  factory _$UserModelImpl.fromJson(Map<String, dynamic> json) =>
      _$$UserModelImplFromJson(json);

  @override
  final String uid;
  @override
  final String name;
  @override
  final String email;
  @override
  final String? photoUrl;
  @override
  final String? classId;
  @override
  final String? school;
  @override
  final String? schoolType;
  @override
  final String? grade;
  @override
  final String? program;
  @override
  final String? faculty;
  @override
  final String? department;
  @override
  final String? course;
  @override
  final DateTime createdAt;

  @override
  String toString() {
    return 'UserModel(uid: $uid, name: $name, email: $email, photoUrl: $photoUrl, classId: $classId, school: $school, schoolType: $schoolType, grade: $grade, program: $program, faculty: $faculty, department: $department, course: $course, createdAt: $createdAt)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$UserModelImpl &&
            (identical(other.uid, uid) || other.uid == uid) &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.email, email) || other.email == email) &&
            (identical(other.photoUrl, photoUrl) ||
                other.photoUrl == photoUrl) &&
            (identical(other.classId, classId) || other.classId == classId) &&
            (identical(other.school, school) || other.school == school) &&
            (identical(other.schoolType, schoolType) ||
                other.schoolType == schoolType) &&
            (identical(other.grade, grade) || other.grade == grade) &&
            (identical(other.program, program) || other.program == program) &&
            (identical(other.faculty, faculty) || other.faculty == faculty) &&
            (identical(other.department, department) ||
                other.department == department) &&
            (identical(other.course, course) || other.course == course) &&
            (identical(other.createdAt, createdAt) ||
                other.createdAt == createdAt));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      uid,
      name,
      email,
      photoUrl,
      classId,
      school,
      schoolType,
      grade,
      program,
      faculty,
      department,
      course,
      createdAt);

  /// Create a copy of UserModel
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$UserModelImplCopyWith<_$UserModelImpl> get copyWith =>
      __$$UserModelImplCopyWithImpl<_$UserModelImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$UserModelImplToJson(
      this,
    );
  }
}

abstract class _UserModel extends UserModel {
  const factory _UserModel(
      {required final String uid,
      required final String name,
      required final String email,
      final String? photoUrl,
      final String? classId,
      final String? school,
      final String? schoolType,
      final String? grade,
      final String? program,
      final String? faculty,
      final String? department,
      final String? course,
      required final DateTime createdAt}) = _$UserModelImpl;
  const _UserModel._() : super._();

  factory _UserModel.fromJson(Map<String, dynamic> json) =
      _$UserModelImpl.fromJson;

  @override
  String get uid;
  @override
  String get name;
  @override
  String get email;
  @override
  String? get photoUrl;
  @override
  String? get classId;
  @override
  String? get school;
  @override
  String? get schoolType;
  @override
  String? get grade;
  @override
  String? get program;
  @override
  String? get faculty;
  @override
  String? get department;
  @override
  String? get course;
  @override
  DateTime get createdAt;

  /// Create a copy of UserModel
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$UserModelImplCopyWith<_$UserModelImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
