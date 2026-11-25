import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/utils/date_helper.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/assignment_model.dart';

/// Mirrors the server-side cap in `functions/index.js`'s
/// `analyzeAssignmentSubmission` (`MAX_FILE_BYTES`). Checked here too so an
/// oversized file is rejected before it's base64-encoded (~4/3 size bloat)
/// and sent over the network, only to be rejected server-side anyway.
///
/// UZ: `functions/index.js` dagi `analyzeAssignmentSubmission` server cheklovini (`MAX_FILE_BYTES`)
/// aks ettiradi. Bu yerda ham tekshiriladi, shunda katta hajmdagi fayl base64 formatiga o'tkazilib
/// (~4/3 hajm kattalashishi) tarmoq orqali yuborilishidan va baribir server tomonidan rad etilishidan
/// oldin qaytariladi.
const _kMaxAssignmentFileBytes = 10 * 1024 * 1024;

/// Streams all assignments for the current user from Firestore.
///
/// Emits an empty stream when the user is not signed in.
///
/// UZ: Firestore dan joriy foydalanuvchi uchun barcha topshiriqlarni oqim (stream) tarzida uzatadi.
///
/// Foydalanuvchi tizimga kirmagan bo'lsa, bo'sh oqim uzatadi.
final assignmentsStreamProvider = StreamProvider<List<AssignmentModel>>((ref) {
  final uid = ref.watch(currentUserProvider)?.uid;
  if (uid == null) return const Stream.empty();
  var synced = false;
  return ref.watch(assignmentsRepositoryProvider).watch(uid).map((assignments) {
    if (!synced) {
      synced = true;
      unawaited(NotificationService.syncAllReminders(assignments: assignments));
    }
    return assignments;
  });
});

/// Currently active status filter on the assignments screen.
///
/// Values are locale-independent ids: `'all'`, `'notStarted'`,
/// `'inProgress'`, `'completed'` — display labels are looked up via
/// `AppStrings.t()` in [FilterChipsRow] so switching language never
/// breaks an active filter.
///
/// UZ: Topshiriqlar ekranidagi joriy faol holat filtri.
///
/// Qiymatlar tilga bog'liq bo'lmagan identifikatorlardir: `'all'`, `'notStarted'`,
/// `'inProgress'`, `'completed'` — ko'rsatiladigan yorliqlar [FilterChipsRow] da
/// `AppStrings.t()` orqali olinadi, shuning uchun tilni o'zgartirish hech qachon faol filtrni buzmaydi.
final selectedFilterProvider = StateProvider<String>((_) => 'all');

/// The assignment list after applying [selectedFilterProvider].
///
/// UZ: [selectedFilterProvider] qo'llanilgandan keyingi topshiriqlar ro'yxati.
final filteredAssignmentsProvider = Provider<List<AssignmentModel>>((ref) {
  final all = ref.watch(assignmentsStreamProvider).valueOrNull ?? [];
  final filter = ref.watch(selectedFilterProvider);
  switch (filter) {
    case 'notStarted':
      return all.where((a) => a.status == AssignmentStatus.notStarted).toList();
    case 'inProgress':
      return all.where((a) => a.status == AssignmentStatus.inProgress).toList();
    case 'completed':
      return all.where((a) => a.status == AssignmentStatus.completed).toList();
    default:
      return all;
  }
});

