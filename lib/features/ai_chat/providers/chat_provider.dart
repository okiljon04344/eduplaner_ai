import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../../core/providers/app_providers.dart';
import '../../assignments/providers/assignments_provider.dart';
import '../../auth/providers/auth_provider.dart';
import '../../timetable/providers/timetable_provider.dart';
import '../models/message_model.dart';
import '../repositories/chat_repository.dart';

class ChatNotifier extends Notifier<List<MessageModel>> {
  @override
  List<MessageModel> build() => [];

  String get _uid => ref.read(currentUserProvider)?.uid ?? '';
  ChatRepository get _repo => ref.read(chatRepositoryProvider);

  Future<void> loadHistory() async {
    if (_uid.isEmpty) return;
    final history = await _repo.loadHistory(_uid);
    state = history;
  }

  Future<void> sendMessage(String content) async {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return;
    final userMsg = MessageModel(id: const Uuid().v4(), content: trimmed, role: MessageRole.user, timestamp: DateTime.now());
    final loadingMsg = MessageModel(id: const Uuid().v4(), content: '', role: MessageRole.assistant, timestamp: DateTime.now(), isLoading: true);
    state = [...state, userMsg, loadingMsg];
    if (_uid.isNotEmpty) await _repo.saveMessage(_uid, userMsg);
    try {
      final classes = ref.read(timetableStreamProvider).valueOrNull ?? [];
      final assignments = ref.read(assignmentsStreamProvider).valueOrNull ?? [];
      final history = state.where((m) => !m.isLoading && !m.isError && m.id != loadingMsg.id).toList();
      final response = await _repo.sendToGemini(
        history: history,
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
