import 'package:edu_planner_ai/core/theme/app_colors.dart';
import 'package:edu_planner_ai/features/school/models/school.dart';
import 'package:edu_planner_ai/features/school/school_providers.dart';
import 'package:edu_planner_ai/core/providers/clock_provider.dart';
import 'package:edu_planner_ai/features/timetable/models/class_model.dart';
import 'package:edu_planner_ai/features/timetable/screens/timetable_screen.dart';
import 'package:edu_planner_ai/features/timetable/providers/timetable_provider.dart';
import 'package:edu_planner_ai/features/timetable/widgets/day_tab_row.dart';
import 'package:edu_planner_ai/features/timetable/widgets/schedule_timeline.dart';
import 'package:edu_planner_ai/features/timetable/widgets/school_changes_list.dart';
import 'package:edu_planner_ai/features/timetable/widgets/school_slot_card.dart';
import 'package:edu_planner_ai/features/timetable/widgets/school_week_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _p12 =
    SchoolPeriod(key: '1-2', label: '1・2限', start: (9, 0), end: (12, 10));
const _p3 = SchoolPeriod(key: '3', label: '3限', start: (13, 0), end: (14, 30));
const _p4 = SchoolPeriod(key: '4', label: '4限', start: (14, 40), end: (16, 10));

SchoolSlot _slot(String period, String subject,
        {SchoolSlotStatus status = SchoolSlotStatus.normal,
        String teacher = '田中',
        String room = 'A101',
        String note = ''}) =>
    SchoolSlot(
        period: period,
        subject: subject,
        teacher: teacher,
        room: room,
        note: note,
        status: status);

final _info = SchoolInfo(
  domain: 'school.test',
  name: 'Test',
  periods: const [_p12, _p3, _p4],
  grades: const [1],
  courses: const ['農業'],
  lastSyncAt: DateTime(2026, 10, 27, 8, 5),
);

ClassModel _personal(String subject, String day, int period) => ClassModel(
      id: '$subject$day$period',
      userId: 'u',
      subject: subject,
      teacher: '',
      room: '',
      dayOfWeek: day,
      period: period,
      createdAt: DateTime(2026, 1, 1),
    );

Widget _app(Widget child, {List<Override> overrides = const []}) =>
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(home: Scaffold(body: child)),
    );

List<Override> _schoolOverrides({
  Map<String, SchoolDay> week = const {},
  List<SchoolChange> changes = const [],
  List<ClassModel> classes = const [],
}) =>
    [
      schoolInfoProvider.overrideWith((_) => Stream.value(_info)),
      schoolRoleProvider.overrideWithValue((teacher: false, admin: false)),
      schoolClassProvider.overrideWithValue((grade: 1, course: '農業')),
      schoolWeekProvider.overrideWith((ref, _) => Stream.value(week)),
      schoolChangesProvider.overrideWith((_) => Stream.value(changes)),
      timetableStreamProvider.overrideWith((_) => Stream.value(classes)),
    ];

