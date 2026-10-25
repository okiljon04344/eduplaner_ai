import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/providers/app_providers.dart';
import '../../assignments/providers/assignments_provider.dart';
import '../../auth/providers/auth_provider.dart';
import '../../timetable/providers/timetable_provider.dart';
import '../models/message_model.dart';
import '../repositories/chat_repository.dart';

/// In-memory chat messages. A loading placeholder is appended while the Cloud
/// Function call is in flight and replaced by the reply (or an error message),
/// so there is never a gap after the user's message.
class ChatNotifier extends Notifier<List<MessageModel>> {
  // Watching the uid resets the conversation when another account signs in, so
  // it can't leak across accounts.
  @override
  List<MessageModel> build() {
    ref.watch(currentUserProvider.select((u) => u?.uid));
    return [];
  }

  String get _uid => ref.read(currentUserProvider)?.uid ?? '';
  ChatRepository get _repo => ref.read(chatRepositoryProvider);

  /// Resolves the AI context from [current]. If the stream hasn't emitted yet
  /// (a message sent right after the screen mounts) it waits briefly on
  /// [whenLoaded] instead of silently sending an empty context. Context is
  /// optional, so a timeout or error falls back to an empty list.
  Future<List<T>> _contextOf<T>(AsyncValue<List<T>> current, Future<List<T>> whenLoaded) async {
    final value = current.valueOrNull;
    if (value != null) return value;
    try {
      return await whenLoaded.timeout(const Duration(seconds: 5));
    } catch (_) {
      return [];
    }
  }

  /// Merges the last 50 stored messages into the state when the chat screen
  /// mounts. Local messages missing from the history (an in-flight placeholder,
  /// unsaved or error messages) are kept, so remounting mid-reply doesn't drop
  /// the answer. No-op when signed out.
  Future<void> loadHistory() async {
    final uid = _uid;
    if (uid.isEmpty) return;
    final history = await _repo.loadHistory(uid);
    if (_uid != uid) return; // account switched while loading
    final historyIds = {for (final m in history) m.id};
    final merged = [...history, ...state.where((m) => !historyIds.contains(m.id))]
      ..sort((a, b) {
        final byTime = a.timestamp.compareTo(b.timestamp);
        // Coarse clocks can tie a user message and its placeholder: user first.
        return byTime != 0 ? byTime : a.role.index.compareTo(b.role.index);
      });
    state = merged;
  }

  /// Appends [content] as a user message and sends it to the AI. Both messages
  /// are persisted; on error the placeholder becomes a visible error message.
  Future<void> sendMessage(String content, {required String botId}) async {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return;
    // Captured once: both saves must go to the sending account even if another
    // account signs in while the reply is in flight.
    final uid = _uid;
    final userMsg = MessageModel(
      id: const Uuid().v4(),
      content: trimmed,
      role: MessageRole.user,
      timestamp: DateTime.now(),
      botId: botId,
    );
    final loadingMsg = MessageModel(
      id: const Uuid().v4(),
      content: '',
      role: MessageRole.assistant,
      timestamp: DateTime.now(),
      isLoading: true,
      botId: botId,
    );
    state = [...state, userMsg, loadingMsg];
    // saveMessage swallows its own errors, so this write can run concurrently
    // with the AI round-trip.
    final userMsgSave = uid.isNotEmpty ? _repo.saveMessage(uid, userMsg) : Future<void>.value();
    try {
      final (classes, assignments) = await (
        _contextOf(ref.read(timetableStreamProvider), ref.read(timetableStreamProvider.future)),
        _contextOf(ref.read(assignmentsStreamProvider), ref.read(assignmentsStreamProvider.future)),
      ).wait;
      final response = await _repo.sendMessage(
        botId: botId,
        userMessage: trimmed,
        classes: classes,
        assignments: assignments,
      );
      final assistantMsg = loadingMsg.copyWith(content: response, isLoading: false);
      state = state.map((m) => m.id == loadingMsg.id ? assistantMsg : m).toList();
      await userMsgSave;
      if (uid.isNotEmpty) await _repo.saveMessage(uid, assistantMsg);
    } catch (e) {
      final errMsg = loadingMsg.copyWith(
        content: AppStrings.t('err_prefix', {'message': e.toString().replaceAll('Exception: ', '')}),
        isLoading: false,
        isError: true,
      );
      state = state.map((m) => m.id == loadingMsg.id ? errMsg : m).toList();
      debugPrint('Chat send error: $e');
    }
  }

  /// Clears the state and deletes the stored messages. A failed delete is logged
  /// and swallowed so the user still gets a fresh chat.
  Future<void> clearHistory() async {
    state = [];
    if (_uid.isNotEmpty) {
      try {
        await _repo.clearHistory(_uid);
      } catch (e) {
        debugPrint('Clear history error: $e');
      }
    }
  }
}

final chatProvider = NotifierProvider<ChatNotifier, List<MessageModel>>(ChatNotifier.new);

/// Id of the selected AI bot (default: planner), set by the bot picker and
/// passed to every [ChatNotifier.sendMessage].
final selectedBotIdProvider = StateProvider<String>((_) => 'planner');
