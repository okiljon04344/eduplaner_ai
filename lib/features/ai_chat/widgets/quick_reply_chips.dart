import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../models/ai_bot.dart';
import '../providers/chat_provider.dart';

/// Bot picker for the subject bots defined in `botPrompts` (functions/index.js).
class QuickReplyChips extends ConsumerWidget {
  const QuickReplyChips({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedBotIdProvider);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0x05FFFFFF),
        border:
            Border(bottom: BorderSide(color: AppColors.borderLight, width: 1)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: aiBots.map((bot) {
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _BotChip(
                bot: bot,
                selected: bot.id == selected,
                onTap: () =>
                    ref.read(selectedBotIdProvider.notifier).state = bot.id,
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _BotChip extends StatelessWidget {
  final AiBot bot;
  final bool selected;
  final VoidCallback onTap;
  const _BotChip(
      {required this.bot, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: bot.color.withValues(alpha: selected ? 0.28 : 0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: bot.color.withValues(alpha: selected ? 0.7 : 0.22),
                width: selected ? 1.5 : 1),
          ),
          child: Text(
            '${bot.emoji} ${bot.label}',
            style: TextStyle(
              fontFamily: 'Plus Jakarta Sans',
              fontFamilyFallback: const ['NotoSansJP'],
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: bot.color,
            ),
          ),
        ),
      ),
    );
  }
}
