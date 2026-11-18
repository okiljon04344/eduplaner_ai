import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:edu_planner_ai/features/auth/models/user_model.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fakes.dart';

void main() {
  group('UserModel AI file consent fields', () {
    test('hasCurrentAiFileConsent is false by default and true when current version is set', () {
      final withoutConsent = buildUser();
      expect(withoutConsent.hasCurrentAiFileConsent, isFalse);

      final oldVersion = withoutConsent.copyWith(
        aiFileConsentAt: DateTime(2026, 1, 1),
        aiFileConsentVersion: kAiFileConsentVersion - 1,
      );
      expect(oldVersion.hasCurrentAiFileConsent, isFalse);

      final current = withoutConsent.copyWith(
        aiFileConsentAt: DateTime(2026, 11, 17, 12, 0),
        aiFileConsentVersion: kAiFileConsentVersion,
      );
      expect(current.hasCurrentAiFileConsent, isTrue);
    });

    test('fromFirestore and toFirestore round-trip aiFileConsentAt and aiFileConsentVersion', () {
      final consentTime = DateTime(2026, 11, 17, 15, 30);
      final doc = FakeDocumentSnapshot('u1', {
        'name': '山田太郎',
        'email': 'taro@example.com',
        'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
        'aiFileConsentAt': Timestamp.fromDate(consentTime),
        'aiFileConsentVersion': kAiFileConsentVersion,
      });

      final model = UserModel.fromFirestore(doc);
      expect(model.aiFileConsentAt, consentTime);
      expect(model.aiFileConsentVersion, kAiFileConsentVersion);
      expect(model.hasCurrentAiFileConsent, isTrue);

      final serialized = model.toFirestore();
      expect(serialized['aiFileConsentAt'], Timestamp.fromDate(consentTime));
      expect(serialized['aiFileConsentVersion'], kAiFileConsentVersion);
    });

    test('toFirestore with consent fields stays within firestore.rules 20-key limit and does not touch locked class fields', () {
      final fullUser = buildUser().copyWith(
        photoUrl: 'https://example.com/p.png',
        classId: 'c1',
        school: 'テスト専門学校',
        schoolType: 'vocational',
        grade: '1',
        program: '2年制',
        faculty: '情報',
        department: 'IT',
        course: 'AI',
        schoolDomain: 'example.ac.jp',
        aiFileConsentAt: DateTime(2026, 11, 17),
        aiFileConsentVersion: kAiFileConsentVersion,
      );

      final payload = fullUser.toFirestore();
      // firestore.rules userFieldsOk() enforces `request.resource.data.keys().size() <= 20`.
      expect(payload.keys.length, lessThanOrEqualTo(20));

      // Verify firestore.rules itself preserves the <= 20 cap and allows merge
      // writes of aiFileConsentAt/aiFileConsentVersion without modifying rules.
      final rules = File('firestore.rules').readAsStringSync();
      expect(rules, contains('request.resource.data.keys().size() <= 20'));
      expect(
        rules,
        contains("request.resource.data.get('grade', null) == resource.data.get('grade', null)"),
      );
      expect(
        rules,
        contains("request.resource.data.get('course', null) == resource.data.get('course', null)"),
      );
    });
  });
}
