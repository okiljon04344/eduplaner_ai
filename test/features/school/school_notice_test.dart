import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:edu_planner_ai/features/school/models/school_notice.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SchoolNotice.fromMap', () {
    test('parses all fields from map with timestamp', () {
      final now = DateTime(2026, 11, 10, 14, 30);
      final map = {
        'grade': 2,
        'course': '農業',
        'title': '実習日程の変更',
        'body': '雨天のため第2実習室にて行います。',
        'priority': 'urgent',
        'createdByName': '佐藤先生',
        'createdBy': 'teacher_uid_123',
        'createdAt': Timestamp.fromDate(now),
      };

      final notice = SchoolNotice.fromMap('notice_abc', map);

      expect(notice.id, 'notice_abc');
      expect(notice.grade, 2);
      expect(notice.course, '農業');
      expect(notice.title, '実習日程の変更');
      expect(notice.body, '雨天のため第2実習室にて行います。');
      expect(notice.urgent, isTrue);
      expect(notice.authorName, '佐藤先生');
      expect(notice.createdBy, 'teacher_uid_123');
      expect(notice.createdAt, now);
    });

    test('sets urgent flag from priority', () {
      final urgentNotice = SchoolNotice.fromMap('n1', {
        'grade': 1,
        'title': '緊急連絡',
        'priority': 'urgent',
      });
      expect(urgentNotice.urgent, isTrue);

      final normalNotice = SchoolNotice.fromMap('n2', {
        'grade': 1,
        'title': '通常連絡',
        'priority': 'normal',
      });
      expect(normalNotice.urgent, isFalse);

      final defaultNotice = SchoolNotice.fromMap('n3', {
        'grade': 1,
        'title': '優先度なし',
      });
      expect(defaultNotice.urgent, isFalse);

      final unknownPriorityNotice = SchoolNotice.fromMap('n4', {
        'grade': 1,
        'title': '未知の優先度',
        'priority': 'low',
      });
      expect(unknownPriorityNotice.urgent, isFalse);
    });

    test('tolerates missing and null fields with safe defaults', () {
      final notice = SchoolNotice.fromMap('empty_doc', const {});

      expect(notice.id, 'empty_doc');
      expect(notice.grade, 0);
      expect(notice.course, isNull);
      expect(notice.title, '');
      expect(notice.body, '');
      expect(notice.urgent, isFalse);
      expect(notice.authorName, '');
      expect(notice.createdBy, '');
      expect(notice.createdAt, isNull);
    });

    test('parses double grade as integer', () {
      final notice = SchoolNotice.fromMap('n_num', {'grade': 3.0, 'title': '3年'});
      expect(notice.grade, 3);
    });
  });

  group('SchoolNotice.appliesTo', () {
    test('when course is null, applies to whole grade across any course', () {
      const wholeGradeNotice = SchoolNotice(
        id: 'n_grade2',
        grade: 2,
        course: null,
        title: '2学年全体集会',
      );

      // Same grade with various courses -> true
      expect(wholeGradeNotice.appliesTo(2, '農業'), isTrue);
      expect(wholeGradeNotice.appliesTo(2, '観光'), isTrue);
      expect(wholeGradeNotice.appliesTo(2, 'プログラミング'), isTrue);

      // Different grade -> false
      expect(wholeGradeNotice.appliesTo(1, '農業'), isFalse);
      expect(wholeGradeNotice.appliesTo(3, '観光'), isFalse);
      expect(wholeGradeNotice.appliesTo(0, '農業'), isFalse);
    });

    test('when course is specified, applies only to matching grade and course', () {
      const classNotice = SchoolNotice(
        id: 'n_class',
        grade: 1,
        course: '観光',
        title: '観光コース連絡',
      );

      // Exact match
      expect(classNotice.appliesTo(1, '観光'), isTrue);

      // Same grade but different course -> false
      expect(classNotice.appliesTo(1, '農業'), isFalse);
      expect(classNotice.appliesTo(1, '情報'), isFalse);

      // Different grade with same course -> false
      expect(classNotice.appliesTo(2, '観光'), isFalse);
      expect(classNotice.appliesTo(3, '観光'), isFalse);

      // Different grade and different course -> false
      expect(classNotice.appliesTo(2, '農業'), isFalse);
    });
  });
}
