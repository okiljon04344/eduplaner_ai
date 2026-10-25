import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/ai_bot.dart';
import '../providers/chat_provider.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/chat_input_bar.dart';
import '../widgets/quick_reply_chips.dart';
import '../../../core/l10n/app_strings.dart';

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
    final ok = await showConfirmDialog(
      context,
      title: AppStrings.t('chat_clear_title'),
      message: AppStrings.t('chat_clear_msg'),
      confirmLabel: AppStrings.t('ai_clear_btn'),
    );
    if (ok) {
      await ref.read(chatProvider.notifier).clearHistory();
    }
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(chatProvider);
    // The chat state resets on an account change; reload the new account's
    // history since this screen stays mounted.
    ref.listen(currentUserProvider.select((u) => u?.uid), (prev, next) {
      if (next != null && next != prev) ref.read(chatProvider.notifier).loadHistory();
    });

    final selectedBot = botById(ref.watch(selectedBotIdProvider));

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _AiChatHeader(bot: selectedBot, onClear: _clearHistory),
            const QuickReplyChips(),
            Expanded(
              child: ColoredBox(
                color: AppColors.background,
                child: messages.isEmpty
                    ? _ChatEmptyState(
                        bot: selectedBot,
                        onPick: (text) => ref
                            .read(chatProvider.notifier)
                            .sendMessage(text, botId: selectedBot.id),
                      )
                    : ListView.builder(
                        reverse: true,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                        itemCount: messages.length,
                        itemBuilder: (context, i) => ChatBubble(
                            message: messages[messages.length - 1 - i]),
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

/// Empty-conversation state: bot identity, a prompt and three example questions
/// that go through the normal send path.
class _ChatEmptyState extends StatelessWidget {
  final AiBot bot;
  final ValueChanged<String> onPick;
  const _ChatEmptyState({required this.bot, required this.onPick});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(bot.emoji, style: const TextStyle(fontSize: 48)),
            const SizedBox(height: 8),
            Text(bot.label,
                style: AppTextStyles.headLG, textAlign: TextAlign.center),
            const SizedBox(height: 4),
            Text(
              AppStrings.t('chat_empty_title'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Plus Jakarta Sans',
                fontFamilyFallback: const ['NotoSansJP'],
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 20),
            for (final key in const [
              'chat_example_1',
              'chat_example_2',
              'chat_example_3'
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: ActionChip(
                  onPressed: () => onPick(AppStrings.t(key)),
                  backgroundColor: AppColors.bgLayer,
                  side: BorderSide(
                      color: AppColors.primaryMid.withValues(alpha: 0.3)),
                  label: Text(
                    AppStrings.t(key),
                    style: TextStyle(
                      fontFamily: 'Plus Jakarta Sans',
                      fontFamilyFallback: const ['NotoSansJP'],
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AiChatHeader extends StatelessWidget {
  final AiBot bot;
  final VoidCallback onClear;
  const _AiChatHeader({required this.bot, required this.onClear});

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        gradient: AppColors.aiBannerGradient,
        border: Border(
            bottom: BorderSide(
                color: AppColors.primaryMid.withValues(alpha: 0.2), width: 1)),
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
                  colors: [
                    AppColors.primaryMid.withValues(alpha: 0.25),
                    Colors.transparent
                  ],
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
                      Text(
                        AppStrings.t('ai_badge'),
                        style: TextStyle(
                          fontFamily: 'Plus Jakarta Sans',
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                          color: AppColors.accentText,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text('${bot.emoji} ${bot.label}',
                          style: AppTextStyles.headLG),
                      const SizedBox(height: 4),
                      Text(
                        AppStrings.t('ai_subtitle'),
                        style: TextStyle(
                          fontFamily: 'Plus Jakarta Sans',
                          fontFamilyFallback: const ['NotoSansJP'],
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                _QuizButton(onTap: () => context.push('/quiz')),
                const SizedBox(width: 8),
                _ClearButton(onTap: onClear),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QuizButton extends StatelessWidget {
  final VoidCallback onTap;
  const _QuizButton({required this.onTap});

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
            border: Border.all(
                color: AppColors.primaryMid.withValues(alpha: 0.22), width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.quiz_outlined, size: 14, color: AppColors.accentText),
              const SizedBox(width: 4),
              Text(
                AppStrings.t('ai_quiz_btn'),
                style: TextStyle(
                  fontFamily: 'Plus Jakarta Sans',
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.accentText,
                ),
              ),
            ],
          ),
        ),
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
            border: Border.all(
                color: AppColors.primaryMid.withValues(alpha: 0.22), width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.refresh_rounded,
                  size: 14, color: AppColors.accentText),
              const SizedBox(width: 4),
              Text(
                AppStrings.t('ai_clear_btn'),
                style: TextStyle(
                  fontFamily: 'Plus Jakarta Sans',
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.accentText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
