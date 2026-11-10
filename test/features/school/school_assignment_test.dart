import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:edu_planner_ai/features/school/models/school_assignment.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('summarizeProgress', () {
    test('returns zeros and rate 0.0 for empty list', () {
      final summary = summarizeProgress(const []);
      expect(summary.total, 0);
      expect(summary.completed, 0);
      expect(summary.inProgress, 0);
      expect(summary.notStarted, 0);
      expect(summary.rate, 0.0);
    });

    test('counts statuses and calculates rate correctly', () {
      final items = [
        const AssignmentProgress(id: '1', sourceId: 's', uid: 'u1', status: 'completed', progress: 1.0),
        const AssignmentProgress(id: '2', sourceId: 's', uid: 'u2', status: 'completed', progress: 1.0),
        const AssignmentProgress(id: '3', sourceId: 's', uid: 'u3', status: 'inProgress', progress: 0.5),
        const AssignmentProgress(id: '4', sourceId: 's', uid: 'u4', status: 'notStarted', progress: 0.0),
        const AssignmentProgress(id: '5', sourceId: 's', uid: 'u5', status: 'notStarted', progress: 0.0),
      ];

      final summary = summarizeProgress(items);
      expect(summary.total, 5);
      expect(summary.completed, 2);
      expect(summary.inProgress, 1);
      expect(summary.notStarted, 2);
      expect(summary.rate, closeTo(0.4, 0.0001));
    });

    test('defaults unknown status to notStarted', () {
      final items = [
        const AssignmentProgress(id: '1', sourceId: 's', uid: 'u1', status: 'unknown'),
      ];

      final summary = summarizeProgress(items);
      expect(summary.total, 1);
      expect(summary.completed, 0);
      expect(summary.inProgress, 0);
      expect(summary.notStarted, 1);
      expect(summary.rate, 0.0);
    });

    test('all completed gives rate 1.0', () {
      final items = [
        const AssignmentProgress(id: '1', sourceId: 's', uid: 'u1', status: 'completed'),
        const AssignmentProgress(id: '2', sourceId: 's', uid: 'u2', status: 'completed'),
      ];

      final summary = summarizeProgress(items);
      expect(summary.total, 2);
      expect(summary.completed, 2);
      expect(summary.rate, 1.0);
    });
  });

  group('SchoolAssignment.fromMap', () {
    test('parses all fields from map with timestamp', () {
      final created = DateTime(2026, 11, 10, 10, 0);
      final due = DateTime(2026, 11, 17, 23, 59);

      final map = {
        'domain': 'ihit.ac.jp',
        'grade': 2,
        'course': 'ITエキスパート',
        'subject': 'プログラミング',
        'title': 'Flutter課題1',
        'description': '状態管理の実装',
        'dueAt': Timestamp.fromDate(due),
        'createdBy': 'teacher_1',
        'createdByName': '田中先生',
        'createdAt': Timestamp.fromDate(created),
        'total': 25,
      };

      final assignment = SchoolAssignment.fromMap('assign_123', map);

      expect(assignment.id, 'assign_123');
      expect(assignment.domain, 'ihit.ac.jp');
      expect(assignment.grade, 2);
      expect(assignment.course, 'ITエキスパート');
      expect(assignment.subject, 'プログラミング');
      expect(assignment.title, 'Flutter課題1');
      expect(assignment.description, '状態管理の実装');
      expect(assignment.dueAt, due);
      expect(assignment.createdBy, 'teacher_1');
      expect(assignment.createdByName, '田中先生');
      expect(assignment.createdAt, created);
      expect(assignment.total, 25);
    });

    test('tolerates missing and null fields with safe defaults', () {
      final assignment = SchoolAssignment.fromMap('empty_doc', const {});

      expect(assignment.id, 'empty_doc');
      expect(assignment.domain, '');
      expect(assignment.grade, 0);
      expect(assignment.course, isNull);
      expect(assignment.subject, '');
      expect(assignment.title, '');
      expect(assignment.description, '');
      expect(assignment.dueAt, isNotNull);
      expect(assignment.createdBy, '');
      expect(assignment.createdByName, '');
      expect(assignment.createdAt, isNull);
      expect(assignment.total, 0);
    });
  });

  group('SchoolAssignment.appliesTo', () {
    test('when course is null, applies to whole grade regardless of course', () {
      final wholeGrade = SchoolAssignment(
        id: 'a1',
        grade: 2,
        course: null,
        subject: '情報',
        title: '学年課題',
        dueAt: DateTime.now(),
      );

      expect(wholeGrade.appliesTo(2, 'ITエキスパート'), isTrue);
      expect(wholeGrade.appliesTo(2, '情報ビジネス'), isTrue);
      expect(wholeGrade.appliesTo(1, 'ITエキスパート'), isFalse);
      expect(wholeGrade.appliesTo(3, 'ITエキスパート'), isFalse);
    });

    test('when course is specified, applies only to matching grade and course', () {
      final classSpecific = SchoolAssignment(
        id: 'a2',
        grade: 1,
        course: '観光',
        subject: '観光概論',
        title: 'レポート',
        dueAt: DateTime.now(),
      );

      expect(classSpecific.appliesTo(1, '観光'), isTrue);
      expect(classSpecific.appliesTo(1, '農業'), isFalse);
      expect(classSpecific.appliesTo(2, '観光'), isFalse);
    });
  });
}
