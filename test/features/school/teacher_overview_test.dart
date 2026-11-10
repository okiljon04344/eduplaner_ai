import 'package:edu_planner_ai/features/school/models/school.dart';
import 'package:edu_planner_ai/features/school/models/school_notice.dart';
import 'package:edu_planner_ai/features/school/teacher_overview_providers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isSlotMine', () {
    const slot1 = SchoolSlot(
      period: '1',
      subject: '英語',
      teacher: '鈴木 一郎',
      room: '101',
      note: '',
      status: SchoolSlotStatus.normal,
    );
    const slot2 = SchoolSlot(
      period: '2',
      subject: '数学',
      teacher: '山田 太郎',
      room: '102',
      note: '',
      status: SchoolSlotStatus.normal,
    );
    const slotCoTeaching = SchoolSlot(
      period: '3',
      subject: '英会話',
      teacher: 'スミス・鈴木',
      room: 'LL',
      note: '',
      status: SchoolSlotStatus.normal,
    );

    test('returns true when slot.teacher contains teacher name', () {
      expect(isSlotMine(slot1, '鈴木'), isTrue);
      expect(isSlotMine(slot1, '鈴木 一郎'), isTrue);
      expect(isSlotMine(slotCoTeaching, '鈴木'), isTrue);
    });

    test('returns false when slot.teacher does not contain teacher name', () {
      expect(isSlotMine(slot2, '鈴木'), isFalse);
    });

    test('returns false when teacher name is empty', () {
      expect(isSlotMine(slot1, ''), isFalse);
    });

    test('returns false when slot.teacher is empty', () {
      const emptySlot = SchoolSlot(
        period: '1',
        subject: '自習',
        teacher: '',
        room: '101',
        note: '',
        status: SchoolSlotStatus.normal,
      );
      expect(isSlotMine(emptySlot, '鈴木'), isFalse);
    });
  });

  group('nextSchoolDay', () {
    test('Friday rolls over to next Monday (+3 days)', () {
      final friday = DateTime(2026, 11, 13); // Friday
      expect(friday.weekday, DateTime.friday);
      final next = nextSchoolDay(friday);
      expect(next, DateTime(2026, 11, 16));
      expect(next.weekday, DateTime.monday);
    });

    test('Saturday rolls over to next Monday (+2 days)', () {
      final saturday = DateTime(2026, 11, 14); // Saturday
      expect(saturday.weekday, DateTime.saturday);
      final next = nextSchoolDay(saturday);
      expect(next, DateTime(2026, 11, 16));
      expect(next.weekday, DateTime.monday);
    });

    test('Sunday rolls to Monday (+1 day)', () {
      final sunday = DateTime(2026, 11, 15); // Sunday
      expect(sunday.weekday, DateTime.sunday);
      final next = nextSchoolDay(sunday);
      expect(next, DateTime(2026, 11, 16));
      expect(next.weekday, DateTime.monday);
    });

    test('Monday rolls to Tuesday (+1 day)', () {
      final monday = DateTime(2026, 11, 9); // Monday
      expect(monday.weekday, DateTime.monday);
      final next = nextSchoolDay(monday);
      expect(next, DateTime(2026, 11, 10));
      expect(next.weekday, DateTime.tuesday);
    });

    test('Thursday rolls to Friday (+1 day)', () {
      final thursday = DateTime(2026, 11, 12); // Thursday
      expect(thursday.weekday, DateTime.thursday);
      final next = nextSchoolDay(thursday);
      expect(next, DateTime(2026, 11, 13));
      expect(next.weekday, DateTime.friday);
    });
  });

  group('isCurrentLesson and isLessonDone', () {
    const period = SchoolPeriod(
      key: 'p1',
      label: '1・2限',
      start: (10, 50),
      end: (12, 20),
    );
    const slot = SchoolSlot(
      period: 'p1',
      subject: '英語',
      teacher: '鈴木',
      room: '101',
      note: '',
      status: SchoolSlotStatus.normal,
    );

    final lessonToday = TeacherLesson(
      date: DateTime(2026, 11, 10),
      period: period,
      grade: 2,
      course: '観光',
      slot: slot,
    );

    test('isCurrentLesson returns true when within start and end on the same day', () {
      // 10:50 is start -> true
      expect(isCurrentLesson(lessonToday, DateTime(2026, 11, 10, 10, 50)), isTrue);
      // 11:30 is middle -> true
      expect(isCurrentLesson(lessonToday, DateTime(2026, 11, 10, 11, 30)), isTrue);
      // 12:19 is just before end -> true
      expect(isCurrentLesson(lessonToday, DateTime(2026, 11, 10, 12, 19)), isTrue);
    });

    test('isCurrentLesson returns false before start or at/after end', () {
      // 10:49 is before start -> false
      expect(isCurrentLesson(lessonToday, DateTime(2026, 11, 10, 10, 49)), isFalse);
      // 12:20 is end boundary -> false
      expect(isCurrentLesson(lessonToday, DateTime(2026, 11, 10, 12, 20)), isFalse);
      // 13:00 is after end -> false
      expect(isCurrentLesson(lessonToday, DateTime(2026, 11, 10, 13, 0)), isFalse);
    });

    test('isCurrentLesson returns false when time matches but date does not', () {
      expect(isCurrentLesson(lessonToday, DateTime(2026, 11, 11, 11, 0)), isFalse);
    });

    test('isLessonDone returns true when now is at or past period end', () {
      expect(isLessonDone(lessonToday, DateTime(2026, 11, 10, 12, 20)), isTrue);
      expect(isLessonDone(lessonToday, DateTime(2026, 11, 10, 15, 0)), isTrue);
    });

    test('isLessonDone returns false when now is before period end', () {
      expect(isLessonDone(lessonToday, DateTime(2026, 11, 10, 12, 19)), isFalse);
      expect(isLessonDone(lessonToday, DateTime(2026, 11, 10, 9, 0)), isFalse);
    });

    test('isLessonDone handles past and future days', () {
      // Past day -> always done
      expect(isLessonDone(lessonToday, DateTime(2026, 11, 11, 8, 0)), isTrue);
      // Future day -> not done
      expect(isLessonDone(lessonToday, DateTime(2026, 11, 9, 15, 0)), isFalse);
    });
  });

  group('summarizeWeekChanges', () {
    final monday = DateTime(2026, 11, 9); // Monday of week Nov 9 - Nov 13

    final changes = [
      ClassChangeItem(
        grade: 1,
        course: '観光',
        change: SchoolChange(
          date: '2026-11-10', // In week (Tue)
          period: '5・6限',
          subject: '英語',
          what: '休講',
          at: DateTime(2026, 11, 8, 10, 0),
        ),
      ),
      ClassChangeItem(
        grade: 2,
        course: '観光',
        change: SchoolChange(
          date: '2026-11-11', // In week (Wed)
          period: '1・2限',
          subject: '情報',
          what: '教室変更：101 → 第2PC室',
          at: DateTime(2026, 11, 8, 14, 0),
        ),
      ),
      ClassChangeItem(
        grade: 2,
        course: '農業',
        change: SchoolChange(
          date: '2026-11-12', // In week (Thu)
          period: '3・4限',
          subject: '簿記',
          what: '補講',
          at: DateTime(2026, 11, 8, 16, 0),
        ),
      ),
      ClassChangeItem(
        grade: 1,
        course: '農業',
        change: SchoolChange(
          date: '2026-11-13', // In week (Fri)
          period: '7・8限',
          subject: '体育',
          what: '休講',
          at: DateTime(2026, 11, 8, 12, 0),
        ),
      ),
      ClassChangeItem(
        grade: 1,
        course: '観光',
        change: SchoolChange(
          date: '2026-11-16', // Next week (Mon) -> should be excluded
          period: '1・2限',
          subject: '英語',
          what: '休講',
          at: DateTime(2026, 11, 9, 8, 0),
        ),
      ),
      ClassChangeItem(
        grade: 2,
        course: '観光',
        change: SchoolChange(
          date: '2026-11-06', // Previous week (Fri) -> should be excluded
          period: '1・2限',
          subject: '英語',
          what: '休講',
          at: DateTime(2026, 11, 5, 8, 0),
        ),
      ),
    ];

    test('counts items within current Mon-Fri week and breaks down by kind', () {
      final summary = summarizeWeekChanges(allChanges: changes, monday: monday);

      // 4 items in week (Nov 10, 11, 12, 13)
      expect(summary.total, 4);
      expect(summary.cancelledCount, 2); // Nov 10 & Nov 13
      expect(summary.roomChangeCount, 1); // Nov 11
      expect(summary.makeupCount, 1); // Nov 12
    });

    test('returns up to 2 most recent items sorted by change.at', () {
      final summary = summarizeWeekChanges(allChanges: changes, monday: monday);
      expect(summary.recentItems.length, 2);
      // Most recent at is Nov 8 16:00 (grade 2 農業 補講)
      expect(summary.recentItems[0].change.what, '補講');
      // Second most recent at is Nov 8 14:00 (grade 2 観光 教室変更)
      expect(summary.recentItems[1].change.what, contains('教室変更'));
    });

    test('returns empty summary when no changes exist', () {
      final summary = summarizeWeekChanges(allChanges: const [], monday: monday);
      expect(summary.total, 0);
      expect(summary.cancelledCount, 0);
      expect(summary.roomChangeCount, 0);
      expect(summary.makeupCount, 0);
      expect(summary.recentItems, isEmpty);
    });
  });

  group('calculateNoticeClassSize', () {
    final classSizes = {
      '1_観光': 27,
      '1_農業': 25,
      '2_観光': 28,
      '2_農業': 26,
    };
    final allCourses = ['観光', '農業'];

    test('returns class size when course is specified', () {
      const notice = SchoolNotice(
        id: 'n1',
        grade: 2,
        course: '観光',
        title: 'テスト',
        body: 'テスト本文',
        createdBy: 'u1',
        authorName: '先生',
      );
      final size = calculateNoticeClassSize(
        notice: notice,
        classSizes: classSizes,
        allCourses: allCourses,
      );
      expect(size, 28);
    });

    test('returns sum of all courses in grade when course is null (whole grade)', () {
      const noticeWholeGrade = SchoolNotice(
        id: 'n2',
        grade: 2,
        course: null,
        title: '学年集会',
        body: 'テスト本文',
        createdBy: 'u1',
        authorName: '先生',
      );
      final size = calculateNoticeClassSize(
        notice: noticeWholeGrade,
        classSizes: classSizes,
        allCourses: allCourses,
      );
      // 28 (2_観光) + 26 (2_農業) = 54
      expect(size, 54);
    });

    test('returns null when classSizes map is empty', () {
      const notice = SchoolNotice(
        id: 'n1',
        grade: 2,
        course: '観光',
        title: 'テスト',
        body: 'テスト本文',
        createdBy: 'u1',
        authorName: '先生',
      );
      final size = calculateNoticeClassSize(
        notice: notice,
        classSizes: const {},
        allCourses: allCourses,
      );
      expect(size, isNull);
    });

    test('returns null when grade courses are not in classSizes', () {
      const noticeGrade3 = SchoolNotice(
        id: 'n3',
        grade: 3,
        course: '観光',
        title: 'テスト',
        body: 'テスト本文',
        createdBy: 'u1',
        authorName: '先生',
      );
      final size = calculateNoticeClassSize(
        notice: noticeGrade3,
        classSizes: classSizes,
        allCourses: allCourses,
      );
      expect(size, isNull);
    });
  });

  group('calculateNoticesReadSummary', () {
    const notice1 = SchoolNotice(
      id: 'n1',
      grade: 2,
      course: '観光',
      title: '校外学習の持ち物',
      body: '',
      createdBy: 'u1',
      authorName: '鈴木先生',
    );
    const notice2 = SchoolNotice(
      id: 'n2',
      grade: 2,
      course: null,
      title: '期末試験の範囲を掲示しました',
      body: '',
      createdBy: 'u1',
      authorName: '鈴木先生',
    );
    const notice3 = SchoolNotice(
      id: 'n3',
      grade: 1,
      course: '観光',
      title: '【緊急】明日は全校集会です',
      body: '',
      urgent: true,
      createdBy: 'u1',
      authorName: '鈴木先生',
    );

    test('calculates totalReads, totalSize, overallPercent and mostUnreadNotice matching mockup', () {
      // Mockup numbers:
      // Notice 1: 22 / 28人 (unread: 6)
      // Notice 2: 40 / 54人 (unread: 14)
      // Notice 3: 12 / 13人 (unread: 1)
      // Sum reads: 22 + 40 + 12 = 74
      // Sum sizes: 28 + 54 + 13 = 95
      // 74 / 95 = 77.89% -> round = 78%
      const items = [
        NoticeReadItem(notice: notice1, reads: 22, size: 28),
        NoticeReadItem(notice: notice2, reads: 40, size: 54),
        NoticeReadItem(notice: notice3, reads: 12, size: 13),
      ];

      final summary = calculateNoticesReadSummary(items);
      expect(summary.totalReads, 74);
      expect(summary.totalSize, 95);
      expect(summary.overallPercent, 78);
      // Most unread: Notice 2 has 54 - 40 = 14 unread
      expect(summary.mostUnreadNotice?.notice.id, 'n2');
      expect(summary.mostUnreadNotice?.unread, 14);
    });

    test('correctly identifies single most unread notice', () {
      const items = [
        NoticeReadItem(notice: notice1, reads: 22, size: 28), // 6 unread
        NoticeReadItem(notice: notice3, reads: 12, size: 13), // 1 unread
      ];

      final summary = calculateNoticesReadSummary(items);
      expect(summary.mostUnreadNotice?.notice.id, 'n1');
      expect(summary.mostUnreadNotice?.unread, 6);
    });

    test('handles missing sizes gracefully', () {
      const items = [
        NoticeReadItem(notice: notice1, reads: 15, size: null),
        NoticeReadItem(notice: notice2, reads: 20, size: null),
      ];

      final summary = calculateNoticesReadSummary(items);
      expect(summary.totalReads, 35);
      expect(summary.totalSize, isNull);
      expect(summary.overallPercent, isNull);
      expect(summary.mostUnreadNotice, isNull);
    });

    test('returns empty summary for empty items list', () {
      final summary = calculateNoticesReadSummary(const []);
      expect(summary.items, isEmpty);
      expect(summary.totalReads, 0);
      expect(summary.totalSize, isNull);
      expect(summary.overallPercent, isNull);
      expect(summary.mostUnreadNotice, isNull);
    });

    test('returns null mostUnreadNotice when all notices are fully read', () {
      const items = [
        NoticeReadItem(notice: notice1, reads: 28, size: 28),
        NoticeReadItem(notice: notice3, reads: 13, size: 13),
      ];

      final summary = calculateNoticesReadSummary(items);
      expect(summary.mostUnreadNotice, isNull);
      expect(summary.overallPercent, 100);
    });
  });
}
