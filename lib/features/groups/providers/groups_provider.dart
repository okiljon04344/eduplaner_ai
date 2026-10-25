import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/providers/app_providers.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/study_group_model.dart';

/// The user's study group, or null. The timetable watches it to switch between
/// personal and shared queries.
final myGroupProvider = StreamProvider<StudyGroupModel?>((ref) {
  final uid = ref.watch(currentUserProvider)?.uid;
  if (uid == null) return const Stream.empty();
  return ref.watch(groupsRepositoryProvider).watchMyGroup(uid);
});

/// Study group mutations. Each returns a localised error string, or null on success.
class GroupsNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  /// Creates a group owned by the current user.
  Future<String?> createGroup(String name) async {
    final uid = ref.read(currentUserProvider)?.uid;
    if (uid == null) return AppStrings.t('err_login_required');
    state = const AsyncLoading();
    state = await AsyncValue.guard(
        () => ref.read(groupsRepositoryProvider).createGroup(name, uid));
    return state.hasError ? AppStrings.t('err_group_create_failed') : null;
  }

  /// Joins a group by invite [code] through the `joinGroupByCode` function; a
  /// joiner isn't a member yet, so the rules don't let the client update the group.
  Future<String?> joinGroup(String code) async {
    state = const AsyncLoading();
    String? error;
    state = await AsyncValue.guard(() async {
      error = await ref.read(groupsRepositoryProvider).joinGroupByCode(code);
    });
    return error;
  }

  /// Leaves [group] (see [GroupsRepository.leaveGroup]). Done client-side: the
  /// rules let a member remove only their own uid from `memberIds`.
  Future<String?> leaveGroup(StudyGroupModel group) async {
    final uid = ref.read(currentUserProvider)?.uid;
    if (uid == null) return AppStrings.t('err_login_required');
    state = const AsyncLoading();
    state = await AsyncValue.guard(
        () => ref.read(groupsRepositoryProvider).leaveGroup(group, uid));
    return state.hasError ? AppStrings.t('err_generic_retry') : null;
  }
}

final groupsNotifierProvider =
    AsyncNotifierProvider<GroupsNotifier, void>(GroupsNotifier.new);
