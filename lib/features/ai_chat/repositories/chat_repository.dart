import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/services/functions_service.dart';
import '../../assignments/models/assignment_model.dart';
import '../../timetable/models/class_model.dart';
import '../models/message_model.dart';

/// Data layer for the AI tutor chat. Inference runs in the `chatWithTutor`
/// Cloud Function, so the Gemini API key never reaches the client. This class
/// builds the payload for it and persists/loads the last 50 messages.
class ChatRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference _msgs(String userId) =>
      _db.collection('ai_chats').doc(userId).collection('messages');

  /// Calls `chatWithTutor` and returns the reply. Throws a localised [Exception]
  /// that callers can show as is.
  ///
  /// Privacy: only non-identifying fields leave the device. Assignments send
  /// `{subject, dueDate, status, progress}` (titles and descriptions may hold
  /// personal notes); classes send `{subject, dayOfWeek, period}` (teacher names
  /// are third-party personal data). That is still enough for useful advice.
  Future<String> sendMessage({
    required String botId,
    required String userMessage,
    required List<ClassModel> classes,
    required List<AssignmentModel> assignments,
  }) async {
    try {
      final callable = FunctionsService.callable('chatWithTutor');
      final result = await callable.call<Map<String, dynamic>>({
        'botId': botId,
        'message': userMessage,
        'language': AppStrings.currentLocale,
        'assignments': assignments
            .map((a) => {
                  'subject': a.subject,
                  'dueDate': a.dueDateLabel,
                  'status': a.status.label,
                  'progress': a.progress
                })
            .toList(),
        'classes': classes
            .map((c) => {
                  'subject': c.subject,
                  'dayOfWeek': c.dayOfWeek,
                  'period': c.period
                })
            .toList(),
      });
      final reply = result.data['reply'] as String?;
      if (reply == null || reply.isEmpty) {
        throw Exception(AppStrings.t('err_ai_no_response'));
      }
      return reply;
    } on FirebaseFunctionsException catch (e) {
      debugPrint('chatWithTutor error: ${e.code} ${e.message}');
      if (e.code == 'unauthenticated') {
        throw Exception(AppStrings.t('err_login_required'));
      }
      if (e.code == 'deadline-exceeded' ||
          e.code == 'unavailable' ||
          e.code == 'resource-exhausted') {
        throw Exception(FunctionsService.describeError(e));
      }
      throw Exception(AppStrings.t('err_ai_connection_failed'));
    }
  }

  /// Files a report of AI-generated content in `ai_reports` (write-only from
  /// the client; reviewed in the Firebase console). [excerpt] is trimmed to
  /// 1000 chars to match the Firestore rule. Throws on failure so the caller
  /// can tell the user.
  Future<void> reportAiContent({
    required String userId,
    required String kind,
    String? botId,
    String? refId,
    required String excerpt,
  }) {
    final text = excerpt.length > 1000 ? excerpt.substring(0, 1000) : excerpt;
    return _db.collection('ai_reports').add({
      'userId': userId,
      'kind': kind,
      'botId': botId,
      'refId': refId,
      'excerpt': text,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Saves one message. Failures are logged and swallowed: the message is
  /// already shown locally and a failed save must not break the chat.
  Future<void> saveMessage(String userId, MessageModel msg) async {
    try {
      await _msgs(userId).doc(msg.id).set(msg.toFirestore());
    } catch (e) {
      debugPrint('Chat save error: $e');
    }
  }

  /// The last 50 messages ordered by time; empty on any error so the chat opens
  /// offline.
  Future<List<MessageModel>> loadHistory(String userId) async {
    try {
      final snap =
          await _msgs(userId).orderBy('timestamp').limitToLast(50).get();
      return snap.docs.map(MessageModel.fromFirestore).toList();
    } catch (_) {
      return [];
    }
  }

  /// Deletes all messages in one batch.
  Future<void> clearHistory(String userId) async {
    final snap = await _msgs(userId).get();
    final batch = _db.batch();
    for (final doc in snap.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }
}
