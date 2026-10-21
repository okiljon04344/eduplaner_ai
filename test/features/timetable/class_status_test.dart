import 'package:edu_planner_ai/features/timetable/models/class_model.dart';
import 'package:flutter_test/flutter_test.dart';

ClassModel _class({
  String dayOfWeek = '金',
  int period = 1,
  ClassStatus status = ClassStatus.normal,
  DateTime? statusDate,
}) =>
    ClassModel(
      id: 'c1',
      userId: 'u1',
      subject: '数学',
      teacher: 'T',
      room: 'R',
      dayOfWeek: dayOfWeek,
      period: period,
      createdAt: DateTime(2026, 1, 1),
      status: status,
      statusDate: statusDate,
    );

void main() {
  // 2026-10-12 is a Monday, so: Mon 12, Tue 13, Wed 14, Thu 15, Fri 16,
  // Sat 17, Sun 18, Mon 19.
  test('fixture dates are the weekdays the tests assume', () {
    expect(DateTime(2026, 10, 12).weekday, DateTime.monday);
    expect(DateTime(2026, 10, 16).weekday, DateTime.friday);
  });

  group('weekdayFromKanji', () {
    test('maps 月火水木金 to Monday..Friday and rejects anything else', () {
      expect([for (final k in kWeekdayKanji) weekdayFromKanji(k)],
          [1, 2, 3, 4, 5]);
      expect(weekdayFromKanji('土'), isNull);
      expect(weekdayFromKanji('Mon'), isNull);
    });
  });

  group('nextClassDate', () {
    test('report on Wednesday for a 金 class -> that Friday', () {
      final d = nextClassDate(
          dayOfWeek: '金', period: 1, now: DateTime(2026, 10, 14, 15, 0));
      expect(d, DateTime(2026, 10, 16));
    });

    test('report on Monday after the class ended -> next Monday', () {
      // Period 1 ends 10:30.
      final d = nextClassDate(
          dayOfWeek: '月', period: 1, now: DateTime(2026, 10, 12, 11, 0));
      expect(d, DateTime(2026, 10, 19));
    });

    test('report on Monday exactly when the class ends -> next Monday', () {
      final d = nextClassDate(
          dayOfWeek: '月', period: 1, now: DateTime(2026, 10, 12, 10, 30));
      expect(d, DateTime(2026, 10, 19));
    });

    test('report on Monday before the class ends (even mid-class) -> today',
        () {
      expect(
          nextClassDate(
              dayOfWeek: '月', period: 1, now: DateTime(2026, 10, 12, 8, 0)),
          DateTime(2026, 10, 12));
      expect(
          nextClassDate(
              dayOfWeek: '月', period: 1, now: DateTime(2026, 10, 12, 10, 29)),
          DateTime(2026, 10, 12));
    });

    test('a weekend report rolls to the coming Monday', () {
      expect(
          nextClassDate(
              dayOfWeek: '月', period: 3, now: DateTime(2026, 10, 17, 9, 0)),
          DateTime(2026, 10, 19));
      expect(
          nextClassDate(
              dayOfWeek: '月', period: 3, now: DateTime(2026, 10, 18, 22, 0)),
          DateTime(2026, 10, 19));
    });

    test('crosses a month boundary', () {
      // Fri 2026-10-30 evening, Monday class -> Mon 2026-11-02.
      final d = nextClassDate(
          dayOfWeek: '月', period: 1, now: DateTime(2026, 10, 30, 20, 0));
      expect(d, DateTime(2026, 11, 2));
    });

    test('result is local midnight and has the class weekday', () {
      for (var i = 0; i < kWeekdayKanji.length; i++) {
        final d = nextClassDate(
            dayOfWeek: kWeekdayKanji[i],
            period: 6,
            now: DateTime(2026, 10, 14, 12, 34))!;
        expect(d.weekday, i + 1);
        expect([d.hour, d.minute, d.second], [0, 0, 0]);
      }
    });

    test('unknown weekday -> null', () {
      expect(
          nextClassDate(dayOfWeek: '土', period: 1, now: DateTime(2026, 10, 14)),
          isNull);
    });
  });

  group('statusAppliesTo', () {
    final friday = DateTime(2026, 10, 16);

    test('only the affected calendar day matches, at any time of that day', () {
      final c = _class(status: ClassStatus.cancelled, statusDate: friday);
      expect(c.statusAppliesTo(DateTime(2026, 10, 16)), isTrue);
      expect(c.statusAppliesTo(DateTime(2026, 10, 16, 23, 59)), isTrue);
      // The report day (Wednesday) and the day after must not show it.
      expect(c.statusAppliesTo(DateTime(2026, 10, 14)), isFalse);
      expect(c.statusAppliesTo(DateTime(2026, 10, 17)), isFalse);
      // Same weekday, different week.
      expect(c.statusAppliesTo(DateTime(2026, 10, 23)), isFalse);
    });

    test('never applies for a normal status or a missing date', () {
      expect(_class(statusDate: friday).statusAppliesTo(friday), isFalse);
      expect(
          _class(status: ClassStatus.changed).statusAppliesTo(friday), isFalse);
    });

    test('hasStatusAlertToday is statusAppliesTo(now)', () {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      expect(
          _class(status: ClassStatus.changed, statusDate: today)
              .hasStatusAlertToday,
          isTrue);
      expect(
          _class(
                  status: ClassStatus.changed,
                  statusDate: today.add(const Duration(days: 3)))
              .hasStatusAlertToday,
          isFalse);
    });
  });

  group('hasStatusAlertUpcoming', () {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    test('true for today and future dates, false for past dates', () {
      expect(
          _class(status: ClassStatus.cancelled, statusDate: today)
              .hasStatusAlertUpcoming,
          isTrue);
      expect(
          _class(
                  status: ClassStatus.cancelled,
                  statusDate: DateTime(today.year, today.month, today.day + 4))
              .hasStatusAlertUpcoming,
          isTrue);
      expect(
          _class(
                  status: ClassStatus.cancelled,
                  statusDate: DateTime(today.year, today.month, today.day - 1))
              .hasStatusAlertUpcoming,
          isFalse);
    });

    test('false for a normal status or a missing date', () {
      expect(_class(statusDate: today).hasStatusAlertUpcoming, isFalse);
      expect(_class(status: ClassStatus.cancelled).hasStatusAlertUpcoming,
          isFalse);
    });
  });
}
