import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'user_model.freezed.dart';
part 'user_model.g.dart';

/// Represents an authenticated user profile stored in Firestore, holding identity details
/// and academic affiliation attributes (school type, grade, faculty, department).
///
/// UZ: Firestore da saqlanadigan autentifikatsiyadan o'tgan foydalanuvchi profilini ifodalaydi,
/// shaxsiy ma'lumotlar va o'quv mansubligi atributlarini (maktab turi, bosqich, fakultet, kafedra/bo'lim) saqlaydi.
@freezed
class UserModel with _$UserModel {
  const factory UserModel({
    required String uid,
    required String name,
    required String email,
    String? photoUrl,
    String? classId,
    String? school,
    String? schoolType,
    String? grade,
    String? program,
    String? faculty,
    String? department,
    String? course,
    String? schoolDomain,
    required DateTime createdAt,
  }) = _UserModel;

  factory UserModel.fromJson(Map<String, dynamic> json) => _$UserModelFromJson(json);

  factory UserModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return UserModel(
      uid: doc.id,
      name: data['name'] as String? ?? '',
      email: data['email'] as String? ?? '',
      photoUrl: data['photoUrl'] as String?,
      classId: data['classId'] as String?,
      school: data['school'] as String?,
      schoolType: data['schoolType'] as String?,
      grade: data['grade'] as String?,
      program: data['program'] as String?,
      faculty: data['faculty'] as String?,
      department: data['department'] as String?,
      course: data['course'] as String?,
      schoolDomain: data['schoolDomain'] as String?,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  const UserModel._();

  /// True once the mandatory school-profile setup step is done. `schoolType`
  /// is the gate — it's only ever written together with `school` by
  /// [AuthRepository.saveSchoolProfile], never independently, so checking it
  /// alone is enough to know the whole step was completed.
  ///
  /// UZ: Majburiy maktab profili sozlash bosqichi bajarilgandan so'ng true bo'ladi.
  /// `schoolType` asosiy shartdir — u faqat [AuthRepository.saveSchoolProfile] tomonidan
  /// `school` bilan birga yoziladi, hech qachon mustaqil yozilmaydi, shuning uchun faqat uni
  /// tekshirish butun bosqich yakunlanganini bilish uchun yetarlidir.
  bool get profileComplete => schoolType != null && schoolType!.isNotEmpty;

  Map<String, dynamic> toFirestore() => {
        'name': name,
        'email': email,
        'photoUrl': photoUrl,
        'classId': classId,
        'school': school,
        'schoolType': schoolType,
        'grade': grade,
        'program': program,
        'faculty': faculty,
        'department': department,
        'course': course,
        'schoolDomain': schoolDomain,
        'createdAt': Timestamp.fromDate(createdAt),
      };
}
