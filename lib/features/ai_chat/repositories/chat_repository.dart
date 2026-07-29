import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import '../../../core/constants/api_constants.dart';
import '../../assignments/models/assignment_model.dart';
import '../../timetable/models/class_model.dart';
import '../models/message_model.dart';

class ChatRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  CollectionReference _msgs(String userId) => _db.collection('ai_chats').doc(userId).collection('messages');

  Future<String> sendToGemini({
    required List<MessageModel> history,
    required String userMessage,
    required List<ClassModel> classes,
    required List<AssignmentModel> assignments,
  }) async {
    final storedKey = await _storage.read(key: ApiConstants.geminiApiKeyName);
    final apiKey = (storedKey != null && storedKey.trim().isNotEmpty) ? storedKey.trim() : ApiConstants.geminiDefaultApiKey;
    final model = GenerativeModel(
      model: ApiConstants.geminiModel,
      apiKey: apiKey,
      systemInstruction: Content.system(_buildSystemPrompt(classes, assignments)),
    );
    final geminiHistory = history
        .where((m) => !m.isLoading && !m.isError)
        .map((m) => m.role == MessageRole.user ? Content.text(m.content) : Content.model([TextPart(m.content)]))
        .toList();
    final chat = model.startChat(history: geminiHistory);
    final response = await chat.sendMessage(Content.text(userMessage));
    final text = response.text;
    if (text == null || text.isEmpty) {
      throw Exception('AIからの応答がありませんでした');
    }
    return text;
  }

  String _buildSystemPrompt(List<ClassModel> classes, List<AssignmentModel> assignments) {
    final buffer = StringBuffer()
      ..writeln('あなたはEduPlanner AIアシスタントです。日本語で丁寧に答えてください。')
      ..writeln('')
      ..writeln('【学生の時間割】');
    if (classes.isEmpty) {
      buffer.writeln('（授業が登録されていません）');
    } else {
      for (final c in classes) {
        buffer.writeln('${c.dayOfWeek}曜日 ${c.period}限: ${c.subject}（${c.teacher}先生, ${c.room}）');
      }
    }
    buffer
      ..writeln('')
      ..writeln('【未完了の課題】');
    final pending = assignments.where((a) => a.status != AssignmentStatus.completed).toList();
    if (pending.isEmpty) {
      buffer.writeln('（未完了の課題はありません）');
    } else {
      for (final a in pending) {
        buffer.writeln('${a.subject}「${a.title}」締め切り: ${a.dueDateLabel}（${a.status.label}）');
      }
    }
    buffer
      ..writeln('')
      ..writeln('この情報を使って学生に具体的なアドバイスをしてください。');
    return buffer.toString();
  }

  Future<void> saveMessage(String userId, MessageModel msg) async {
    try {
      await _msgs(userId).doc(msg.id).set(msg.toFirestore());
    } catch (e) {
      debugPrint('Chat save error: $e');
    }
  }

  Future<List<MessageModel>> loadHistory(String userId) async {
    try {
      final snap = await _msgs(userId).orderBy('timestamp').limitToLast(50).get();
      return snap.docs.map(MessageModel.fromFirestore).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> clearHistory(String userId) async {
    final snap = await _msgs(userId).get();
    final batch = _db.batch();
    for (final doc in snap.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }
}
