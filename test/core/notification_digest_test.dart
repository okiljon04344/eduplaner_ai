import 'package:edu_planner_ai/core/l10n/app_strings.dart';
import 'package:edu_planner_ai/core/services/notification_service.dart';
import 'package:edu_planner_ai/features/timetable/models/class_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() async {
    await AppStrings.load('ja');
  });

  ClassModel buildClass({
    required String id,
    required int period,
    required String subject,
    String dayOfWeek = '月',
  }) {
    return ClassModel(
      id: id,
      userId: 'u1',
      subject: subject,
      teacher: 'Teacher',
      room: '101',
      dayOfWeek: dayOfWeek,
      period: period,
      createdAt: DateTime(2026, 10, 1),
    );
  }

  group('morningDigestTitle', () {
    test('formats count with Japanese vocational school phrasing', () {
      expect(NotificationService.morningDigestTitle(0), '今日の授業は0コマ');
      expect(NotificationService.morningDigestTitle(1), '今日の授業は1コマ');
      expect(NotificationService.morningDigestTitle(5), '今日の授業は5コマ');
    });
  });

  group('morningDigestBody', () {
    test('returns empty string when no classes', () {
      expect(NotificationService.morningDigestBody([]), isEmpty);
    });

    test('formats single class with localized period label', () {
      final classes = [
        buildClass(id: 'c1', period: 1, subject: '数学'),
      ];
      expect(NotificationService.morningDigestBody(classes), '1限 数学');
    });

    test('sorts classes by period ascending and joins with middle dot', () {
      final classes = [
        buildClass(id: 'c3', period: 4, subject: '物理'),
        buildClass(id: 'c1', period: 1, subject: '数学'),
        buildClass(id: 'c2', period: 2, subject: '英語'),
      ];
      expect(
        NotificationService.morningDigestBody(classes),
        '1限 数学 · 2限 英語 · 4限 物理',
      );
    });

    test('trims whitespace around subjects', () {
      final classes = [
        buildClass(id: 'c1', period: 1, subject: '  プログラミング  '),
      ];
      expect(NotificationService.morningDigestBody(classes), '1限 プログラミング');
    });

    test('keeps short digests untouched without ellipsis', () {
      final classes = [
        buildClass(id: 'c1', period: 1, subject: '数学'),
        buildClass(id: 'c2', period: 2, subject: '英語'),
      ];
      final body = NotificationService.morningDigestBody(classes);
      expect(body, '1限 数学 · 2限 英語');
      expect(body.length, lessThanOrEqualTo(120));
      expect(body.endsWith('…'), isFalse);
    });

    test('truncates digests exceeding ~120 characters with ellipsis', () {
      final classes = [
        buildClass(id: 'c1', period: 1, subject: '人工知能プログラミング基礎と機械学習モデルの実践演習'),
        buildClass(id: 'c2', period: 2, subject: '情報通信ネットワーク構築とクラウドインフラ設計技術'),
        buildClass(id: 'c3', period: 3, subject: 'データベースシステム工学と分散データ処理アーキテクチャ'),
        buildClass(id: 'c4', period: 4, subject: 'サイバーセキュリティ脅威分析とインシデントレスポンス演習'),
      ];
      final body = NotificationService.morningDigestBody(classes);
      expect(body.length, lessThanOrEqualTo(120));
      expect(body.endsWith('…'), isTrue);
    });

    test('respects custom maxLength parameter', () {
      final classes = [
        buildClass(id: 'c1', period: 1, subject: '数学'),
        buildClass(id: 'c2', period: 2, subject: '英語'),
      ];
      // "1限 数学 · 2限 英語" is 13 chars
      final body = NotificationService.morningDigestBody(classes, maxLength: 8);
      expect(body.length, 8);
      expect(body.endsWith('…'), isTrue);
    });
  });

  group('morningReminderId', () {
    test('returns stable and distinct IDs for each weekday 1..7', () {
      final ids = <int>{};
      for (var w = 1; w <= 7; w++) {
        final id1 = NotificationService.morningReminderId(w);
        final id2 = NotificationService.morningReminderId(w);
        expect(id1, equals(id2), reason: 'must be stable across calls');
        ids.add(id1);
      }
      expect(ids, hasLength(7), reason: 'each weekday must have a unique id');
    });
  });
}
