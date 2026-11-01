import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:edu_planner_ai/features/assignments/repositories/assignments_repository.dart';

import '../../support/fakes.dart';

void main() {
  test('add() persists an assignment that watch(userId) emits back', () async {
    final repo = AssignmentsRepository(db: FakeFirebaseFirestore());
    final model = buildAssignment(id: 'a1', userId: 'u1', title: 'Essay');

    await repo.add(model);
    // Another user's assignment must not leak into the stream.
    await repo.add(buildAssignment(id: 'a2', userId: 'u2', title: 'Other'));

    final list = await repo.watch('u1').first;
    expect(list.map((a) => a.id), ['a1']);
    expect(list.single.title, 'Essay');
  });
}
