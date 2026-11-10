import 'package:edu_planner_ai/core/l10n/app_strings.dart';
import 'package:edu_planner_ai/features/home/widgets/today_lessons.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatLessonTimeRemaining (ja)', () {
    setUpAll(() async {
      await AppStrings.load('ja');
    });

    test('under 60 minutes formats as "あと {n}分"', () {
      expect(formatLessonTimeRemaining(59), equals('あと 59分'));
    });

    test('60 minutes (m == 0) formats as "あと {h}時間"', () {
      expect(formatLessonTimeRemaining(60), equals('あと 1時間'));
    });

    test('61 minutes formats as "あと {h}時間{m}分"', () {
      expect(formatLessonTimeRemaining(61), equals('あと 1時間1分'));
    });

    test('636 minutes (10h 36m) formats as "あと 10時間36分"', () {
      expect(formatLessonTimeRemaining(636), equals('あと 10時間36分'));
    });

    test('live lesson under 60 minutes formats as "残り {n}分"', () {
      expect(formatLessonTimeRemaining(59, live: true), equals('残り 59分'));
    });

    test('live lesson 60 minutes formats as "残り {h}時間"', () {
      expect(formatLessonTimeRemaining(60, live: true), equals('残り 1時間'));
    });

    test('live lesson 61 minutes formats as "残り {h}時間{m}分"', () {
      expect(formatLessonTimeRemaining(61, live: true), equals('残り 1時間1分'));
    });

    test('live lesson 636 minutes formats as "残り {h}時間{m}分"', () {
      expect(formatLessonTimeRemaining(636, live: true), equals('残り 10時間36分'));
    });
  });

  group('formatLessonTimeRemaining (en)', () {
    setUpAll(() async {
      await AppStrings.load('en');
    });

    tearDownAll(() async {
      await AppStrings.load('ja');
    });

    test('formats English upcoming lessons (59, 60, 61, 636 min)', () {
      expect(formatLessonTimeRemaining(59), equals('in 59 min'));
      expect(formatLessonTimeRemaining(60), equals('in 1h'));
      expect(formatLessonTimeRemaining(61), equals('in 1h 1m'));
      expect(formatLessonTimeRemaining(636), equals('in 10h 36m'));
    });

    test('formats English in-progress lessons (59, 60, 61, 636 min)', () {
      expect(formatLessonTimeRemaining(59, live: true), equals('59 min left'));
      expect(formatLessonTimeRemaining(60, live: true), equals('1h left'));
      expect(formatLessonTimeRemaining(61, live: true), equals('1h 1m left'));
      expect(formatLessonTimeRemaining(636, live: true), equals('10h 36m left'));
    });
  });
}
