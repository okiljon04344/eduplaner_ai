import 'package:edu_planner_ai/core/services/notification_service.dart';
import 'package:edu_planner_ai/features/timetable/models/class_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ClassModel cls(String room) => ClassModel(
        id: 'c1',
        userId: 'u1',
        subject: 'Math',
        teacher: 'T',
        room: room,
        dayOfWeek: '月',
        period: 3,
        createdAt: DateTime(2026, 10, 1),
      );

  test('room appears when set', () {
    expect(NotificationService.classReminderText('notif_class_rem_today', cls('A101')), contains('(A101)'));
  });

  test('empty room leaves no "()"', () {
    for (final key in ['notif_class_rem_today', 'notif_class_rem_soon']) {
      for (final room in ['', '  ']) {
        expect(NotificationService.classReminderText(key, cls(room)), isNot(contains('()')), reason: key);
      }
    }
  });

  test('soon reminder states the start time', () {
    expect(NotificationService.classReminderText('notif_class_rem_soon', cls('A101')), contains('13:00'));
  });
}