/// How many assignments are due this week and how many are completed.
///
/// Used by the weekly progress ring on the home and assignments screens.
///
/// UZ: Shu hafta topshirilishi kerak bo'lgan nechta topshiriq borligi va ulardan nechtasi bajarilgani.
///
/// Asosiy va topshiriqlar ekranlaridagi haftalik progress halqasi tomonidan foydalaniladi.
final weeklyProgressProvider = Provider<({int completed, int total})>((ref) {
  final all = ref.watch(assignmentsStreamProvider).valueOrNull ?? [];
  final now = DateTime.now();
  // Calendar arithmetic (not Duration): Monday 00:00 .. next Monday 00:00,
  // correct across DST changes.
  // UZ: Taqvim arifmetikasi (Duration emas): Dushanba 00:00 .. keyingi Dushanba 00:00,
  // DST (yozgi/qishki vaqt) o'zgarishlarida ham to'g'ri ishlaydi.
  final start = DateTime(now.year, now.month, now.day - (now.weekday - 1));
  final end = DateTime(start.year, start.month, start.day + 7);
  final weekAssignments = all.where((a) {
    final due = a.dueDate;
    return !due.isBefore(start) && due.isBefore(end);
  }).toList();
  final completed =
      weekAssignments.where((a) => a.status == AssignmentStatus.completed).length;
  return (completed: completed, total: weekAssignments.length);
});

/// The next 3 incomplete assignments — shown on the home screen quick-view.
///
/// Only items due within the last 7 days or later are considered, so ancient
/// overdue leftovers can't crowd out the real upcoming work.
///
/// UZ: Keyingi 3 ta tugallanmagan topshiriq — asosiy ekrandagi tezkor ko'rishda ko'rsatiladi.
///
/// Faqat so'nggi 7 kun ichida yoki undan keyin muddati keladigan topshiriqlar hisobga olinadi,
/// shuning uchun juda eski qolib ketgan topshiriqlar haqiqiy yaqinlashib kelayotgan ishlarni siqib chiqarmaydi.
final upcomingAssignmentsProvider = Provider<List<AssignmentModel>>((ref) {
  final all = ref.watch(assignmentsStreamProvider).valueOrNull ?? [];
  final now = DateTime.now();
  final upcoming = all
      .where((a) =>
          a.status != AssignmentStatus.completed &&
          DateHelper.daysBetween(a.dueDate, now) >= -7)
      .toList()
    ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
  return upcoming.take(3).toList();
});

/// How many incomplete assignments are overdue or due within the next 3 days.
///
/// Used to show an urgent badge count in the nav bar.
///
/// UZ: Muddati o'tgan yoki keyingi 3 kun ichida bajarilishi kerak bo'lgan tugallanmagan topshiriqlar soni.
///
/// Navigatsiya panelida shoshilinch nishon (badge) sonini ko'rsatish uchun foydalaniladi.
final urgentAssignmentsCountProvider = Provider<int>((ref) {
  final all = ref.watch(assignmentsStreamProvider).valueOrNull ?? [];
  final now = DateTime.now();
  return all
      .where((a) =>
          a.status != AssignmentStatus.completed &&
          DateHelper.daysBetween(a.dueDate, now) <= 3)
      .length;
});

