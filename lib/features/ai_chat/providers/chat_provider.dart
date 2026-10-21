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

/// Manages the in-memory list of chat messages for the active bot session.
///
/// Optimistically appends a loading message while the Cloud Function call is
/// in flight, then replaces it with the real AI reply (or an error message)
/// once the result arrives.  This ensures the UI never shows an empty gap
/// between the user's message and the bot's reply.
class ChatNotifier extends Notifier<List<MessageModel>> {
  /// Watches the signed-in uid so the in-memory conversation is reset (and
  /// can never leak) when a different account signs in on this device.
  @override
  List<MessageModel> build() {
    ref.watch(currentUserProvider.select((u) => u?.uid));
    return [];
  }

  String get _uid => ref.read(currentUserProvider)?.uid ?? '';
  ChatRepository get _repo => ref.read(chatRepositoryProvider);

  /// Resolves the AI context from [current], briefly awaiting [whenLoaded]
  /// when the stream hasn't emitted yet (cold open: a message sent right
  /// after the chat screen mounts would otherwise silently give the AI an
  /// empty timetable/assignment context). Context is optional, so timeout
  /// and error (e.g. signed-out empty stream) fall back to an empty list
  /// instead of failing the send.
  Future<List<T>> _contextOf<T>(AsyncValue<List<T>> current, Future<List<T>> whenLoaded) async {
    final value = current.valueOrNull;
    if (value != null) return value;
    try {
      return await whenLoaded.timeout(const Duration(seconds: 5));
    } catch (_) {
      return [];
    }
  }

  /// Loads the last 50 messages from Firestore and merges them into the
  /// current state.
  ///
  /// Called whenever the chat screen mounts.  Local messages that aren't in
  /// the loaded history (an in-flight loading placeholder, unsaved or error
  /// messages) are kept, so remounting mid-reply doesn't drop the answer.
  /// No-op when not signed in.
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

  /// Appends [content] as a user message, then sends it to the AI.
  ///
  /// A placeholder loading message is inserted immediately so the typing
  /// indicator appears without waiting for the network round-trip.
  /// Both the user message and the eventual AI reply are persisted to
  /// Firestore.  On error the placeholder is replaced with a visible error
  /// message rather than being removed.
  Future<void> sendMessage(String content, {required String botId}) async {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return;
    // Captured once: both saves below must go to the account that sent the
    // message, even if another account signs in while the reply is in flight.
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
    // saveMessage swallows its own errors (see ChatRepository), so the user
    // message write can safely run concurrently with the AI round-trip
    // instead of delaying it by one Firestore write.
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

  /// Clears all messages from state and deletes them from Firestore.
  ///
  /// Firestore deletion failures are logged and swallowed — the local state
  /// is cleared regardless so the user always gets a fresh-looking chat.
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

/// Global provider for the active chat message list.
final chatProvider = NotifierProvider<ChatNotifier, List<MessageModel>>(ChatNotifier.new);

/// Tracks which AI bot is currently selected (defaults to the planner bot).
///
/// Changed by the bot picker at the top of [AiChatScreen].
/// The selected id is passed into every [ChatNotifier.sendMessage] call so
/// each message is stored and rendered with the correct bot identity.
final selectedBotIdProvider = StateProvider<String>((_) => 'planner');
