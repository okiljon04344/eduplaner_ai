import 'package:edu_planner_ai/core/l10n/app_strings.dart';
import 'package:edu_planner_ai/core/theme/app_colors.dart';
import 'package:edu_planner_ai/features/school/models/school.dart';
import 'package:edu_planner_ai/features/timetable/widgets/school_slot_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

SchoolSlot _slot({
  String period = '1',
  String subject = '数学',
  String teacher = '田中',
  String room = '101',
  String note = '',
  SchoolSlotStatus status = SchoolSlotStatus.normal,
  SchoolOverrideKind? teacherKind,
}) =>
    SchoolSlot(
      period: period,
      subject: subject,
      teacher: teacher,
      room: room,
      note: note,
      status: status,
      teacherKind: teacherKind,
    );

bool get _stringsLoaded =>
    AppStrings.t('school_slot_cancelled') != 'school_slot_cancelled';
String get _cancelledBadge =>
    _stringsLoaded ? '休講' : 'school_slot_cancelled';
String get _eventBadge => _stringsLoaded ? '行事' : 'school_slot_event';
String get _tbdBadge => _stringsLoaded ? '未定' : 'school_slot_tbd';
String get _roomBadge => _stringsLoaded ? '教室変更' : 'teacher_kind_room';
String get _makeupBadge => _stringsLoaded ? '補講' : 'teacher_kind_makeup';

void main() {
  setUp(() {
    AppColors.applyBrightness(Brightness.dark);
  });

  group('schoolSlotBadge', () {
    test('normal slot has null badge', () {
      final slot = _slot(status: SchoolSlotStatus.normal);
      expect(schoolSlotBadge(slot), isNull);
    });

    test('cancelled slot has cancelled badge', () {
      final slot = _slot(status: SchoolSlotStatus.cancelled);
      expect(schoolSlotBadge(slot), _cancelledBadge);
    });

    test('event slot has event badge', () {
      final slot = _slot(status: SchoolSlotStatus.event);
      expect(schoolSlotBadge(slot), _eventBadge);
    });

    test('tbd slot has tbd badge', () {
      final slot = _slot(status: SchoolSlotStatus.tbd);
      expect(schoolSlotBadge(slot), _tbdBadge);
    });

    test('elective slot has null badge', () {
      final slot = _slot(status: SchoolSlotStatus.elective);
      expect(schoolSlotBadge(slot), isNull);
    });

    test('normal slot changed by teacher with kind room has room badge', () {
      final slot = _slot(
        status: SchoolSlotStatus.normal,
        teacherKind: SchoolOverrideKind.room,
      );
      expect(schoolSlotBadge(slot), _roomBadge);
    });

    test('slot changed by teacher with kind makeup has makeup badge', () {
      final slot = _slot(
        status: SchoolSlotStatus.normal,
        teacherKind: SchoolOverrideKind.makeup,
      );
      expect(schoolSlotBadge(slot), _makeupBadge);
    });
  });

  group('schoolSlotAccent', () {
    test('normal slot has AppColors.primary', () {
      final slot = _slot(status: SchoolSlotStatus.normal);
      expect(schoolSlotAccent(slot), AppColors.primary);
    });

    test('cancelled slot has AppColors.danger', () {
      final slot = _slot(status: SchoolSlotStatus.cancelled);
      expect(schoolSlotAccent(slot), AppColors.danger);
    });

    test('event slot has AppColors.warning', () {
      final slot = _slot(status: SchoolSlotStatus.event);
      expect(schoolSlotAccent(slot), AppColors.warning);
    });

    test('tbd slot has AppColors.textMuted', () {
      final slot = _slot(status: SchoolSlotStatus.tbd);
      expect(schoolSlotAccent(slot), AppColors.textMuted);
    });

    test('elective slot has AppColors.primaryMid', () {
      final slot = _slot(status: SchoolSlotStatus.elective);
      expect(schoolSlotAccent(slot), AppColors.primaryMid);
    });

    test('normal slot changed by teacher with kind room has AppColors.warning', () {
      final slot = _slot(
        status: SchoolSlotStatus.normal,
        teacherKind: SchoolOverrideKind.room,
      );
      expect(schoolSlotAccent(slot), AppColors.warning);
    });

    test('slot changed by teacher with kind makeup has AppColors.warning', () {
      final slot = _slot(
        status: SchoolSlotStatus.normal,
        teacherKind: SchoolOverrideKind.makeup,
      );
      expect(schoolSlotAccent(slot), AppColors.warning);
    });
  });
}
