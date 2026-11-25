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
///
/// UZ: Joriy foydalanuvchi tegishli bo'lgan o'quv guruhini uzatadi (stream), yoki agar ular
/// hech qanday guruhda bo'lmasa, `null` qaytaradi.
///
/// Dars jadvali (timetable) funksiyasi shaxsiy va umumiy dars jadvali so'rovlari o'rtasida avtomatik
/// almashish uchun buni kuzatib boradi.
final myGroupProvider = StreamProvider<StudyGroupModel?>((ref) {
  final uid = ref.watch(currentUserProvider)?.uid;
  if (uid == null) return const Stream.empty();
  return ref.watch(groupsRepositoryProvider).watchMyGroup(uid);
});

/// Handles study group mutations: create, join, and leave.
///
/// UZ: O'quv guruhi o'zgarishlarini boshqaradi: yaratish, qo'shilish va chiqish.
class GroupsNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  /// Creates a new group owned by the current user.
  ///
  /// Returns a localised error string on failure, or `null` on success.
  ///
  /// UZ: Joriy foydalanuvchiga tegishli yangi guruh yaratadi.
  ///
  /// Xatolik yuz berganda mahalliylashtirilgan xatolik satrini, muvaffaqiyatli bo'lsa `null` qaytaradi.
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
  ///
  /// UZ: `joinGroupByCode` Cloud Function orqali taklif [code] bo'yicha guruhga qo'shiladi.
  ///
  /// Qo'shilish server tomonida amalga oshiriladi, chunki Firestore qoidalari faqat mavjud a'zolarga
  /// guruh hujjatini yangilashga ruxsat beradi — qo'shiluvchi hali a'zo emas.
  /// Xatolik yuz berganda mahalliylashtirilgan xatolik satrini, muvaffaqiyatli bo'lsa `null` qaytaradi.
  Future<String?> joinGroup(String code) async {
    state = const AsyncLoading();
    String? error;
    state = await AsyncValue.guard(() async {
      error = await ref.read(groupsRepositoryProvider).joinGroupByCode(code);
    });
    // A thrown error (network, timeout) leaves `error` null: report it too.
    // UZ: Tashlangan xato (tarmoq, timeout) `error`ni null qoldiradi: uni ham xabar qiling.
    return state.hasError ? AppStrings.t('err_group_join_failed') : error;
  }

  /// Removes the current user from [group]: detaches their own classes, hands
  /// ownership on if they are the owner, and deletes the group if they are the
  /// last member (see [GroupsRepository.leaveGroup]).
  ///
  /// Done client-side: Firestore rules allow a member to remove only their
  /// own uid from `memberIds`.
  /// Returns a localised error string on failure, or `null` on success.
  ///
  /// UZ: Joriy foydalanuvchini [group]dan olib tashlaydi: ularning shaxsiy darslarini ajratadi,
  /// agar ular egasi bo'lsa, egalikni topshiradi va agar ular oxirgi a'zo bo'lsa, guruhni o'chirib tashlaydi
  /// ([GroupsRepository.leaveGroup]ga qarang).
  ///
  /// Mijoz tomonida bajariladi: Firestore qoidalari a'zoga faqat o'z uid'sini `memberIds`dan
  /// olib tashlashga ruxsat beradi.
  /// Xatolik yuz berganda mahalliylashtirilgan xatolik satrini, muvaffaqiyatli bo'lsa `null` qaytaradi.
  Future<String?> leaveGroup(StudyGroupModel group) async {
    final uid = ref.read(currentUserProvider)?.uid;
    if (uid == null) return AppStrings.t('err_login_required');
    state = const AsyncLoading();
    state = await AsyncValue.guard(
        () => ref.read(groupsRepositoryProvider).leaveGroup(group, uid));
    return state.hasError ? AppStrings.t('err_generic_retry') : null;
  }
}

/// Global provider for [GroupsNotifier].
///
/// UZ: [GroupsNotifier] uchun global provider.
final groupsNotifierProvider =
    AsyncNotifierProvider<GroupsNotifier, void>(GroupsNotifier.new);
