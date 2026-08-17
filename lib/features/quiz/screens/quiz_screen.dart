import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/subject_colors.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/app_input_field.dart';
import '../../../shared/widgets/lottie_helpers.dart';
import '../models/quiz_question.dart';
import '../providers/quiz_provider.dart';

/// テスト問題の自動生成 — pick a subject, optionally add a specific topic
/// and enable web-grounded generation, then answer 5 AI-generated MC questions
/// with instant correct/incorrect feedback + explanation.
class QuizScreen extends ConsumerStatefulWidget {
  const QuizScreen({super.key});

  @override
  ConsumerState<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends ConsumerState<QuizScreen> {
  String _subject = SubjectColors.all.first;
  final _topicCtrl = TextEditingController();
  bool _useSearch = true;

  @override
  void dispose() {
    _topicCtrl.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    FocusScope.of(context).unfocus();
    await ref.read(quizNotifierProvider.notifier).generate(
      subject: _subject,
      topic: _topicCtrl.text.trim(),
      useSearch: _useSearch,
    );
  }

  @override
  Widget build(BuildContext context) {
    final quizState = ref.watch(quizNotifierProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(AppStrings.t('quiz_title')),
        backgroundColor: AppColors.background,
        elevation: 0,
      ),
      body: SafeArea(
        child: Column(
          children: [
            _ConfigPanel(
              subject: _subject,
              topicCtrl: _topicCtrl,
              useSearch: _useSearch,
              isLoading: quizState.isLoading,
              onSubjectChanged: (v) => setState(() => _subject = v),
              onUseSearchChanged: (v) => setState(() => _useSearch = v),
              onGenerate: _generate,
            ),
            const Divider(height: 1),
            Expanded(
              child: quizState.when(
                loading: () => const _LoadingState(),
                error: (e, __) => _ErrorState(
                  message: e.toString().replaceFirst('Exception: ', ''),
                  onRetry: _generate,
                ),
                data: (questions) {
                  if (questions.isEmpty) return const _EmptyState();
                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                    itemCount: questions.length,
                    // Keyed by question identity: without this, regenerating a
                    // quiz reuses the old _QuizCardState at each position, so
                    // answers from the previous quiz appear pre-selected on the
                    // new questions.
                    itemBuilder: (context, i) => _QuizCard(key: ObjectKey(questions[i]), index: i, question: questions[i]),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConfigPanel extends StatelessWidget {
  final String subject;
  final TextEditingController topicCtrl;
  final bool useSearch;
  final bool isLoading;
  final ValueChanged<String> onSubjectChanged;
  final ValueChanged<bool> onUseSearchChanged;
  final VoidCallback onGenerate;
  const _ConfigPanel({
    required this.subject,
    required this.topicCtrl,
    required this.useSearch,
    required this.isLoading,
    required this.onSubjectChanged,
    required this.onUseSearchChanged,
    required this.onGenerate,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            AppStrings.t('quiz_subject'),
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: AppColors.bgInput,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: subject,
                isExpanded: true,
                icon: Icon(Icons.keyboard_arrow_down, color: AppColors.textSecondary),
                dropdownColor: AppColors.surface,
                style: TextStyle(fontSize: 14, color: AppColors.textPrimary, fontFamily: 'Plus Jakarta Sans', fontFamilyFallback: const ['NotoSansJP']),
                items: SubjectColors.all
                    .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                    .toList(),
                onChanged: isLoading ? null : (v) { if (v != null) onSubjectChanged(v); },
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            AppStrings.t('quiz_topic'),
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 6),
          AppInputField(
            controller: topicCtrl,
            hintText: AppStrings.t('quiz_topic_hint'),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => isLoading ? null : onGenerate(),
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: AppColors.surfaceVar,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            child: SwitchListTile.adaptive(
              value: useSearch,
              onChanged: isLoading ? null : onUseSearchChanged,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
              activeThumbColor: AppColors.primary,
              title: Text(
                AppStrings.t('quiz_use_search'),
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
              ),
              subtitle: Text(
                AppStrings.t('quiz_use_search_sub'),
                style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
              ),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 48,
            child: ElevatedButton.icon(
              onPressed: isLoading ? null : onGenerate,
              icon: isLoading
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.auto_awesome, size: 18),
              label: Text(isLoading ? AppStrings.t('quiz_generating') : AppStrings.t('quiz_generate_btn')),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppLottie.loading(size: 90),
          const SizedBox(height: 16),
          Text(
            AppStrings.t('quiz_loading'),
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 4),
          Text(
            AppStrings.t('quiz_loading_sub'),
            style: TextStyle(fontSize: 11, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('📚', style: TextStyle(fontSize: 40)),
            const SizedBox(height: 12),
            Text(
              AppStrings.t('quiz_empty'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 40, color: AppColors.danger),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppColors.textPrimary, height: 1.5),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 16),
              label: Text(AppStrings.t('common_retry')),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuizCard extends StatefulWidget {
  final int index;
  final QuizQuestion question;
  const _QuizCard({super.key, required this.index, required this.question});

  @override
  State<_QuizCard> createState() => _QuizCardState();
}

class _QuizCardState extends State<_QuizCard> {
  int? _selected;

  @override
  Widget build(BuildContext context) {
    final answered = _selected != null;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardStroke),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Q${widget.index + 1}. ${widget.question.question}', style: AppTextStyles.headMD),
          const SizedBox(height: 12),
          ...List.generate(widget.question.choices.length, (i) {
            final isCorrect = i == widget.question.answerIndex;
            final isSelected = i == _selected;
            Color? bg;
            Color borderColor = AppColors.border;
            Widget? trailing;
            if (answered) {
              if (isCorrect) {
                bg = AppColors.successLight;
                borderColor = AppColors.success;
                trailing = const Icon(Icons.check_circle, size: 18, color: AppColors.success);
              } else if (isSelected) {
                bg = AppColors.dangerLight;
                borderColor = AppColors.danger;
                trailing = const Icon(Icons.cancel, size: 18, color: AppColors.danger);
              }
            }
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: GestureDetector(
                onTap: answered ? null : () => setState(() => _selected = i),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: borderColor)),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(widget.question.choices[i], style: TextStyle(fontSize: 13, color: AppColors.textPrimary)),
                      ),
                      if (trailing != null) trailing,
                    ],
                  ),
                ),
              ),
            );
          }),
          if (answered) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primaryLight.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.primaryMid.withValues(alpha: 0.15)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.lightbulb_outline, size: 16, color: AppColors.primaryMid),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(widget.question.explanation, style: TextStyle(fontSize: 12, height: 1.5, color: AppColors.textSecondary)),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
