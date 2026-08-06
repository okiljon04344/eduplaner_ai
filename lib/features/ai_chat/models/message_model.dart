import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'message_model.freezed.dart';
part 'message_model.g.dart';

enum MessageRole { user, assistant }

@freezed
class MessageModel with _$MessageModel {
  const factory MessageModel({
    required String id,
    required String content,
    required MessageRole role,
    required DateTime timestamp,
    @Default(false) bool isLoading,
    @Default(false) bool isError,
    @Default('planner') String botId,
  }) = _MessageModel;

  factory MessageModel.fromJson(Map<String, dynamic> json) => _$MessageModelFromJson(json);

  factory MessageModel.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    return MessageModel(
      id: doc.id,
      content: d['content'] as String? ?? '',
      role: (d['role'] as String? ?? 'assistant') == 'user' ? MessageRole.user : MessageRole.assistant,
      timestamp: (d['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      botId: d['botId'] as String? ?? 'planner',
    );
  }

  const MessageModel._();

  Map<String, dynamic> toFirestore() => {
        'content': content,
        'role': role.name,
        'timestamp': Timestamp.fromDate(timestamp),
        'botId': botId,
      };
}
