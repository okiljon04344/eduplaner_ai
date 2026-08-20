import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../models/message_model.dart';
import 'typing_indicator.dart';

const _kAiBorderColorDark = Color(0x3306D6A0); // rgba(6,214,160,.2)

class ChatBubble extends StatelessWidget {
  final MessageModel message;
  const ChatBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == MessageRole.user;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          isUser ? _buildUserBubble(context) : _buildAssistantBubble(context),
          Padding(
            padding: EdgeInsets.only(top: 4, left: isUser ? 4 : 40, right: 4),
            child: Text(
              DateFormat('HH:mm').format(message.timestamp),
              style: TextStyle(
                fontFamily: 'Plus Jakarta Sans',
                fontFamilyFallback: const ['NotoSansJP'],
                fontSize: 10,
                color: AppColors.textMuted,
              ),
            ),
          ),
        ],
      ),
    )
        .animate()
        .fadeIn(duration: 300.ms, curve: Curves.easeOutExpo)
        .slideY(begin: 0.12, end: 0, duration: 300.ms, curve: Curves.easeOutExpo);
  }

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
