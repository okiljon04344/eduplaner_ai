import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/providers/app_providers.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/study_group_model.dart';

/// Streams the study group the current user belongs to, or `null` if they
/// are not in any group.
///
/// The timetable feature watches this to switch between personal and shared
/// timetable queries automatically.
final myGroupProvider = StreamProvider<StudyGroupModel?>((ref) {
  final uid = ref.watch(currentUserProvider)?.uid;
  if (uid == null) return const Stream.empty();
  return ref.watch(groupsRepositoryProvider).watchMyGroup(uid);
});

/// Handles study group mutations: create, join, and leave.
class GroupsNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  /// Creates a new group owned by the current user.
  ///
  /// Returns a localised error string on failure, or `null` on success.
  Future<String?> createGroup(String name) async {
    final uid = ref.read(currentUserProvider)?.uid;
    if (uid == null) return AppStrings.t('err_login_required');
    state = const AsyncLoading();
    state = await AsyncValue.guard(
        () => ref.read(groupsRepositoryProvider).createGroup(name, uid));
    return state.hasError ? AppStrings.t('err_group_create_failed') : null;
  }

  /// Joins a group by invite [code] via the `joinGroupByCode` Cloud Function.
  ///
  /// The join is server-side because Firestore rules only allow existing
  /// members to update a group document — a joiner is not one yet.
  /// Returns a localised error string on failure, or `null` on success.
  Future<String?> joinGroup(String code) async {
    state = const AsyncLoading();
    String? error;
    state = await AsyncValue.guard(() async {
      error = await ref.read(groupsRepositoryProvider).joinGroupByCode(code);
    });
    return error;
  }

  /// Removes the current user from [groupId].
  ///
  /// Done client-side: Firestore rules allow a member to remove only their
  /// own uid from `memberIds`.
  Future<void> leaveGroup(String groupId) async {
    final uid = ref.read(currentUserProvider)?.uid;
    if (uid == null) return;
    state = const AsyncLoading();
    state = await AsyncValue.guard(
        () => ref.read(groupsRepositoryProvider).leaveGroup(groupId, uid));
  }
}

/// Global provider for [GroupsNotifier].
final groupsNotifierProvider =
    AsyncNotifierProvider<GroupsNotifier, void>(GroupsNotifier.new);
