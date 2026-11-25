import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/subject_colors.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/responsive.dart';
import '../../../shared/widgets/app_input_field.dart';
import '../../../shared/widgets/entrance.dart';
import '../../../shared/widgets/glass_panel.dart';
import '../../../shared/widgets/lottie_helpers.dart';
import '../../../shared/widgets/pressable.dart';
import '../../assignments/providers/assignments_provider.dart';
import '../../home/widgets/home_ambient_glow.dart';
import '../../timetable/providers/timetable_provider.dart';
import '../../ai_chat/widgets/report_ai_content.dart';
import '../models/quiz_question.dart';
import '../providers/quiz_provider.dart';

/// テスト問題の自動生成 — pick a subject, optionally add a specific topic
/// and enable web-grounded generation, then answer 5 AI-generated MC questions
/// with instant correct/incorrect feedback + explanation.
///
/// UZ: テスト問題の自動生成 — fanni tanlang, ixtiyoriy ravishda aniq mavzu qo'shing va
/// vebga asoslangan yaratishni yoqing, so'ngra bir zumda to'g'ri/noto'g'ri fikr-mulohazalar + tushuntirish
/// bilan AI tomonidan yaratilgan 5 ta test savoliga javob bering.
class QuizScreen extends ConsumerStatefulWidget {
  const QuizScreen({super.key});

