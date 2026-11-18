import 'package:flutter/foundation.dart' show immutable, listEquals;

/// Role of a person in the school system; determines the masking token prefix.
enum PersonRole {
  student,
  teacher;

  String get tokenPrefix => switch (this) {
        PersonRole.student => 'STUDENT',
        PersonRole.teacher => 'TEACHER',
      };
}

/// Immutable representation of a real person's name and known variants
/// (family name, given name, hiragana, katakana, romaji) used by the
/// privacy anonymizer.
@immutable
class PersonName {
  final String id;
  final String fullName;
  final PersonRole role;
  final List<String> parts;

  const PersonName({
    required this.id,
    required this.fullName,
    required this.role,
    this.parts = const [],
  });

  String get tokenPrefix => role.tokenPrefix;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PersonName &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          fullName == other.fullName &&
          role == other.role &&
          listEquals(parts, other.parts);

  @override
  int get hashCode => Object.hash(id, fullName, role, Object.hashAll(parts));

  /// Deliberately omits [fullName] and [parts] so real names never leak into logs.
  @override
  String toString() => 'PersonName(id: $id, role: ${role.name})';
}
