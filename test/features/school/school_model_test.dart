import 'package:flutter_test/flutter_test.dart';
import 'package:edu_planner_ai/features/auth/models/school_type.dart';
import 'package:edu_planner_ai/features/school/models/school.dart';
import 'package:edu_planner_ai/features/school/school_repository.dart';

void main() {
  test('SchoolInfo.fromMap parses periods and courses', () {
    final info = SchoolInfo.fromMap('school.test', {
      'name': 'Test School',
      'periods': [
        {'key': '1-2', 'label': '1・2限', 'start': '09:00', 'end': '10:30'},
        {'key': '3', 'label': '3限', 'start': 'bad', 'end': ''},
      ],
      'grades': [1, 2],
      'courses': ['農業', '観光'],
    });
    expect(info.domain, 'school.test');
    expect(info.name, 'Test School');
    expect(info.periods.first.key, '1-2');
    expect(info.periods.first.start, (9, 0));
    expect(info.periods.first.end, (10, 30));
    expect(info.periods[1].start, (0, 0));
    expect(info.periods[1].end, (0, 0));
    expect(info.grades, [1, 2]);
    expect(info.courses, ['農業', '観光']);
    expect(info.lastSyncAt, isNull);
  });

  test('SchoolInfo.fromMap tolerates missing fields', () {
    final info = SchoolInfo.fromMap('d', {});
    expect(info.periods, isEmpty);
    expect(info.grades, isEmpty);
    expect(info.courses, isEmpty);
  });

  test('SchoolSlotStatus.parse falls back to normal', () {
    expect(SchoolSlotStatus.parse('cancelled'), SchoolSlotStatus.cancelled);
    expect(SchoolSlotStatus.parse('elective'), SchoolSlotStatus.elective);
    expect(SchoolSlotStatus.parse('???'), SchoolSlotStatus.normal);
    expect(SchoolSlotStatus.parse(null), SchoolSlotStatus.normal);
  });

  test('SchoolDay.fromMap parses slots', () {
    final day = SchoolDay.fromMap({
      'date': '2026-10-26',
      'slots': [
        {'period': '1-2', 'subject': '数学', 'teacher': '田中', 'status': 'event'},
      ],
    });
    expect(day.date, '2026-10-26');
    expect(day.slots.single.subject, '数学');
    expect(day.slots.single.room, '');
    expect(day.slots.single.status, SchoolSlotStatus.event);
  });

  test('SchoolChange.fromMap parses items', () {
    final c = SchoolChange.fromMap(
        {'date': '2026-10-26', 'period': '3', 'subject': '英語', 'what': '休講'});
    expect(c.what, '休講');
    expect(c.at, isNull);
  });

  test('dayId matches server format', () {
    expect(SchoolRepository.dayId('school.test', 1, '農業', DateTime(2026, 10, 26)),
        'school.test_1_農業_20261026');
  });

  test('domainFrom returns null for unverified or empty email', () {
    expect(SchoolRepository.domainFrom('a@School.Test', false), isNull);
    expect(SchoolRepository.domainFrom(null, true), isNull);
    expect(SchoolRepository.domainFrom('noat', true), isNull);
    expect(SchoolRepository.domainFrom('a@', true), isNull);
  });

  test('domainFrom lowercases the part after the last @', () {
    expect(SchoolRepository.domainFrom('a@School.Test', true), 'school.test');
    expect(SchoolRepository.domainFrom('a@b@X.jp', true), 'x.jp');
  });

  test('SchoolSlot.fromMap tolerates a non-string status', () {
    final slot = SchoolSlot.fromMap({'period': '1', 'status': 5, 'subject': 3});
    expect(slot.status, SchoolSlotStatus.normal);
    expect(slot.subject, '');
  });

  test('legacy grade text parses via SchoolType.parseGrade', () {
    expect(SchoolType.parseGrade('２年生'), 2);
    expect(SchoolType.parseGrade('3'), 3);
    expect(SchoolType.parseGrade(null), isNull);
  });

  test('applyOverrides: teacher input wins until resolved', () {
    const day = SchoolDay(date: '2026-10-29', slots: [
      SchoolSlot(period: '3-4', subject: '英語', teacher: '田中', room: '102', note: '', status: SchoolSlotStatus.normal),
      SchoolSlot(period: '1-2', subject: '数学', teacher: '鈴木', room: '201', note: '', status: SchoolSlotStatus.normal),
    ]);
    final out = applyOverrides(day, const {
      '3-4': SchoolOverride(kind: SchoolOverrideKind.room, room: '第2PC室'),
      '1-2': SchoolOverride(kind: SchoolOverrideKind.cancelled, note: '自習'),
      '5-6': SchoolOverride(kind: SchoolOverrideKind.makeup, subject: '簿記', room: '103'),
      '7-8': SchoolOverride(kind: SchoolOverrideKind.memo, note: 'no lesson, ignored'),
    }, '2026-10-29')!;
    expect(out.slots.map((s) => s.period), ['1-2', '3-4', '5-6']);
    expect(out.slots[0].status, SchoolSlotStatus.cancelled);
    expect(out.slots[0].note, '自習');
    expect(out.slots[1].room, '第2PC室');
    expect(out.slots[1].subject, '英語');
    expect(out.slots[2].subject, '簿記');
    expect(out.slots.every((s) => s.byTeacher), isTrue);

    final resolved = applyOverrides(day, const {
      '3-4': SchoolOverride(kind: SchoolOverrideKind.room, room: '第2PC室', resolved: true),
    }, '2026-10-29');
    expect(identical(resolved, day), isTrue);

    final onlyMakeup = applyOverrides(null, const {
      '1-2': SchoolOverride(kind: SchoolOverrideKind.makeup, subject: '補講'),
    }, '2026-10-30')!;
    expect(onlyMakeup.date, '2026-10-30');
    expect(applyOverrides(null, const {'1-2': SchoolOverride(kind: SchoolOverrideKind.cancelled)}, 'x'), isNull);
  });

  test('SchoolInfo roles', () {
    final info = SchoolInfo.fromMap('school.test', {
      'admins': ['u1'],
      'teachers': ['tanaka@school.test'],
    });
    expect(info.isAdmin('u1'), isTrue);
    expect(info.isTeacher('u1', null), isTrue);
    expect(info.isTeacher('u2', 'Tanaka@School.test'), isTrue);
    expect(info.isTeacher('u2', 's123@school.test'), isFalse);
  });

  test('SchoolInfo.canEdit mirrors the server edit scope', () {
    final info = SchoolInfo.fromMap('school.test', {
      'admins': ['a1'],
      'teachers': ['tanaka@school.test', 'suzuki@school.test'],
      'teacherProfiles': {
        'tanaka@school.test': {'name': '田中', 'homeroom': null},
        'suzuki@school.test': {'name': '鈴木', 'homeroom': {'grade': 1, 'course': '農業'}},
      },
    });
    const eng = SchoolSlot(period: '3-4', subject: '英語', teacher: '田中【102】', room: '102', note: '', status: SchoolSlotStatus.normal);
    bool can(String? uid, String? email, {String course = '農業', SchoolSlot? slot = eng, List<String> day = const []}) =>
        info.canEdit(uid: uid, email: email, grade: 1, course: course, slot: slot, dayTeachers: day);
    expect(can('a1', null), isTrue);
    expect(can('u1', 'Tanaka@school.test'), isTrue);
    expect(can('u2', 'suzuki@school.test'), isTrue, reason: 'homeroom');
    expect(can('u2', 'suzuki@school.test', course: '観光'), isFalse);
    expect(can('u3', 'other@school.test'), isFalse);
    expect(can('u1', 'tanaka@school.test', slot: null, day: ['佐藤', '田中【102】']), isTrue);
    expect(can('u1', 'tanaka@school.test', slot: null, day: ['佐藤']), isFalse);
  });

  test('locksStudentClass: first save open, later locked unless allowed', () {
    final locked = SchoolInfo.fromMap('school.test', const {'courses': ['農業', '観光']});
    final open = SchoolInfo.fromMap('school.test', const {'allowStudentEdit': true, 'courses': ['農業']});
    expect(locked.locksStudentClass(grade: null, course: null), isFalse);
    expect(locked.locksStudentClass(grade: '1', course: ''), isFalse);
    expect(locked.locksStudentClass(grade: '1', course: '農業'), isTrue);
    expect(locked.locksStudentClass(grade: '2', course: '商工業'), isFalse, reason: 'not a school course: fixable');
    expect(open.locksStudentClass(grade: '1', course: '農業'), isFalse);
  });
}
