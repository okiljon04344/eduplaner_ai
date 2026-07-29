import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../providers/chat_provider.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/chat_input_bar.dart';
import '../widgets/quick_reply_chips.dart';

class AiChatScreen extends ConsumerStatefulWidget {
  const AiChatScreen({super.key});

  @override
  ConsumerState<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends ConsumerState<AiChatScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(chatProvider.notifier).loadHistory();
    });
  }

  Future<void> _clearHistory() async {
    final ok = await showConfirmDialog(context, title: 'チャットをクリア', message: '会話履歴をすべて削除しますか？', confirmLabel: 'クリア');
    if (ok) {
      await ref.read(chatProvider.notifier).clearHistory();
    }
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(chatProvider);
    final reversed = messages.reversed.toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _AiChatHeader(onClear: _clearHistory),
            const QuickReplyChips(),
            Expanded(
              child: ColoredBox(
                color: AppColors.background,
                child: ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  itemCount: reversed.length,
                  itemBuilder: (context, i) => ChatBubble(message: reversed[i]),
                ),
              ),
            ),
            const ChatInputBar(),
          ],
        ),
      ),
    );
  }
}

class _AiChatHeader extends StatelessWidget {
  final VoidCallback onClear;
  const _AiChatHeader({required this.onClear});

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.hardEdge,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF050311), Color(0xFF0D0521)],
        ),
        border: Border(bottom: BorderSide(color: Color(0x33A855F7), width: 1)),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -30,
            right: -30,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [AppColors.primaryMid.withValues(alpha: 0.25), Colors.transparent],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 16, 18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'AI POWERED',
                        style: TextStyle(
                          fontFamily: 'Plus Jakarta Sans',
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                          color: Color(0x8CA855F7),
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text('🤖 AIアシスタント', style: AppTextStyles.headLG),
                      const SizedBox(height: 4),
                      Text(
                        'Gemini 1.5 Flash',
                        style: TextStyle(
                          fontFamily: 'Plus Jakarta Sans',
                          fontFamilyFallback: const ['NotoSansJP'],
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: AppColors.primaryLight.withValues(alpha: 0.4),
                        ),
                      ),
                    ],
                  ),
                ),
                _ClearButton(onTap: onClear),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ClearButton extends StatelessWidget {
  final VoidCallback onTap;
  const _ClearButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.primaryMid.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.primaryMid.withValues(alpha: 0.22), width: 1),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.refresh_rounded, size: 14, color: AppColors.primaryLight),
              SizedBox(width: 4),
              Text(
                'クリア',
                style: TextStyle(
                  fontFamily: 'Plus Jakarta Sans',
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primaryLight,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
