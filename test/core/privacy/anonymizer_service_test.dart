import 'package:edu_planner_ai/core/privacy/anonymizer_service.dart';
import 'package:edu_planner_ai/core/privacy/masking_session.dart';
import 'package:edu_planner_ai/core/privacy/person_name.dart';
import 'package:edu_planner_ai/core/privacy/text_normalizer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const yamada = PersonName(
    id: 's1',
    fullName: '山田太郎',
    role: PersonRole.student,
    parts: ['山田', '太郎', 'やまだ', 'Yamada'],
  );
  const suzuki = PersonName(
    id: 's2',
    fullName: '鈴木花子',
    role: PersonRole.student,
    parts: ['鈴木', '花子'],
  );
  const ali = PersonName(
    id: 's3',
    fullName: 'Ali',
    role: PersonRole.student,
    parts: ['Ali'],
  );

  group('AnonymizerService & MaskingSession', () {
    test('1. 山田太郎さん -> [STUDENT_1]さん', () {
      final service = AnonymizerService();
      final session = MaskingSession();

      final masked = service.anonymize('山田太郎さん', [yamada], session);

      expect(masked, '[STUDENT_1]さん');
    });

    test('2. 山田さんと太郎くん -> same token for the same person', () {
      final service = AnonymizerService();
      final session = MaskingSession();

      final masked = service.anonymize('山田さんと太郎くん', [yamada], session);

      expect(masked, '[STUDENT_1]さんと[STUDENT_1]くん');
    });

    test('3. 山田太郎 matches full name first and never becomes [STUDENT_1]太郎', () {
      final service = AnonymizerService();
      final session = MaskingSession();

      final masked = service.anonymize('山田太郎', [yamada], session);

      expect(masked, '[STUDENT_1]');
      expect(masked, isNot('[STUDENT_1]太郎'));
    });

    test('4. 田んぼ is unchanged because single-character part 田 is ignored', () {
      final service = AnonymizerService();
      final session = MaskingSession();
      const singleCharPart = PersonName(
        id: 's4',
        fullName: '田一郎',
        role: PersonRole.student,
        parts: ['田'],
      );

      final masked = service.anonymize('田んぼで遊ぶ', [singleCharPart], session);

      expect(masked, '田んぼで遊ぶ');
    });

    test('5. Ali inside Alisher is not replaced (Latin word boundary)', () {
      final service = AnonymizerService();
      final session = MaskingSession();

      final masked = service.anonymize('Alisher came to class', [ali], session);

      expect(masked, 'Alisher came to class');
    });

    test('6. ALI / ali are matched case-insensitively', () {
      final service = AnonymizerService();
      final session = MaskingSession();

      final masked = service.anonymize('ALI and ali submitted', [ali], session);

      expect(masked, '[STUDENT_1] and [STUDENT_1] submitted');
    });

    test('7. Two distinct students receive [STUDENT_1] and [STUDENT_2]', () {
      final service = AnonymizerService();
      final session = MaskingSession();

      final masked = service.anonymize(
        '山田太郎と鈴木花子が発表します',
        [yamada, suzuki],
        session,
      );

      expect(masked, '[STUDENT_1]と[STUDENT_2]が発表します');
    });

    test('8. Round-trip restore recovers the original text completely', () {
      final service = AnonymizerService();
      final session = MaskingSession();
      const original = '山田太郎と鈴木花子は教室にいます。';

      final masked = service.anonymize(original, [yamada, suzuki], session);
      final restored = session.restore(masked);

      expect(masked, isNot(contains('山田太郎')));
      expect(masked, isNot(contains('鈴木花子')));
      expect(restored, original);
    });

    test('9. Preexisting [PERSON_1] in input is neutralized and not replaced during restore', () {
      final service = AnonymizerService();
      final session = MaskingSession();
      const input = '山田太郎と[PERSON_1]のメモ';

      final neutralized = MaskingSession.neutralizeTokens(input);
      // Force [PERSON_1] into the session via an ambiguous surname so restore
      // would collide if neutralization had not run.
      const satoA = PersonName(
        id: 'a',
        fullName: '佐藤一郎',
        role: PersonRole.student,
        parts: ['佐藤'],
      );
      const satoB = PersonName(
        id: 'b',
        fullName: '佐藤二郎',
        role: PersonRole.student,
        parts: ['佐藤'],
      );
      final masked = service.anonymize(
        '$neutralized (佐藤)',
        [yamada, satoA, satoB],
        session,
      );
      final restored = session.restore(masked);

      expect(restored, startsWith('山田太郎と'));
      expect(restored, isNot(contains('佐藤のメモ')));
      expect(restored, contains('［PERSON_1］'));
      expect(session.findUnresolvedTokens(restored), isEmpty);
    });

    test('10. findUnresolvedTokens detects corrupted AI tokens such as PERSON 1', () {
      final session = MaskingSession();
      session.tokenFor('山田太郎', prefix: 'PERSON');

      final unresolved = session.findUnresolvedTokens(
        'AIの回答: PERSON 1 と [PERSON-1] と 【PERSON_1】 と [STUDENT_99]',
      );

      expect(
        unresolved,
        containsAll(['PERSON 1', '[PERSON-1]', '【PERSON_1】', '[STUDENT_99]']),
      );
    });

    test('shared surname (同姓) uses generic PERSON prefix while full name uses role prefix', () {
      final service = AnonymizerService();
      final session = MaskingSession();
      const satoTeacher = PersonName(
        id: 't1',
        fullName: '佐藤先生',
        role: PersonRole.teacher,
        parts: ['佐藤'],
      );
      const satoStudent = PersonName(
        id: 's5',
        fullName: '佐藤健',
        role: PersonRole.student,
        parts: ['佐藤'],
      );

      final masked = service.anonymize(
        '佐藤と佐藤健が話した',
        [satoTeacher, satoStudent],
        session,
      );

      expect(masked, '[PERSON_1]と[STUDENT_1]が話した');
    });

    test('TextNormalizer keeps katakana prolonged sound mark intact while normalizing digit dashes', () {
      final norm = TextNormalizer.normalizeForComparison('コンピューター　０９０－１２３４');
      expect(norm, 'コンピューター 090-1234');
    });

    test('MaskingSession.toString never leaks masked values', () {
      final session = MaskingSession();
      session.tokenFor('山田太郎', prefix: 'STUDENT');

      final text = session.toString();

      expect(text, isNot(contains('山田太郎')));
      expect(text, contains('maskedCount: 1'));
    });
  });
}