void main() {
  setUp(() {
    AppColors.applyBrightness(Brightness.dark);
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('cancelled slot shows strike-through and 休講', (tester) async {
    await tester.pumpWidget(_app(SchoolSlotCard(
        slot: _slot('3', '数学', status: SchoolSlotStatus.cancelled),
        period: _p3)));
    final subject = tester.widget<Text>(find.text('数学'));
    expect(subject.style?.decoration, TextDecoration.lineThrough);
    expect(find.text('休講'), findsOneWidget);
  });

  testWidgets('elective slot shows 選択科目 X', (tester) async {
    await tester.pumpWidget(_app(SchoolSlotCard(
        slot: _slot('3', 'X', status: SchoolSlotStatus.elective),
        period: _p3)));
    expect(find.text('選択科目 X'), findsOneWidget);
  });

  testWidgets('event and tbd slots show their badges', (tester) async {
    await tester.pumpWidget(_app(Column(children: [
      SchoolSlotCard(
          slot: _slot('3', '遠足', status: SchoolSlotStatus.event), period: _p3),
      SchoolSlotCard(
          slot: _slot('4', '理科', status: SchoolSlotStatus.tbd), period: _p4),
    ])));
    expect(find.text('行事'), findsOneWidget);
    expect(find.text('未定'), findsOneWidget);
  });

  testWidgets('shows period times from SchoolPeriod', (tester) async {
    await tester.pumpWidget(_app(
        SchoolSlotCard(slot: _slot('1-2', '国語', note: '持ち物あり'), period: _p12)));
    expect(find.text('1・2限'), findsOneWidget);
    expect(find.text('09:00–12:10'), findsOneWidget);
    expect(find.text('田中 · A101'), findsOneWidget);
    expect(find.text('持ち物あり'), findsOneWidget);
  });

  testWidgets('week grid places school slot in its period row', (tester) async {
    tester.view.physicalSize = const Size(1024, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final week = {
      '2026-10-28': SchoolDay(date: '2026-10-28', slots: [_slot('3', '数学')]),
    };
    await tester.pumpWidget(_app(
      SchoolWeekGrid(weekStart: DateTime(2026, 10, 26)),
      overrides: _schoolOverrides(week: week, classes: [
        _personal('英語', '水', 3), // 13:00 starts inside 3限 -> shares the cell
        _personal('体育', '木', 6), // 18:00 fits no row -> 自分 list
      ]),
    ));
    await tester.pumpAndSettle();

    // 2nd row (3限), 3rd column (水).
    final cell = find.byKey(const ValueKey('school-cell-1-2'));
    expect(
        find.descendant(of: cell, matching: find.text('数学')), findsOneWidget);
    expect(
        find.descendant(of: cell, matching: find.text('英語')), findsOneWidget);
    expect(
        find.descendant(of: cell, matching: find.text('自分')), findsOneWidget);
    // Same slot must not appear in other cells.
    expect(find.text('数学'), findsOneWidget);
    // Unplaced personal class goes to the 自分 list under the grid.
    expect(find.textContaining('体育'), findsOneWidget);
  });

  testWidgets('changes list shows 変更はありません when empty', (tester) async {
    await tester.pumpWidget(
        _app(const SchoolChangesList(), overrides: _schoolOverrides()));
    await tester.pumpAndSettle();
    expect(find.text('最近の変更'), findsOneWidget);
    expect(find.text('変更はありません'), findsOneWidget);
  });

  testWidgets('changes list is sorted by at, newest first', (tester) async {
    final changes = [
      SchoolChange(
          date: '2026-10-28',
          period: '3',
          subject: '古い',
          what: '休講',
          at: DateTime(2026, 10, 20)),
      SchoolChange(
          date: '2026-10-29',
          period: '4',
          subject: '新しい',
          what: '休講',
          at: DateTime(2026, 10, 27)),
    ];
    await tester.pumpWidget(_app(const SchoolChangesList(),
        overrides: _schoolOverrides(changes: changes)));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.textContaining('新しい')).dy,
        lessThan(tester.getTopLeft(find.textContaining('古い')).dy));
  });

  testWidgets(
      'timeline lists school slots first, then labelled personal classes, then the sync footer',
      (tester) async {
    final week = {
      '2026-10-26': SchoolDay(
          date: '2026-10-26', slots: [_slot('4', '理科'), _slot('1-2', '国語')]),
    };
    await tester.pumpWidget(_app(
      ScheduleTimeline(selectedDay: 0, weekStart: DateTime(2026, 10, 26)),
      overrides:
          _schoolOverrides(week: week, classes: [_personal('塾', '月', 1)]),
    ));
    await tester.pumpAndSettle();

    double y(String t) => tester.getTopLeft(find.text(t)).dy;
    expect(y('国語'),
        lessThan(y('理科'))); // ordered by SchoolInfo.periods, not slot order
    expect(y('理科'), lessThan(y('塾')));
    expect(find.text('自分'), findsOneWidget);
    expect(find.text('学校の時間割 · 10/27 08:05 更新'), findsOneWidget);
  });

  testWidgets(
      'a linked school day with no lessons shows a free slot per period, not the empty state',
      (tester) async {
    await tester.pumpWidget(_app(
      ScheduleTimeline(selectedDay: 0, weekStart: DateTime(2026, 10, 26)),
      overrides: _schoolOverrides(),
    ));
    await tester.pumpAndSettle();
    // Redesign: each school period becomes a 空きコマ row that opens 授業を追加.
    expect(find.byIcon(Icons.add_rounded), findsWidgets);
    expect(find.byIcon(Icons.wb_sunny_outlined), findsNothing);
  });

  testWidgets('home banner shows the newest change until opened',
      (tester) async {
    final changes = [
      SchoolChange(
          date: '2026-10-29',
          period: '4',
          subject: '理科',
          what: '休講',
          at: DateTime(2026, 10, 27)),
    ];
    await tester.pumpWidget(_app(const SchoolChangesBanner(),
        overrides: _schoolOverrides(changes: changes)));
    await tester.pumpAndSettle();
    expect(find.textContaining('理科'), findsOneWidget);

    await tester.tap(find.byType(SchoolChangesBanner));
    await tester.pumpAndSettle();
    expect(find.text('最近の変更'), findsWidgets); // bottom sheet with the full list
    expect(
        (await SharedPreferences.getInstance())
            .getInt('school_changes_seen_at'),
        isNotNull);

    // Dismiss the sheet; the banner hides because nothing is newer than seen_at.
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.byType(SchoolChangesBanner), findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(SchoolChangesBanner),
            matching: find.byType(InkWell)),
        findsNothing);
  });

  testWidgets(
      'narrow grid (600) keeps long subjects readable and does not overflow',
      (tester) async {
    tester.view.physicalSize = const Size(600, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final week = {
      '2026-10-28': SchoolDay(date: '2026-10-28', slots: [
        _slot('3', '数学総合演習', status: SchoolSlotStatus.cancelled),
        _slot('4', 'X', status: SchoolSlotStatus.elective),
      ]),
    };
    await tester.pumpWidget(_app(
      SchoolWeekGrid(weekStart: DateTime(2026, 10, 26)),
      overrides: _schoolOverrides(week: week),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('数学総合演習'), findsOneWidget);
    expect(find.text('休講'), findsOneWidget);
    // Badge sits below the subject, not beside it.
    expect(tester.getTopLeft(find.text('休講')).dy,
        greaterThan(tester.getTopLeft(find.text('数学総合演習')).dy));
    // The subject gets the full cell width, not what is left beside a badge.
    expect(tester.getSize(find.text('数学総合演習')).width, greaterThan(60));
  });

  testWidgets('slot with an unknown period key is still shown under the grid',
      (tester) async {
    tester.view.physicalSize = const Size(900, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final week = {
      '2026-10-28': SchoolDay(
          date: '2026-10-28',
          slots: [_slot('7', '特別講座', status: SchoolSlotStatus.cancelled)]),
    };
    await tester.pumpWidget(_app(
      SchoolWeekGrid(weekStart: DateTime(2026, 10, 26)),
      overrides: _schoolOverrides(week: week),
    ));
    await tester.pumpAndSettle();
    expect(find.text('特別講座'), findsOneWidget);
    expect(find.text('休講'), findsOneWidget);
    expect(find.text('水 · 7'), findsOneWidget);
  });

  group('timetable screen layout by width', () {
    Future<void> pumpAt(WidgetTester tester, double width) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_app(
        const TimetableScreen(),
        overrides: [
          ..._schoolOverrides(),
          todayProvider
              .overrideWith((_) => Stream.value(DateTime(2026, 10, 27))),
        ],
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('phone keeps the day tabs', (tester) async {
      await pumpAt(tester, 400);
      expect(find.byType(DayTabRow), findsOneWidget);
      expect(find.byType(SchoolWeekGrid), findsNothing);
    });

    testWidgets('tablet shows the week grid without the side column',
        (tester) async {
      await pumpAt(tester, 900);
      expect(find.byType(SchoolWeekGrid), findsOneWidget);
      expect(find.byType(DayTabRow), findsNothing);
      expect(find.byType(SchoolChangesList), findsNothing);
    });

    testWidgets('desktop adds the 320-wide changes column', (tester) async {
      await pumpAt(tester, 1300);
      expect(find.byType(SchoolWeekGrid), findsOneWidget);
      expect(find.byType(SchoolChangesList), findsOneWidget);
      expect(
          tester
              .getSize(find
                  .ancestor(
                      of: find.byType(SchoolChangesList),
                      matching: find.byType(Container))
                  .first)
              .width,
          320);
    });

    testWidgets(
        'next week does not flip the grid back to day tabs while loading',
        (tester) async {
      tester.view.physicalSize = const Size(900, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_app(
        const TimetableScreen(),
        overrides: [
          ..._schoolOverrides(),
          // Only the current week ever has a value; other weeks stay loading.
          schoolWeekProvider.overrideWith((ref, week) =>
              week == DateTime(2026, 10, 26)
                  ? Stream.value(const <String, SchoolDay>{})
                  : const Stream.empty()),
          todayProvider
              .overrideWith((_) => Stream.value(DateTime(2026, 10, 27))),
        ],
      ));
      await tester.pumpAndSettle();
      expect(find.byType(SchoolWeekGrid), findsOneWidget);

      await tester.tap(find.byIcon(Icons.chevron_right_rounded));
      await tester.pump();
      expect(find.byType(SchoolWeekGrid), findsOneWidget);
      expect(find.byType(DayTabRow), findsNothing);
    });

    testWidgets(
        'without school data a wide screen keeps the day tabs and timeline',
        (tester) async {
      tester.view.physicalSize = const Size(1300, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_app(
        const TimetableScreen(),
        overrides: [
          schoolInfoProvider.overrideWith((_) => Stream.value(null)),
          schoolRoleProvider.overrideWithValue((teacher: false, admin: false)),
          schoolClassProvider.overrideWithValue(null),
          schoolChangesProvider.overrideWith((_) => Stream.value(const [])),
          timetableStreamProvider
              .overrideWith((_) => Stream.value(const <ClassModel>[])),
          todayProvider
              .overrideWith((_) => Stream.value(DateTime(2026, 10, 27))),
        ],
      ));
      await tester.pumpAndSettle();
      expect(find.byType(SchoolWeekGrid), findsNothing);
      expect(find.byType(SchoolChangesList), findsNothing);
      expect(find.byType(DayTabRow), findsOneWidget);
      expect(find.byType(ScheduleTimeline), findsOneWidget);
    });
  });
}
