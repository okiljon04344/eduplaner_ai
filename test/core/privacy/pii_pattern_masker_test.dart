import 'dart:convert';
import 'dart:io';

import 'package:edu_planner_ai/core/privacy/anonymizer_service.dart';
import 'package:edu_planner_ai/core/privacy/masking_session.dart';
import 'package:edu_planner_ai/core/privacy/person_name.dart';
import 'package:edu_planner_ai/core/privacy/pii_pattern_masker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PiiPatternMasker', () {
    test('11. Masks Japanese phone numbers (hyphenated, plain, full-width) as [PHONE_1]', () {
      const masker = PiiPatternMasker();

      final s1 = MaskingSession();
      expect(masker.mask('連絡先: 090-1234-5678', s1), '連絡先: [PHONE_1]');
      expect(s1.restore('連絡先: [PHONE_1]'), '連絡先: 090-1234-5678');

      final s2 = MaskingSession();
      expect(masker.mask('TEL 09012345678', s2), 'TEL [PHONE_1]');

      final s3 = MaskingSession();
      expect(masker.mask('電話：０９０－１２３４－５６７８', s3), '電話：[PHONE_1]');
    });

    test('12. Dates (2026-11-17) and times (10:30) are NOT masked as phone numbers', () {
      const masker = PiiPatternMasker();
      final session = MaskingSession();
      const input = '提出日は 2026-11-17 の 10:30 です。';

      final masked = masker.mask(input, session);

      expect(masked, input);
      expect(session.hasMaskedData, isFalse);
    });

    test('13. Masks email addresses as [EMAIL_1]', () {
      const masker = PiiPatternMasker();
      final session = MaskingSession();

      final masked = masker.mask('Email: test@example.com まで', session);

      expect(masked, 'Email: [EMAIL_1] まで');
      expect(session.restore(masked), 'Email: test@example.com まで');
    });

    test('Masks Japanese postal codes and custom student ID patterns without disturbing dates', () {
      final masker = PiiPatternMasker(
        extraPatterns: [RegExp(r'\bS\d{6}\b')],
      );
      final session = MaskingSession();

      final masked = masker.mask(
        '〒086-1100 学籍番号 S202601 締切 2026-11-17',
        session,
      );

      expect(masked, '[POSTAL_1] 学籍番号 [STUDENT_ID_1] 締切 2026-11-17');
      expect(
        session.restore(masked),
        '〒086-1100 学籍番号 S202601 締切 2026-11-17',
      );
    });

    test('Shared fixture test_fixtures/privacy_cases.json matches Dart output', () {
      final raw = File('test_fixtures/privacy_cases.json').readAsStringSync();
      final cases = (jsonDecode(raw) as List<dynamic>).cast<Map<String, dynamic>>();
      final anonymizer = AnonymizerService();

      for (final c in cases) {
        final id = c['id'] as String;
        final input = c['input'] as String;
        final expectedMasked = c['expectedMasked'] as String;
        final expectedRestored = c['expectedRestored'] as String;

        final rawPeople = (c['people'] as List<dynamic>).cast<Map<String, dynamic>>();
        final people = rawPeople
            .map(
              (p) => PersonName(
                id: p['id'] as String,
                fullName: p['fullName'] as String,
                role: (p['role'] as String) == 'teacher'
                    ? PersonRole.teacher
                    : PersonRole.student,
                parts: (p['parts'] as List<dynamic>).cast<String>(),
              ),
            )
            .toList();

        final extraPatterns = (c['extraPatterns'] as List<dynamic>)
            .cast<String>()
            .map(RegExp.new)
            .toList();
        final piiMasker = PiiPatternMasker(extraPatterns: extraPatterns);

        final session = MaskingSession();
        final masked = anonymizer.maskText(
          input,
          people,
          session,
          piiMasker: piiMasker,
        );
        final restored = session.restore(masked);

        expect(masked, expectedMasked, reason: 'masked mismatch in $id');
        expect(restored, expectedRestored, reason: 'restored mismatch in $id');
      }
    });

    test('Email local-part matching known student name is masked as [EMAIL_1], not [STUDENT_1]@gmail.com', () {
      final anonymizer = AnonymizerService();
      final session = MaskingSession();
      const people = [
        PersonName(
          id: 's6',
          fullName: 'Taro Yamada',
          role: PersonRole.student,
          parts: ['Taro', 'Yamada'],
        ),
      ];

      final masked = anonymizer.maskText(
        'Taro Yamada <taro@gmail.com>',
        people,
        session,
      );

      expect(masked, '[STUDENT_1] <[EMAIL_1]>');
      expect(session.restore(masked), 'Taro Yamada <taro@gmail.com>');
    });
  });
}
