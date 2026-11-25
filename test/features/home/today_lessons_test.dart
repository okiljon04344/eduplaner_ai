import 'package:edu_planner_ai/core/providers/clock_provider.dart';
import 'package:edu_planner_ai/core/theme/app_colors.dart';
import 'package:edu_planner_ai/features/home/widgets/today_lessons.dart';
import 'package:edu_planner_ai/features/school/models/school.dart';
import 'package:edu_planner_ai/features/school/school_providers.dart';
import 'package:edu_planner_ai/features/timetable/models/class_model.dart';
import 'package:edu_planner_ai/features/timetable/providers/timetable_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => AppColors.applyBrightness(Brightness.dark));

  // Regression: the remark under a lesson (what an 行事 is, what changed) was
  // shown on the timetable but dropped on Home.
  testWidgets('Home lesson rows show the slot note', (tester) async {
    final day = DateTime(2026, 11, 16, 8); // a Monday, before 1限
    const info = SchoolInfo(
      domain: 'school.test',
      name: 'Test',
      periods: [SchoolPeriod(key: '1', label: '1限', start: (9, 0), end: (10, 30))],
      grades: [1],
      courses: ['農業'],
    );
    const slot = SchoolSlot(
      period: '1',
      subject: '体育祭',
      teacher: '田中',
      room: '',
      note: '体育館に集合',
      status: SchoolSlotStatus.event,
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [
        todayProvider.overrideWith((_) => Stream.value(day)),
        minuteTickProvider.overrideWith((_) => Stream.value(day)),
        schoolInfoProvider.overrideWith((_) => Stream.value(info)),
        schoolWeekProvider.overrideWith(
            (ref, _) => Stream.value({'2026-11-16': const SchoolDay(date: '2026-11-16', slots: [slot])})),
        timetableStreamProvider.overrideWith((_) => Stream.value(const <ClassModel>[])),
      ],
      child: const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: Column(children: [NowLessonCard(), TodayLessonsCard()]))),
      ),
    ));
    await tester.pump();
    await tester.pump();

    expect(find.text('体育祭'), findsNWidgets(2));
    // Once in the "next lesson" card, once in the day's list.
    expect(find.text('体育館に集合'), findsNWidgets(2));
  });
}
