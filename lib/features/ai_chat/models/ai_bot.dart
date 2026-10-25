import 'package:flutter/material.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_colors.dart';

/// Mirrors the `botPrompts` map in `functions/index.js`; keep the ids in sync
/// so `botId` round-trips.
class AiBot {
  final String id;
  final String emoji;
  final Color color;
  const AiBot({required this.id, required this.emoji, required this.color});

  /// Display name from `bot_<id>`, resolved on read so it follows the locale.
  String get label => AppStrings.t('bot_$id');
}

const List<AiBot> aiBots = [
  AiBot(id: 'planner', emoji: '📅', color: AppColors.primaryMid),
  AiBot(id: 'math', emoji: '🔢', color: AppColors.subjectMath),
  AiBot(id: 'english', emoji: '🇬🇧', color: AppColors.subjectEnglish),
  AiBot(id: 'programming', emoji: '💻', color: AppColors.subjectProgramming),
  AiBot(id: 'physics', emoji: '⚛️', color: AppColors.subjectPhysics),
  AiBot(id: 'chemistry', emoji: '🧪', color: AppColors.success),
  AiBot(id: 'history', emoji: '📜', color: AppColors.subjectHistory),
  AiBot(id: 'exam', emoji: '📝', color: AppColors.danger),
  AiBot(id: 'focus', emoji: '🎯', color: AppColors.cyan),
  AiBot(id: 'career', emoji: '🎓', color: AppColors.primaryLight),
];

AiBot botById(String id) => aiBots.firstWhere((b) => b.id == id, orElse: () => aiBots.first);
