import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:edu_planner_ai/features/auth/models/user_model.dart';
import 'package:edu_planner_ai/features/school/models/school.dart';
import 'package:edu_planner_ai/features/timetable/models/timetable_import_models.dart';

void main() {
  group('ParseMethod', () {
    test('parses all wire names correctly', () {
      expect(ParseMethod.fromWire('school_matrix'), ParseMethod.schoolMatrix);
      expect(ParseMethod.fromWire('header_mapper'), ParseMethod.headerMapper);
      expect(ParseMethod.fromWire('ocr_grid'), ParseMethod.ocrGrid);
      expect(ParseMethod.fromWire('ai'), ParseMethod.ai);
      expect(ParseMethod.fromWire('unknown'), ParseMethod.schoolMatrix);
      expect(ParseMethod.fromWire(null), ParseMethod.schoolMatrix);
    });

    test('exposes correct wireName', () {
      expect(ParseMethod.schoolMatrix.wireName, 'school_matrix');
      expect(ParseMethod.headerMapper.wireName, 'header_mapper');
      expect(ParseMethod.ocrGrid.wireName, 'ocr_grid');
      expect(ParseMethod.ai.wireName, 'ai');
    });
  });

  group('ImportDiffSummary and ImportDiff (single changed field)', () {
    test('parses server response fixture accurately into changed count', () {
      // Exact payload shape returned by Cloud Function previewTimetableImport
      final serverFixture = <String, dynamic>{
        'draftId': 'tokyo.ac.jp_uuid-123',
        'expiresAt': '2026-06-01T00:30:00.000Z',
        'mode': 'merge',
        'grade': 1,
        'course': '農業',
        'parseMethod': 'header_mapper',
        'usedAi': false,
        'maskedPreviewText': null,
        'invalidRows': [
          {'row': 5, 'reason': 'Invalid period: 99'},
        ],
        'summary': {
          'added': 2,
          'updated': 3,
          'removed': 1,
          'unchanged': 10,
        },
        'changedDaysCount': 4,
        'diffPreview': [
          {
            'date': '2026-06-01',
            'period': '1',
            'kind': 'added',
            'before': null,
            'after': {
              'subject': '数学',
              'teacher': '田中',
              'room': '101',
              'status': 'normal',
            },
          },
          {
            'date': '2026-06-02',
            'period': '2',
            'kind': 'updated',
            'before': {
              'subject': '英語',
              'teacher': '佐藤',
              'room': '102',
              'status': 'normal',
            },
            'after': {
              'subject': '英語II',
              'teacher': '佐藤',
              'room': '202',
              'status': 'normal',
            },
          },
        ],
        'excludedDates': [
          {
            'date': '2028-03-20',
            'reason': 'national_holiday',
            'label': '春分の日',
            'provisional': true,
          },
          {
            'date': '2026-08-10',
            'reason': 'closed_range',
            'label': '夏季休業',
            'provisional': false,
          },
          {
            'date': '2026-06-07',
            'reason': 'non_school_day',
            'label': '日',
            'provisional': false,
          },
        ],
        'notifyStudentsDefault': true,
      };

      final preview = TimetableImportPreview.fromMap(serverFixture);
      expect(preview.draftId, 'tokyo.ac.jp_uuid-123');
      expect(preview.expiresAt?.isUtc, true);
      expect(preview.mode, 'merge');
      expect(preview.grade, 1);
      expect(preview.course, '農業');
      expect(preview.parseMethod, ParseMethod.headerMapper);
      expect(preview.usedAi, false);
      expect(preview.notifyStudentsDefault, true);
      expect(preview.changedDaysCount, 4);

      // Single changed field check
      expect(preview.diff.added, 2);
      expect(preview.diff.changed, 3);
      expect(preview.diff.removed, 1);
      expect(preview.diff.unchanged, 10);
      expect(preview.diff.total, 16);
      expect(preview.diff.totalMutations, 6);

      // diffPreview items
      expect(preview.diff.preview.length, 2);
      expect(preview.diff.preview[0].kind, DiffKind.added);
      expect(preview.diff.preview[0].after?.subject, '数学');
      expect(preview.diff.preview[1].kind, DiffKind.changed);
      expect(preview.diff.preview[1].before?.subject, '英語');
      expect(preview.diff.preview[1].after?.room, '202');

      // invalidRows
      expect(preview.invalidRows.length, 1);
      expect(preview.invalidRows.first.rowNumber, 5);
      expect(preview.invalidRows.first.reason, 'Invalid period: 99');

      // excludedDates
      expect(preview.excludedDates.length, 3);
      expect(preview.excludedDates[0].reason, ExcludedDateReason.holiday);
      expect(preview.excludedDates[0].provisional, true);
      expect(preview.excludedDates[1].reason, ExcludedDateReason.closedDateRange);
      expect(preview.excludedDates[2].reason, ExcludedDateReason.nonSchoolDay);
    });

    test('parses changed key directly when server returns changed', () {
      final summary = ImportDiffSummary.fromMap({
        'added': 1,
        'changed': 4,
        'removed': 2,
        'unchanged': 8,
      });
      expect(summary.changed, 4);
      expect(summary.totalMutations, 7);
      expect(summary.total, 15);
    });
  });

  group('ImportResult and RevertResult', () {
    test('parses confirmTimetableImport and revertTimetableImport server responses', () {
      final importRes = ImportResult.fromMap({
        'ok': true,
        'appliedDays': 15,
        'importId': 'tokyo.ac.jp_imp-999',
        'pushed': 32,
      });
      expect(importRes.ok, true);
      expect(importRes.importId, 'tokyo.ac.jp_imp-999');
      expect(importRes.appliedDays, 15);
      expect(importRes.pushedCount, 32);

      final revertRes = RevertResult.fromMap({
        'ok': true,
        'revertedDays': 15,
      });
      expect(revertRes.success, true);
      expect(revertRes.restoredDaysCount, 15);
    });
  });

  group('SchoolPolicy defaults parity', () {
    test('SchoolPolicy.defaults matches shared/school_policy_defaults.json exactly', () {
      final raw = File('shared/school_policy_defaults.json').readAsStringSync();
      final sharedDefaults = jsonDecode(raw) as Map<String, dynamic>;
      expect(SchoolPolicy.defaults.toMap(), sharedDefaults);
    });

    test('parses timetableImport policy from school map', () {
      final info = SchoolInfo.fromMap('high.school.jp', {
        'name': 'High School',
        'policy': {
          'schemaVersion': 1,
          'revision': 3,
          'timetableImport': {
            'allowedImporters': 'all_teachers',
            'replaceMode': 'admins_only',
            'notifyStudentsDefault': true,
            'undoWindowDays': 14,
            'schoolDays': ['月', '火', '水', '木', '金', '土'],
            'excludeNationalHolidays': true,
          },
        },
      });

      expect(info.policy.revision, 3);
      expect(info.policy.allowedImporters, 'all_teachers');
      expect(info.policy.replaceMode, 'admins_only');
      expect(info.policy.notifyStudentsDefault, true);
      expect(info.policy.undoWindowDays, 14);
      expect(info.policy.schoolDays, ['月', '火', '水', '木', '金', '土']);
      expect(info.policy.canUserUseReplace(isAdmin: true), true);
      expect(info.policy.canUserUseReplace(isAdmin: false), false);
    });
  });

  group('canUserImport (3 allowedImporters modes x 3 roles)', () {
    const school = SchoolInfo(
      domain: 'tokyo.ac.jp',
      name: 'Tokyo HS',
      periods: [],
      grades: [1, 2],
      courses: ['農業', '観光'],
      admins: ['admin_uid'],
      teachers: [
        'admin@tokyo.ac.jp',
        'homeroom@tokyo.ac.jp',
        'regular@tokyo.ac.jp',
      ],
      teacherProfiles: {
        'homeroom@tokyo.ac.jp': TeacherProfile(
          name: '担任先生',
          homeroomGrade: 1,
          homeroomCourse: '農業',
        ),
        'regular@tokyo.ac.jp': TeacherProfile(name: '一般先生'),
      },
    );

    UserModel makeUser(String uid, String email) => UserModel(
          uid: uid,
          name: 'User',
          email: email,
          createdAt: DateTime(2026, 1, 1),
        );

    final adminUser = makeUser('admin_uid', 'admin@tokyo.ac.jp');
    final homeroomUser = makeUser('homeroom_uid', 'homeroom@tokyo.ac.jp');
    final regularTeacher = makeUser('regular_uid', 'regular@tokyo.ac.jp');
    final studentUser = makeUser('student_uid', 'student@tokyo.ac.jp');

    test('mode = admins_only', () {
      const policy = SchoolPolicy(allowedImporters: 'admins_only');
      expect(canUserImport(adminUser, school, policy), true);
      expect(canUserImport(homeroomUser, school, policy), false);
      expect(canUserImport(regularTeacher, school, policy), false);
      expect(canUserImport(studentUser, school, policy), false);
    });

    test('mode = homeroom_and_admins', () {
      const policy = SchoolPolicy(allowedImporters: 'homeroom_and_admins');
      expect(canUserImport(adminUser, school, policy), true);
      expect(canUserImport(homeroomUser, school, policy), true);
      // Matches homeroom class vs non-homeroom class
      expect(
        canUserImport(homeroomUser, school, policy, targetGrade: 1, targetCourse: '農業'),
        true,
      );
      expect(
        canUserImport(homeroomUser, school, policy, targetGrade: 2, targetCourse: '観光'),
        false,
      );
      expect(canUserImport(regularTeacher, school, policy), false);
      expect(canUserImport(studentUser, school, policy), false);
    });

    test('mode = all_teachers', () {
      const policy = SchoolPolicy(allowedImporters: 'all_teachers');
      expect(canUserImport(adminUser, school, policy), true);
      expect(canUserImport(homeroomUser, school, policy), true);
      expect(canUserImport(regularTeacher, school, policy), true);
      expect(canUserImport(studentUser, school, policy), false);
    });
  });
}
