import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:uuid/uuid.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/services/functions_service.dart';
import '../models/study_group_model.dart';

class GroupsRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  CollectionReference get _col => _db.collection('study_groups');

  static const _codeChars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  String _generateCode() {
    final rand = Random.secure();
    return List.generate(6, (_) => _codeChars[rand.nextInt(_codeChars.length)]).join();
  }

  Stream<StudyGroupModel?> watchMyGroup(String uid) {
    return _col.where('memberIds', arrayContains: uid).limit(1).snapshots().map(
          (s) => s.docs.isEmpty ? null : StudyGroupModel.fromFirestore(s.docs.first),
        );
  }

  Future<StudyGroupModel> createGroup(String name, String ownerId) async {
    final id = const Uuid().v4();
    final model = StudyGroupModel(
      id: id,
      name: name,
      code: _generateCode(),
      ownerId: ownerId,
      memberIds: [ownerId],
      createdAt: DateTime.now(),
    );
    await _col.doc(id).set(model.toFirestore());
    return model;
  }

  /// Runs server-side via [functions/index.js]'s `joinGroupByCode` — the
  /// client can't add itself to `memberIds` directly because Firestore rules
  /// only allow existing members to update a group document.
  Future<String?> joinGroupByCode(String code) async {
    try {
      final callable = FunctionsService.callable('joinGroupByCode');
      await callable.call<Map<String, dynamic>>({'code': code.trim().toUpperCase()});
      return null;
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'not-found') return AppStrings.t('err_group_not_found');
      if (e.code == 'unauthenticated' || e.code == 'deadline-exceeded' || e.code == 'unavailable') {
        return FunctionsService.describeError(e);
      }
      return AppStrings.t('err_group_join_failed');
    }
  }

  /// Removes [uid] from the group.
  ///
  /// The leaver's own classes are detached from the group first (while they
  /// are still a member), so they stay in their personal timetable instead of
  /// pointing at a group they can no longer read. Then:
  ///  * sole member → the group document is deleted (rules forbid emptying
  ///    `memberIds`, but allow a sole member to delete);
  ///  * owner with others remaining → ownership moves to the longest-standing
  ///    remaining member in the same write, so the group is never ownerless;
  ///  * anyone else → just removed from `memberIds`.
  Future<void> leaveGroup(StudyGroupModel group, String uid) async {
    final mine = await _db
        .collection('timetables')
        .where('userId', isEqualTo: uid)
        .where('groupId', isEqualTo: group.id)
        .get();
    if (mine.docs.isNotEmpty) {
      final batch = _db.batch();
      for (final doc in mine.docs) {
        batch.update(doc.reference, {'groupId': null});
      }
      await batch.commit();
    }

    final others = group.memberIds.where((id) => id != uid).toList();
    if (others.isEmpty) {
      await _col.doc(group.id).delete();
      return;
    }
    await _col.doc(group.id).update({
      'memberIds': FieldValue.arrayRemove([uid]),
      if (group.ownerId == uid) 'ownerId': others.first,
    });
  }
}
