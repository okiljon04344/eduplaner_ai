import 'package:edu_planner_ai/core/l10n/app_strings.dart';
import 'package:edu_planner_ai/core/providers/app_providers.dart';
import 'package:edu_planner_ai/features/auth/models/user_model.dart';
import 'package:edu_planner_ai/features/auth/providers/auth_provider.dart';
import 'package:edu_planner_ai/features/groups/providers/groups_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fakes.dart';

ProviderContainer _createContainer({
  UserModel? user,
  required FakeGroupsRepository repo,
}) {
  final container = ProviderContainer(
    overrides: [
      groupsRepositoryProvider.overrideWithValue(repo),
      currentUserProvider.overrideWithValue(user),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  setUpAll(() async {
    await AppStrings.load('ja');
  });

  group('myGroupProvider', () {
    test('emits empty/null when currentUserProvider is null', () async {
      final repo = FakeGroupsRepository(currentGroup: buildStudyGroup(id: 'g1'));
      final container = _createContainer(user: null, repo: repo);

      // Stream.empty() emits no data, so valueOrNull stays null.
      final val = container.read(myGroupProvider).valueOrNull;
      expect(val, isNull);
    });

    test('streams group from repository when user is logged in', () async {
      final group = buildStudyGroup(id: 'g1', name: '情報処理');
      final repo = FakeGroupsRepository(currentGroup: group);
      final user = buildUser(uid: 'u1');
      final container = _createContainer(user: user, repo: repo);

      final val = await container.read(myGroupProvider.future);
      expect(val, isNotNull);
      expect(val!.id, 'g1');
      expect(val.name, '情報処理');
    });
  });

  group('GroupsNotifier - createGroup', () {
    test('returns err_login_required when user is not logged in', () async {
      final repo = FakeGroupsRepository();
      final container = _createContainer(user: null, repo: repo);

      final error = await container.read(groupsNotifierProvider.notifier).createGroup('新グループ');

      expect(error, AppStrings.t('err_login_required'));
      expect(repo.createGroupCalls, isEmpty);
    });

    test('returns err_group_create_failed when repository throws', () async {
      final repo = FakeGroupsRepository(createGroupError: Exception('Firestore network timeout'));
      final user = buildUser(uid: 'u1');
      final container = _createContainer(user: user, repo: repo);

      final error = await container.read(groupsNotifierProvider.notifier).createGroup('失敗グループ');

      expect(error, AppStrings.t('err_group_create_failed'));
      expect(repo.createGroupCalls, hasLength(1));
      expect(container.read(groupsNotifierProvider).hasError, isTrue);
    });

    test('returns null and creates group on success', () async {
      final repo = FakeGroupsRepository();
      final user = buildUser(uid: 'u1');
      final container = _createContainer(user: user, repo: repo);

      final error = await container.read(groupsNotifierProvider.notifier).createGroup('成功グループ');

      expect(error, isNull);
      expect(repo.createGroupCalls, hasLength(1));
      expect(repo.createGroupCalls.single.name, '成功グループ');
      expect(repo.createGroupCalls.single.ownerId, 'u1');
      expect(container.read(groupsNotifierProvider).hasError, isFalse);
    });
  });

  group('GroupsNotifier - joinGroup', () {
    test('returns repository error string when code is invalid or not found', () async {
      final repo = FakeGroupsRepository(
        joinGroupByCodeError: AppStrings.t('err_group_not_found'),
      );
      final container = _createContainer(user: buildUser(uid: 'u1'), repo: repo);

      final error = await container.read(groupsNotifierProvider.notifier).joinGroup('BADCOD');

      expect(error, AppStrings.t('err_group_not_found'));
      expect(repo.joinCalls, ['BADCOD']);
    });

    test('returns null on successful join', () async {
      final repo = FakeGroupsRepository(joinGroupByCodeError: null);
      final container = _createContainer(user: buildUser(uid: 'u1'), repo: repo);

      final error = await container.read(groupsNotifierProvider.notifier).joinGroup('VALID1');

      expect(error, isNull);
      expect(repo.joinCalls, ['VALID1']);
    });

    test('returns join_failed when the call throws (never a false success)', () async {
      final repo = FakeGroupsRepository(joinGroupByCodeThrows: Exception('network'));
      final container = _createContainer(user: buildUser(uid: 'u1'), repo: repo);

      final error = await container.read(groupsNotifierProvider.notifier).joinGroup('VALID1');

      expect(error, AppStrings.t('err_group_join_failed'));
    });
  });

  group('GroupsNotifier - leaveGroup', () {
    test('returns err_login_required when user is not logged in', () async {
      final repo = FakeGroupsRepository();
      final container = _createContainer(user: null, repo: repo);
      final group = buildStudyGroup();

      final error = await container.read(groupsNotifierProvider.notifier).leaveGroup(group);

      expect(error, AppStrings.t('err_login_required'));
      expect(repo.leaveCalls, isEmpty);
    });

    test('returns err_generic_retry when repository throws', () async {
      final repo = FakeGroupsRepository(leaveGroupError: Exception('Firestore permission denied'));
      final user = buildUser(uid: 'u1');
      final container = _createContainer(user: user, repo: repo);
      final group = buildStudyGroup(ownerId: 'u1', memberIds: ['u1', 'u2']);

      final error = await container.read(groupsNotifierProvider.notifier).leaveGroup(group);

      expect(error, AppStrings.t('err_generic_retry'));
      expect(repo.leaveCalls, hasLength(1));
      expect(container.read(groupsNotifierProvider).hasError, isTrue);
    });

    test('returns null and leaves group on success', () async {
      final repo = FakeGroupsRepository();
      final user = buildUser(uid: 'u1');
      final container = _createContainer(user: user, repo: repo);
      final group = buildStudyGroup(ownerId: 'u1', memberIds: ['u1', 'u2']);

      final error = await container.read(groupsNotifierProvider.notifier).leaveGroup(group);

      expect(error, isNull);
      expect(repo.leaveCalls, hasLength(1));
      expect(repo.leaveCalls.single.group.id, group.id);
      expect(repo.leaveCalls.single.uid, 'u1');
      expect(container.read(groupsNotifierProvider).hasError, isFalse);
    });
  });
}