/// Handles all assignment write operations and AI-check integration.
///
/// UZ: Topshiriqlarni yozish bo'yicha barcha amallarni va AI-check integratsiyasini boshqaradi.
class AssignmentsNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  /// Runs a [NotificationService] call, logging (not rethrowing) any
  /// failure — reminder scheduling is best-effort and must never surface
  /// as a user-facing error for what is otherwise a successful write.
  ///
  /// UZ: [NotificationService] chaqiruvini bajaradi va har qanday xatolikni qayta tashlamasdan
  /// (not rethrowing) log qiladi — eslatmalarni rejalashtirish best-effort usulida va aks holda
  /// muvaffaqiyatli yozish amali uchun foydalanuvchiga ko'rinadigan xato sifatida chiqmasligi kerak.
  Future<void> _safeNotify(Future<void> Function() action, String label) async {
    try {
      await action();
    } catch (e) {
      debugPrint('$label error: $e');
    }
  }

  /// Runs [write], returning `null` on success or the localized generic
  /// retry message on failure (after logging) — callers show the message in
  /// an error toast and keep their UI open.
  ///
  /// UZ: [write] funksiyasini bajaradi, muvaffaqiyatli bo'lsa `null` yoki xatolik yuz berganda
  /// (log qilingandan keyin) mahalliylashtirilgan umumiy qayta urinish xabarini qaytaradi —
  /// chaqiruvchilar xabarni xatolik bildirishnomasida (toast) ko'rsatadi va o'z UI-larini ochiq qoldiradi.
  Future<String?> _guarded(Future<void> Function() write, String label) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(write);
    if (state.hasError) {
      debugPrint('$label error: ${state.error}');
      return AppStrings.t('err_generic_retry');
    }
    return null;
  }

  /// Creates a new assignment and schedules due-date reminders.
  ///
  /// Returns `null` on success, otherwise an error message to show.
  ///
  /// UZ: Yangi topshiriq yaratadi va topshirish muddati eslatmalarini rejalashtiradi.
  ///
  /// Muvaffaqiyatli bo'lsa `null`, aks holda ko'rsatish uchun xatolik xabarini qaytaradi.
  Future<String?> add(AssignmentModel model) async {
    final error = await _guarded(() => ref.read(assignmentsRepositoryProvider).add(model), 'Assignment add');
    if (error == null) {
      await _safeNotify(() => NotificationService.scheduleAssignmentReminders(model), 'Assignment reminder schedule');
    }
    return error;
  }

  /// Updates an existing assignment and reschedules its reminders.
  ///
  /// Returns `null` on success, otherwise an error message to show.
  ///
  /// UZ: Mavjud topshiriqni yangilaydi va uning eslatmalarini qayta rejalashtiradi.
  ///
  /// Muvaffaqiyatli bo'lsa `null`, aks holda ko'rsatish uchun xatolik xabarini qaytaradi.
  Future<String?> updateAssignment(AssignmentModel model) async {
    if (model.isDistributed) {
      return AppStrings.t('sas_distributed_no_edit');
    }
    final error = await _guarded(() => ref.read(assignmentsRepositoryProvider).update(model), 'Assignment update');
    if (error == null) {
      await _safeNotify(() => NotificationService.scheduleAssignmentReminders(model), 'Assignment reminder schedule');
    }
    return error;
  }

  /// Deletes an assignment and cancels its pending notifications.
  ///
  /// Returns `null` on success, otherwise an error message to show.
  ///
  /// UZ: Topshiriqni o'chiradi va uning kutilayotgan bildirishnomalarini bekor qiladi.
  ///
  /// Muvaffaqiyatli bo'lsa `null`, aks holda ko'rsatish uchun xatolik xabarini qaytaradi.
  Future<String?> delete(String id) async {
    final all = ref.read(assignmentsStreamProvider).valueOrNull ?? [];
    final match = all.where((a) => a.id == id).firstOrNull;
    if (match != null && match.isDistributed) {
      return AppStrings.t('sas_distributed_no_delete');
    }
    final error = await _guarded(() => ref.read(assignmentsRepositoryProvider).delete(id), 'Assignment delete');
    if (error == null) {
      await _safeNotify(() => NotificationService.cancelAssignmentReminders(id), 'Assignment reminder cancel');
    }
    return error;
  }

  /// Sets [status] on [model] and writes it together with the progress that
  /// goes with it (see [AssignmentModel.withStatus]).
  ///
  /// Returns `null` on success, otherwise an error message to show.
  ///
  /// UZ: [model] da [status] ni o'rnatadi va unga mos keladigan progress bilan birga
  /// yozadi (qarang: [AssignmentModel.withStatus]).
  ///
  /// Muvaffaqiyatli bo'lsa `null`, aks holda ko'rsatish uchun xatolik xabarini qaytaradi.
  Future<String?> updateStatus(AssignmentModel model, AssignmentStatus status) =>
      _writeStatusProgress(model, model.withStatus(status));

  /// Sets the progress (0.0–1.0) of [model] and writes it together with the
  /// status derived from it (see [AssignmentModel.withProgress]).
  ///
  /// Returns `null` on success, otherwise an error message to show.
  ///
  /// UZ: [model] ning progressini (0.0–1.0) o'rnatadi va undan kelib chiqqan holat
  /// bilan birga yozadi (qarang: [AssignmentModel.withProgress]).
  ///
  /// Muvaffaqiyatli bo'lsa `null`, aks holda ko'rsatish uchun xatolik xabarini qaytaradi.
  Future<String?> updateProgress(AssignmentModel model, double progress) =>
      _writeStatusProgress(model, model.withProgress(progress));

  /// Persists [next]'s status + progress in one Firestore update and keeps
  /// reminders in step: cancelled when it becomes completed, rescheduled when
  /// it leaves completed.
  ///
  /// UZ: Bitta Firestore yangilanishida [next] ning holati + progressini saqlaydi va
  /// eslatmalarni moslashtirib boradi: bajarilganda (completed) bekor qilinadi,
  /// bajarilganlikdan chiqqanda qayta rejalashtiriladi.
  Future<String?> _writeStatusProgress(AssignmentModel previous, AssignmentModel next) async {
    try {
      await ref.read(assignmentsRepositoryProvider).updateStatusAndProgress(next.id, next.status, next.progress);
    } catch (e) {
      debugPrint('Assignment status/progress error: $e');
      return AppStrings.t('err_generic_retry');
    }
    if (next.status == AssignmentStatus.completed) {
      await _safeNotify(() => NotificationService.cancelAssignmentReminders(next.id), 'Assignment reminder cancel');
    } else if (previous.status == AssignmentStatus.completed) {
      await _safeNotify(() => NotificationService.scheduleAssignmentReminders(next), 'Assignment reminder schedule');
    }
    return null;
  }

  /// 課題の自動チェック — base64-encodes a file picked by the user and sends it
  /// to the `analyzeAssignmentSubmission` Cloud Function for Gemini analysis.
  ///
  /// The file is never written to Storage or logged — it exists only in the
  /// Cloud Function's memory for that single invocation.  Only the derived
  /// result (`completionPercent`, `missingParts`, `advice`) is written back
  /// to Firestore and returned to the caller.
  ///
  /// Returns `(model: updated, error: null, highRedactionWarning: ...)` on
  /// success or `(model: null, error: message, highRedactionWarning: false)` on
  /// failure.
  Future<({AssignmentModel? model, String? error, bool highRedactionWarning})>
      checkWithAi(
    AssignmentModel assignment, {
    required Uint8List fileBytes,
    required String mimeType,
  }) async {
    if (fileBytes.length > _kMaxAssignmentFileBytes) {
      return (
        model: null,
        error: AppStrings.t('err_invalid_file'),
        highRedactionWarning: false,
      );
    }
    final repo = ref.read(assignmentsRepositoryProvider);
    try {
      final result = await repo.analyzeSubmission(
        subject: assignment.subject,
        title: assignment.title,
        description: assignment.description,
        fileBase64: base64Encode(fileBytes),
        mimeType: mimeType,
      );
      final completionPercent =
          (result['completionPercent'] as num?)?.toDouble() ?? 0.0;
      final missingParts = (result['missingParts'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList();
      final advice = result['advice'] as String? ?? '';
      final highRedactionWarning = result['highRedactionWarning'] == true;
      final analyzedAt = DateTime.now();
      await repo.saveAiAnalysis(
        assignment.id,
        completionPercent: completionPercent,
        missingParts: missingParts,
        advice: advice,
        analyzedAt: analyzedAt,
      );
      final updated = assignment.copyWith(
        aiCompletionPercent: completionPercent,
        aiMissingParts: missingParts,
        aiAdvice: advice,
        aiAnalyzedAt: analyzedAt,
      );
      return (
        model: updated,
        error: null,
        highRedactionWarning: highRedactionWarning,
      );
    } catch (e) {
      debugPrint('checkWithAi error: $e');
      return (
        model: null,
        error: e.toString().replaceFirst('Exception: ', ''),
        highRedactionWarning: false,
      );
    }
  }
}

/// Global provider for [AssignmentsNotifier].
///
/// UZ: [AssignmentsNotifier] uchun global provayder.
final assignmentsNotifierProvider =
    AsyncNotifierProvider<AssignmentsNotifier, void>(AssignmentsNotifier.new);
