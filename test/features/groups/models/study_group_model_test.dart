import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:edu_planner_ai/features/groups/models/study_group_model.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fakes.dart';

void main() {
  group('StudyGroupModel', () {
    test('fromJson and toJson round-trip', () {
      final now = DateTime(2026, 8, 1, 10, 30);
      final model = StudyGroupModel(
        id: 'group-123',
        name: '3年A組数学',
        code: 'XYZ789',
        ownerId: 'user-owner',
        memberIds: const ['user-owner', 'user-member-2'],
        createdAt: now,
      );

      final json = model.toJson();
      final fromJsonModel = StudyGroupModel.fromJson(json);

      expect(fromJsonModel.id, model.id);
      expect(fromJsonModel.name, '3年A組数学');
      expect(fromJsonModel.code, 'XYZ789');
      expect(fromJsonModel.ownerId, 'user-owner');
      expect(fromJsonModel.memberIds, ['user-owner', 'user-member-2']);
      expect(fromJsonModel.createdAt, now);
      expect(fromJsonModel, equals(model));
    });

    test('fromFirestore parses valid DocumentSnapshot', () {
      final createdAt = DateTime(2026, 5, 20, 15, 0);
      final doc = FakeDocumentSnapshot('doc-grp-1', {
        'name': '情報システム科',
        'code': 'CODE42',
        'ownerId': 'owner-1',
        'memberIds': ['owner-1', 'member-2', 'member-3'],
        'createdAt': Timestamp.fromDate(createdAt),
      });

      final model = StudyGroupModel.fromFirestore(doc);

      expect(model.id, 'doc-grp-1');
      expect(model.name, '情報システム科');
      expect(model.code, 'CODE42');
      expect(model.ownerId, 'owner-1');
      expect(model.memberIds, ['owner-1', 'member-2', 'member-3']);
      expect(model.createdAt, createdAt);
    });

    test('fromFirestore handles null and empty map edge cases gracefully', () {
      final before = DateTime.now().subtract(const Duration(seconds: 1));
      final doc = FakeDocumentSnapshot('doc-empty', null);

      final model = StudyGroupModel.fromFirestore(doc);

      expect(model.id, 'doc-empty');
      expect(model.name, isEmpty);
      expect(model.code, isEmpty);
      expect(model.ownerId, isEmpty);
      expect(model.memberIds, isEmpty);
      final after = DateTime.now().add(const Duration(seconds: 1));
      expect(model.createdAt.isAfter(before), isTrue);
      expect(model.createdAt.isBefore(after), isTrue);
    });

    test('fromFirestore maps non-string memberIds to string representations', () {
      final doc = FakeDocumentSnapshot('doc-dynamic-members', {
        'name': 'テスト',
        'code': '123456',
        'ownerId': 'u1',
        'memberIds': [101, 202, 'u3'],
      });

      final model = StudyGroupModel.fromFirestore(doc);

      expect(model.memberIds, ['101', '202', 'u3']);
    });

    test('toFirestore serializes fields and creates Firestore Timestamp', () {
      final createdAt = DateTime(2026, 10, 15, 12, 0);
      final model = StudyGroupModel(
        id: 'grp-ignored-in-map',
        name: '物理特講',
        code: 'PHY101',
        ownerId: 'teacher-1',
        memberIds: const ['teacher-1', 'student-1'],
        createdAt: createdAt,
      );

      final map = model.toFirestore();

      expect(map['id'], isNull, reason: 'Firestore doc ID is not a field in the map');
      expect(map['name'], '物理特講');
      expect(map['code'], 'PHY101');
      expect(map['ownerId'], 'teacher-1');
      expect(map['memberIds'], ['teacher-1', 'student-1']);
      expect(map['createdAt'], isA<Timestamp>());
      expect((map['createdAt'] as Timestamp).toDate(), createdAt);
    });
  });
}
