import 'package:edu_planner_ai/core/services/notification_service.dart';
import 'package:edu_planner_ai/features/school/models/school.dart';
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

  test('schoolReminderText uses school period start', () {
    const slot = SchoolSlot(
      period: '5-6',
      subject: 'プログラミング',
      teacher: '田中',
      room: '実習室1',
      note: '',
      status: SchoolSlotStatus.normal,
    );
    const period = SchoolPeriod(
      key: '5-6',
      label: '5・6限',
      start: (13, 10),
      end: (16, 20),
    );
    final text = NotificationService.schoolReminderText(slot, period);
    expect(text, contains('13:10'));
    expect(text, contains('5・6'));
    expect(text, contains('プログラミング'));
    expect(text, contains('(実習室1)'));
  });

  test('schoolReminderText strips empty room', () {
    const period = SchoolPeriod(
      key: '5-6',
      label: '5・6限',
      start: (13, 10),
      end: (16, 20),
    );
    for (final room in ['', '  ']) {
      final slot = SchoolSlot(
        period: '5-6',
        subject: 'プログラミング',
        teacher: '田中',
        room: room,
        note: '',
        status: SchoolSlotStatus.normal,
      );
      expect(NotificationService.schoolReminderText(slot, period), isNot(contains('()')));
    }
  });
}

