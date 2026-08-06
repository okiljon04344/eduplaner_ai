import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

/// Mirrors the `botPrompts` map in `functions/index.js` — keep the `id`
/// values in sync with that file so `botId` round-trips correctly.
class AiBot {
  final String id;
  final String emoji;
  final String label;
  final Color color;
  const AiBot({required this.id, required this.emoji, required this.label, required this.color});
}

const List<AiBot> aiBots = [
  AiBot(id: 'planner', emoji: '📅', label: 'プランナー', color: AppColors.primaryMid),
  AiBot(id: 'math', emoji: '🔢', label: '数学', color: AppColors.subjectMath),
  AiBot(id: 'english', emoji: '🇬🇧', label: '英語', color: AppColors.subjectEnglish),
  AiBot(id: 'programming', emoji: '💻', label: 'プログラミング', color: AppColors.subjectProgramming),
  AiBot(id: 'physics', emoji: '⚛️', label: '物理', color: AppColors.subjectPhysics),
  AiBot(id: 'chemistry', emoji: '🧪', label: '化学', color: AppColors.success),
  AiBot(id: 'history', emoji: '📜', label: '歴史', color: AppColors.subjectHistory),
  AiBot(id: 'exam', emoji: '📝', label: '試験', color: AppColors.danger),
  AiBot(id: 'focus', emoji: '🎯', label: '集中', color: AppColors.cyan),
  AiBot(id: 'career', emoji: '🎓', label: '進路', color: AppColors.primaryLight),
];

AiBot botById(String id) => aiBots.firstWhere((b) => b.id == id, orElse: () => aiBots.first);
