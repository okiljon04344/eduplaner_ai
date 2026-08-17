import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/services/functions_service.dart';
import '../../assignments/models/assignment_model.dart';
import '../../timetable/models/class_model.dart';
import '../models/message_model.dart';

/// Data layer for AI tutor chat.
///
/// All AI inference happens server-side via the `chatWithTutor` Cloud Function —
/// the Gemini API key never leaves the Firebase backend.  This class only:
///   - Builds the minimal, privacy-safe payload sent to the function.
///   - Persists messages to Firestore so history survives app restarts.
///   - Loads the last 50 messages on demand (capped to keep read costs low).
class ChatRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Reference to the messages sub-collection for a given user.
  CollectionReference _msgs(String userId) =>
      _db.collection('ai_chats').doc(userId).collection('messages');

  /// Calls the `chatWithTutor` Cloud Function and returns the AI reply.
  ///
  /// Only anonymous, non-identifying fields leave the device:
  ///   - Assignments: `{subject, dueDate, status, progress}` — no title or
  ///     description (may contain personal notes).
  ///   - Classes: `{subject, dayOfWeek, period}` — no teacher names
  ///     (third-party personal data).
  ///
  /// Throws a localised [Exception] (via [AppStrings]) on error so callers
  /// can surface it directly in the UI without further translation.
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
        // Privacy: only anonymous, non-identifying fields leave the device —
        // no assignment titles/descriptions (may contain personal notes) and
        // no teacher names (third-party personal data). The AI still gets
        // enough context (subject, due date, progress) to give useful advice.
        'assignments': assignments.map((a) => {'subject': a.subject, 'dueDate': a.dueDateLabel, 'status': a.status.label, 'progress': a.progress}).toList(),
        'classes': classes.map((c) => {'subject': c.subject, 'dayOfWeek': c.dayOfWeek, 'period': c.period}).toList(),
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
      if (e.code == 'deadline-exceeded' || e.code == 'unavailable') {
        throw Exception(FunctionsService.describeError(e));
      }
      throw Exception(AppStrings.t('err_ai_connection_failed'));
    }
  }

  /// Writes a single [MessageModel] to Firestore.
  ///
  /// Failures are logged with [debugPrint] and swallowed — a failed save
  /// should never crash the chat UI; the message is already shown locally.
  Future<void> saveMessage(String userId, MessageModel msg) async {
    try {
      await _msgs(userId).doc(msg.id).set(msg.toFirestore());
    } catch (e) {
      debugPrint('Chat save error: $e');
    }
  }

  /// Returns the last 50 messages for [userId] ordered by timestamp.
  ///
  /// Returns an empty list on any error so the chat screen opens cleanly
  /// even without a network connection.
  Future<List<MessageModel>> loadHistory(String userId) async {
    try {
      final snap = await _msgs(userId).orderBy('timestamp').limitToLast(50).get();
      return snap.docs.map(MessageModel.fromFirestore).toList();
    } catch (_) {
      return [];
    }
  }

  /// Deletes all messages for [userId] in a single batched write.
  Future<void> clearHistory(String userId) async {
    final snap = await _msgs(userId).get();
    final batch = _db.batch();
    for (final doc in snap.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }
}
