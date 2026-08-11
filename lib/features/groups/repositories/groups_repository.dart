import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:uuid/uuid.dart';
import '../../../core/l10n/app_strings.dart';
import '../models/study_group_model.dart';

class GroupsRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;
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
      final callable = _functions.httpsCallable('joinGroupByCode');
      await callable.call<Map<String, dynamic>>({'code': code.trim().toUpperCase()});
      return null;
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'not-found') return AppStrings.t('err_group_not_found');
      return AppStrings.t('err_group_join_failed');
    }
  }

  Future<void> leaveGroup(String groupId, String uid) async {
    await _col.doc(groupId).update({
      'memberIds': FieldValue.arrayRemove([uid]),
    });
  }
}