  @override
  ConsumerState<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends ConsumerState<QuizScreen> {
  final _subjectCtrl = TextEditingController(text: SubjectColors.all.first);
  final _topicCtrl = TextEditingController();
  // Off by default: each web-grounded quiz costs two AI calls.
  // UZ: Odatiy holda o'chiq: har bir vebga asoslangan test ikkita AI chaqiruvini talab qiladi.
  bool _useSearch = false;

  @override
  void dispose() {
    _subjectCtrl.dispose();
    _topicCtrl.dispose();
    super.dispose();
  }

  /// Suggestions only — the field always accepts a freely typed subject
  /// name too (school/college/university subject names vary), not just
  /// these. Combines the fixed color-coded subjects with any subject the
  /// student already uses in their timetable classes or assignments.
  ///
  /// UZ: Faqat takliflar — bu maydon har doim faqat bularni emas, balki erkin kiritilgan
  /// fan nomini ham qabul qiladi (maktab/kollej/universitet fan nomlari farq qiladi).
  /// Belgilangan rangli fanlarni talaba dars jadvalida yoki topshiriqlarida allaqachon
  /// foydalanayotgan har qanday fan bilan birlashtiradi.
  List<String> _subjectSuggestions() {
    final fromClasses = (ref.read(timetableStreamProvider).valueOrNull ?? []).map((c) => c.subject);
    final fromAssignments = (ref.read(assignmentsStreamProvider).valueOrNull ?? []).map((a) => a.subject);
    return {...SubjectColors.all, ...fromClasses, ...fromAssignments}.where((s) => s.trim().isNotEmpty).toList();
  }

  Future<void> _generate() async {
    if (_subjectCtrl.text.trim().isEmpty) return;
    FocusScope.of(context).unfocus();
    await ref.read(quizNotifierProvider.notifier).generate(
          subject: _subjectCtrl.text.trim(),
          topic: _topicCtrl.text.trim(),
          useSearch: _useSearch,
        );
  }

  @override
  Widget build(BuildContext context) {
    final quizState = ref.watch(quizNotifierProvider);
    final canPop = Navigator.of(context).canPop();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          const Positioned.fill(child: HomeAmbientGlow()),
          ResponsiveBody(
            maxWidth: 720,
            expandedMaxWidth: 720,
            child: SafeArea(
              bottom: false,
              // The whole page scrolls as a single CustomScrollView so the keyboard never overflows on small screens.
              // UZ: Kichik ekranlarda klaviatura sig'may qolmasligi uchun butun sahifa yagona CustomScrollView sifatida aylanadi.
              child: CustomScrollView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                slivers: [
                  SliverToBoxAdapter(
                    child: Entrance(
                      index: 0,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                        child: Row(
                          children: [
                            if (canPop) ...[
                              IconButton(
                                icon: Icon(Icons.arrow_back, color: AppColors.textPrimary),
                                onPressed: () => Navigator.of(context).maybePop(),
                              ),
                              const SizedBox(width: 4),
                            ],
                            Expanded(
                              child: Text(
                                AppStrings.t('quiz_title'),
                                style: TextStyle(
                                  fontSize: 24,
                                  height: 1.4,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ),
                            if ((quizState.valueOrNull ?? const <QuizQuestion>[]).isNotEmpty)
                              IconButton(
                                tooltip: AppStrings.t('ai_report_title'),
                                icon: Icon(Icons.outlined_flag, color: AppColors.textPrimary),
                                onPressed: () => confirmAndReportAiContent(
                                  context,
                                  kind: 'quiz',
                                  excerpt: quizState.value!.map((q) => q.question).join('\n'),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Entrance(
                      index: 1,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                        child: KeyedSubtree(
                          key: ValueKey(AppColors.brightness),
                          child: GlassPanel(
                            padding: const EdgeInsets.all(16),
                            radius: 24,
                            tint: AppColors.glassFill,
                            borderColor: AppColors.glassBorder,
                            shadows: AppColors.glassShadow,
                            child: _ConfigPanel(
                              subjectCtrl: _subjectCtrl,
                              subjectSuggestions: _subjectSuggestions(),
                              topicCtrl: _topicCtrl,
                              useSearch: _useSearch,
                              isLoading: quizState.isLoading,
                              onUseSearchChanged: (v) => setState(() => _useSearch = v),
                              onGenerate: _generate,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Entrance(
                      index: 2,
                      child: quizState.when(
                        loading: () => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 40),
                          child: _LoadingState(
                            onCancel: () => ref.read(quizNotifierProvider.notifier).cancel(),
                          ),
                        ),
                        error: (e, __) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 40),
                          child: _ErrorState(
                            message: e.toString().replaceFirst('Exception: ', ''),
                            onRetry: _generate,
                          ),
                        ),
                        data: (questions) {
                          if (questions.isEmpty) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 40),
                              child: _EmptyState(),
                            );
                          }
                          return Padding(
                            padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                            child: Column(
                              children: [
                                for (var i = 0; i < questions.length; i++)
                                  _QuizCard(
                                    key: ObjectKey(questions[i]),
                                    index: i,
                                    question: questions[i],
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  const SliverToBoxAdapter(
                    child: SizedBox(height: 32),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConfigPanel extends StatelessWidget {
  final TextEditingController subjectCtrl;
  final List<String> subjectSuggestions;
  final TextEditingController topicCtrl;
  final bool useSearch;
  final bool isLoading;
  final ValueChanged<bool> onUseSearchChanged;
  final VoidCallback onGenerate;
  const _ConfigPanel({
    required this.subjectCtrl,
    required this.subjectSuggestions,
    required this.topicCtrl,
    required this.useSearch,
    required this.isLoading,
    required this.onUseSearchChanged,
    required this.onGenerate,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          AppStrings.t('quiz_subject'),
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 6),
        Autocomplete<String>(
          // Seeded once; fieldViewBuilder must not reassign the text
          // or every rebuild would move the cursor to the end.
          // UZ: Bir marta boshlang'ich qiymat beriladi; fieldViewBuilder matnni qayta
          // tayinlamasligi kerak, aks holda har bir qayta qurish kursor oxiriga o'tib ketadi.
          initialValue: TextEditingValue(text: subjectCtrl.text),
          optionsBuilder: (value) {
            if (value.text.isEmpty) return subjectSuggestions;
            return subjectSuggestions.where((s) => s.contains(value.text));
          },
          onSelected: (value) => subjectCtrl.text = value,
          fieldViewBuilder: (context, controller, focusNode, onSubmit) {
            return AppInputField(
              controller: controller,
              focusNode: focusNode,
              hintText: AppStrings.t('fld_subject_hint_free'),
              onChanged: (v) => subjectCtrl.text = v,
            );
          },
        ),
        const SizedBox(height: 12),
        Text(
          AppStrings.t('quiz_topic'),
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: AppColors.textSecondary),
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
          // Own Material so the ListTile ink is not hidden by the box color.
          // UZ: ListTile siyoh (ink) effekti quti rangi bilan yashirinib qolmasligi uchun o'z Material vidjeti.
          child: Material(
            type: MaterialType.transparency,
            child: SwitchListTile.adaptive(
              value: useSearch,
              onChanged: isLoading ? null : onUseSearchChanged,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
              activeThumbColor: AppColors.primary,
              activeTrackColor: AppColors.primary.withValues(alpha: 0.38),
              thumbColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return states.contains(WidgetState.disabled)
                      ? AppColors.primary.withValues(alpha: 0.7)
                      : AppColors.primary;
                }
                return null;
              }),
              trackColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return states.contains(WidgetState.disabled)
                      ? AppColors.primary.withValues(alpha: 0.25)
                      : AppColors.primary.withValues(alpha: 0.38);
                }
                return null;
              }),
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
        ),
        const SizedBox(height: 14),
        Pressable(
          child: SizedBox(
            height: 54,
            child: ElevatedButton.icon(
              onPressed: isLoading ? null : onGenerate,
              style: ElevatedButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              icon: isLoading
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textSecondary),
                    )
                  : const Icon(Icons.auto_awesome, size: 18),
              label: Text(isLoading ? AppStrings.t('quiz_generating') : AppStrings.t('quiz_generate_btn')),
            ),
          ),
        ),
      ],
    );
  }
}

class _LoadingState extends StatelessWidget {
  final VoidCallback onCancel;
  const _LoadingState({required this.onCancel});

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
          const SizedBox(height: 16),
          TextButton(
            onPressed: onCancel,
            child: Text(AppStrings.t('common_cancel')),
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
            Icon(Icons.quiz_outlined, size: 40, color: AppColors.textMuted),
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
                  Icon(Icons.lightbulb_outline, size: 16, color: AppColors.accentText),
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
