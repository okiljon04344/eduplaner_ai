import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
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
    if (_uid.isNotEmpty) await _repo.saveMessage(_uid, userMsg);
    try {
      final classes = ref.read(timetableStreamProvider).valueOrNull ?? [];
      final assignments = ref.read(assignmentsStreamProvider).valueOrNull ?? [];
      final response = await _repo.sendMessage(
        botId: botId,
        userMessage: trimmed,
        classes: classes,
        assignments: assignments,
      );
      final assistantMsg = loadingMsg.copyWith(content: response, isLoading: false);
      state = state.map((m) => m.id == loadingMsg.id ? assistantMsg : m).toList();
      if (_uid.isNotEmpty) await _repo.saveMessage(_uid, assistantMsg);
    } catch (e) {
      final errMsg = loadingMsg.copyWith(
        content: 'エラー: ${e.toString().replaceAll('Exception: ', '')}',
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
