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
  @override
  List<MessageModel> build() => [];

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

  /// Loads the last 50 messages from Firestore and replaces the current state.
  ///
  /// Called once when the chat screen mounts.  No-op when not signed in.
  Future<void> loadHistory() async {
    if (_uid.isEmpty) return;
    final history = await _repo.loadHistory(_uid);
    state = history;
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
    final userMsgSave = _uid.isNotEmpty ? _repo.saveMessage(_uid, userMsg) : Future<void>.value();
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
      if (_uid.isNotEmpty) await _repo.saveMessage(_uid, assistantMsg);
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
