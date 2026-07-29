import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../providers/chat_provider.dart';

class _QuickReply {
  final String emoji;
  final String text;
  final Color color;
  const _QuickReply(this.emoji, this.text, this.color);
}

class QuickReplyChips extends ConsumerWidget {
  const QuickReplyChips({super.key});

  static const _chips = [
    _QuickReply('📚', '問題を生成する', AppColors.primaryMid),
    _QuickReply('🗓', '学習スケジュールを提案', AppColors.cyan),
    _QuickReply('🎯', '苦手分野を分析', AppColors.amber),
    _QuickReply('🔢', '積分問題を解く', AppColors.danger),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: Color(0x05FFFFFF),
        border: Border(bottom: BorderSide(color: AppColors.borderLight, width: 1)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: _chips.map((chip) {
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _Chip(
                chip: chip,
                onTap: () => ref.read(chatProvider.notifier).sendMessage(chip.text),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final _QuickReply chip;
  final VoidCallback onTap;
  const _Chip({required this.chip, required this.onTap});

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
            color: chip.color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: chip.color.withValues(alpha: 0.22), width: 1),
          ),
          child: Text(
            '${chip.emoji} ${chip.text}',
            style: TextStyle(
              fontFamily: 'Plus Jakarta Sans',
              fontFamilyFallback: const ['NotoSansJP'],
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: chip.color,
            ),
          ),
        ),
      ),
    );
  }
}
