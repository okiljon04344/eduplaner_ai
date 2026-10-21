import 'package:edu_planner_ai/features/auth/models/school_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SchoolType.maxGrade', () {
    test('fixed-length types', () {
      expect(SchoolType.juniorHigh.maxGrade(null), 3);
      expect(SchoolType.kosen.maxGrade(null), 5);
      expect(SchoolType.vocational.maxGrade(null), 4);
      expect(SchoolType.juniorCollege.maxGrade(null), 3);
      expect(SchoolType.university.maxGrade(null), 6);
      expect(SchoolType.other.maxGrade(null), 0);
    });

    test('high school: 3 years full-time, 4 for part-time/correspondence', () {
      expect(SchoolType.highSchool.maxGrade('full_time'), 3);
      expect(SchoolType.highSchool.maxGrade('part_time'), 4);
      expect(SchoolType.highSchool.maxGrade('correspondence'), 4);
    });

    test('graduate school: master/professional 2, doctor 4', () {
      expect(SchoolType.graduate.maxGrade('master'), 2);
      expect(SchoolType.graduate.maxGrade('professional'), 2);
      expect(SchoolType.graduate.maxGrade('doctor'), 4);
    });
  });

  test('programs and defaultProgram', () {
    expect(SchoolType.highSchool.programs, ['full_time', 'part_time', 'correspondence']);
    expect(SchoolType.graduate.programs, ['master', 'doctor', 'professional']);
    expect(SchoolType.highSchool.defaultProgram, 'full_time');
    expect(SchoolType.graduate.defaultProgram, 'master');
    for (final t in SchoolType.values.where((t) => t != SchoolType.highSchool && t != SchoolType.graduate)) {
      expect(t.programs, isEmpty, reason: t.key);
      expect(t.defaultProgram, isNull, reason: t.key);
    }
  });

  test('parseGrade reads half/full-width digits from legacy free text', () {
    expect(SchoolType.parseGrade('2年生'), 2);
    expect(SchoolType.parseGrade('２年'), 2);
    expect(SchoolType.parseGrade('3'), 3);
    expect(SchoolType.parseGrade('abc'), isNull);
    expect(SchoolType.parseGrade(null), isNull);
  });

  test('fromKey resolves legacy and new keys', () {
    for (final t in SchoolType.values) {
      expect(SchoolType.fromKey(t.key), t);
    }
    expect(SchoolType.fromKey('high_school'), SchoolType.highSchool);
    expect(SchoolType.fromKey('junior_college'), SchoolType.juniorCollege);
    expect(SchoolType.fromKey('nope'), isNull);
    expect(SchoolType.fromKey(null), isNull);
  });
}
