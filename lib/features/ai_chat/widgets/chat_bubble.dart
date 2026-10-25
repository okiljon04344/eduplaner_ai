import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/l10n/app_strings.dart';
import '../models/message_model.dart';
import 'report_ai_content.dart';
import 'typing_indicator.dart';

const _kAiBorderColorDark = Color(0x3306D6A0);

class ChatBubble extends StatelessWidget {
  final MessageModel message;
  const ChatBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == MessageRole.user;
    final canReport = !isUser && !message.isLoading && !message.isError;
    final bubble = Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (isUser)
            _buildUserBubble(context)
          else if (canReport)
            GestureDetector(onLongPress: () => _report(context), child: _buildAssistantBubble(context))
          else
            _buildAssistantBubble(context),
          Padding(
            padding: EdgeInsets.only(top: 4, left: isUser ? 4 : 40, right: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  DateFormat('HH:mm').format(message.timestamp),
                  style: TextStyle(
                    fontFamily: 'Plus Jakarta Sans',
                    fontFamilyFallback: const ['NotoSansJP'],
                    fontSize: 10,
                    color: AppColors.textMuted,
                  ),
                ),
                if (canReport)
                  IconButton(
                    onPressed: () => _report(context),
                    tooltip: AppStrings.t('ai_report_title'),
                    icon: Icon(Icons.outlined_flag, size: 14, color: AppColors.textMuted),
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    padding: EdgeInsets.zero,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    // Animate only fresh messages: replaying on rebuild or scroll-back janks scrolling.
    if (DateTime.now().difference(message.timestamp) >= const Duration(seconds: 3)) return bubble;
    return bubble
        .animate()
        .fadeIn(duration: 300.ms, curve: Curves.easeOutExpo)
        .slideY(begin: 0.12, end: 0, duration: 300.ms, curve: Curves.easeOutExpo);
  }

  void _report(BuildContext context) => confirmAndReportAiContent(
        context,
        kind: 'chat',
        botId: message.botId,
        refId: message.id,
        excerpt: message.content,
      );

  Widget _buildUserBubble(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.75),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          gradient: AppColors.userBubbleGradient,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
            bottomLeft: Radius.circular(20),
            bottomRight: Radius.circular(4),
          ),
        ),
        child: Text(
          message.content,
          style: const TextStyle(
            fontFamily: 'Plus Jakarta Sans',
            fontFamilyFallback: ['NotoSansJP'],
            fontSize: 13,
            fontWeight: FontWeight.w500,
            height: 1.6,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _buildAssistantBubble(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            gradient: AppColors.gradientPrimary,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(color: AppColors.primaryMid.withValues(alpha: 0.5), blurRadius: 14),
            ],
          ),
          alignment: Alignment.center,
          child: const Text('🤖', style: TextStyle(fontSize: 15)),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Container(
            constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.7),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.bgLayer,
              border: AppColors.isDark
                  ? Border.all(color: _kAiBorderColorDark, width: 1)
                  : null,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
                bottomLeft: Radius.circular(4),
                bottomRight: Radius.circular(20),
              ),
            ),
            child: message.isLoading
                ? const TypingIndicator()
                : message.isError
                    ? Text(
                        message.content,
                        style: const TextStyle(
                          fontFamily: 'Plus Jakarta Sans',
                          fontFamilyFallback: ['NotoSansJP'],
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          height: 1.6,
                          color: AppColors.danger,
                        ),
                      )
                    : SelectableText(
                        message.content,
                        // SelectableText owns long-press (text selection), so the
                        // report action is also offered in its context menu.
                        contextMenuBuilder: (ctx, state) => AdaptiveTextSelectionToolbar.buttonItems(
                          anchors: state.contextMenuAnchors,
                          buttonItems: [
                            ...state.contextMenuButtonItems,
                            ContextMenuButtonItem(
                              label: AppStrings.t('ai_report_title'),
                              onPressed: () {
                                state.hideToolbar();
                                _report(context);
                              },
                            ),
                          ],
                        ),
                        style: TextStyle(
                          fontFamily: 'Plus Jakarta Sans',
                          fontFamilyFallback: const ['NotoSansJP'],
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          height: 1.6,
                          color: AppColors.textPrimary,
                        ),
                      ),
          ),
        ),
      ],
    );
  }
}
