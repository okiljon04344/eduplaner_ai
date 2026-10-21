import 'package:edu_planner_ai/core/constants/periods.dart';
import 'package:edu_planner_ai/core/services/notification_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // What the timetable and home cards have always displayed.
  const displayed = {
    1: ('09:00', '10:30'),
    2: ('10:40', '12:10'),
    3: ('13:00', '14:30'),
    4: ('14:40', '16:10'),
    5: ('16:20', '17:50'),
    6: ('18:00', '19:30'),
  };

  test('period table matches the times the UI shows', () {
    expect(kPeriodTimes.keys, displayed.keys);
    displayed.forEach((period, t) {
      final labels = periodTimeLabels(period);
      expect((labels.start, labels.end), t, reason: 'period $period');
    });
  });

  test('local reminders start at the displayed start time of every period', () {
    for (final period in kPeriodTimes.keys) {
      final start = NotificationService.periodStart(period);
      expect(start, isNotNull, reason: 'period $period');
      expect(formatHm(start!), periodTimeLabels(period).start,
          reason: 'period $period');
    }
    expect(NotificationService.periodStart(0), isNull);
    expect(NotificationService.periodStart(7), isNull);
  });

  test('periods are 90 minutes long and do not overlap', () {
    DateTime? previousEnd;
    for (final period in kPeriodTimes.keys) {
      final start = periodStartOn(DateTime(2026, 10, 12), period)!;
      final end = periodEndOn(DateTime(2026, 10, 12), period)!;
      expect(end.difference(start), const Duration(minutes: 90),
          reason: 'period $period');
      if (previousEnd != null) {
        expect(start.isAfter(previousEnd), isTrue, reason: 'period $period');
      }
      previousEnd = end;
    }
  });

  test('unknown periods have placeholder labels and no DateTimes', () {
    expect(periodTimeLabels(9), (start: '--:--', end: '--:--'));
    expect(periodStartOn(DateTime(2026, 10, 12), 9), isNull);
    expect(periodEndOn(DateTime(2026, 10, 12), 9), isNull);
  });

  test('formatHm zero-pads', () {
    expect(formatHm((9, 5)), '09:05');
    expect(formatHm((18, 30)), '18:30');
  });
}
