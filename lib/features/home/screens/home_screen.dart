import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/providers/locale_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/responsive.dart';
import '../../../shared/widgets/entrance.dart';
import '../../../shared/widgets/glass_panel.dart';
import '../../../shared/widgets/pressable.dart';
import '../../timetable/widgets/school_changes_list.dart';
import '../../school/widgets/school_notices_card.dart';
import '../providers/home_provider.dart';
import '../widgets/ai_study_tip_card.dart';
import '../widgets/greeting_header.dart';
import '../widgets/home_ambient_glow.dart';
import '../widgets/notification_prompt_card.dart';
import '../widgets/stats_row.dart';
import '../widgets/today_lessons.dart';
import '../../assignments/widgets/add_edit_assignment_sheet.dart';
import '../widgets/upcoming_assignments_list.dart';
import '../widgets/weak_area_card.dart';
import '../../../core/l10n/app_strings.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AppColors.background,
      floatingActionButton: Padding(
        padding: EdgeInsets.only(bottom: context.isTablet ? 0 : 84),
        child: Pressable(
          child: FloatingActionButton.extended(
            heroTag: 'home-add-assignment',
            onPressed: () => showAddEditAssignmentSheet(context, ref),
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.onPrimary,
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            icon: const Icon(Icons.add_rounded),
            label: Text(AppStrings.t('home_add_assignment'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          ),
        ),
      ),
      body: Stack(
        children: [
          const Positioned.fill(child: HomeAmbientGlow()),
          SafeArea(
            bottom: false,
            child: RefreshIndicator(
              color: AppColors.accentText,
              backgroundColor: AppColors.bgLayer,
              onRefresh: () async {
                // Explicit user refresh: drop today's cached AI results so the
                // providers below actually fetch instead of re-serving the cache.
                await clearTodaysAiCache(ref.read(localeProvider));
                ref.invalidate(aiStudyTipProvider);
                ref.invalidate(weakAreaProvider);
              },
              child: LayoutBuilder(builder: (context, constraints) {
                final classes = [
                  _SectionLabel(
                    text: AppStrings.t('home_today_classes'),
                    linkLabel: AppStrings.t('home_open_timetable'),
                    onTap: () => context.go('/timetable'),
                  ),
                  const TodayLessonsCard(),
                ];
                final dueSoon = [
                  _SectionLabel(
                    text: AppStrings.t('home_due_soon'),
                    linkLabel: AppStrings.t('home_see_all'),
                    onTap: () => context.go('/assignments'),
                  ),
                  const Padding(padding: EdgeInsets.symmetric(horizontal: 20), child: UpcomingAssignmentsList()),
                ];
                const aiTip = Padding(padding: EdgeInsets.fromLTRB(20, 20, 20, 12), child: AiStudyTipCard());
                final weakArea = Padding(padding: EdgeInsets.fromLTRB(20, 0, 20, context.isTablet ? 110 : 130), child: const WeakAreaCard());

                // Desktop: lessons on the left, assignments and AI on the right,
                // so a wide window shows the whole day without scrolling.
                final wide = constraints.maxWidth >= 900;
                return CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(
                      child: Entrance(
                        index: 0,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                          child: KeyedSubtree(
                            key: ValueKey(AppColors.brightness),
                            child: GlassPanel(
                              padding: const EdgeInsets.all(18),
                              radius: 24,
                              tint: AppColors.glassFill,
                              borderColor: AppColors.glassBorder,
                              shadows: AppColors.glassShadow,
                              child: const Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  GreetingHeader(),
                                  SizedBox(height: 16),
                                  StatsRow(),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SliverToBoxAdapter(
                      child: Entrance(
                        index: 1,
                        child: NowLessonCard(),
                      ),
                    ),
                    const SliverToBoxAdapter(
                      child: Entrance(
                        index: 2,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SchoolChangesBanner(),
                            SchoolNoticesCard(),
                            NotificationPromptCard(),
                          ],
                        ),
                      ),
                    ),
                    if (wide)
                      SliverToBoxAdapter(
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 1280),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  flex: 6,
                                  child: Column(
                                    children: [
                                      Entrance(
                                        index: 3,
                                        child: Column(mainAxisSize: MainAxisSize.min, children: classes),
                                      ),
                                      const SizedBox(height: 110),
                                    ],
                                  ),
                                ),
                                Expanded(
                                  flex: 5,
                                  child: Column(
                                    children: [
                                      Entrance(
                                        index: 4,
                                        child: Column(mainAxisSize: MainAxisSize.min, children: dueSoon),
                                      ),
                                      const Entrance(
                                        index: 5,
                                        child: aiTip,
                                      ),
                                      Entrance(
                                        index: 6,
                                        child: weakArea,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                    else
                      SliverList(
                        delegate: SliverChildListDelegate([
                          Entrance(
                            index: 3,
                            child: Column(mainAxisSize: MainAxisSize.min, children: classes),
                          ),
                          const SizedBox(height: 8),
                          Entrance(
                            index: 4,
                            child: Column(mainAxisSize: MainAxisSize.min, children: dueSoon),
                          ),
                          const Entrance(
                            index: 5,
                            child: aiTip,
                          ),
                          Entrance(
                            index: 6,
                            child: weakArea,
                          ),
                        ]),
                      ),
                  ],
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

/// Section title (17/700) with a plain text link on the right.
class _SectionLabel extends StatelessWidget {
  final String text, linkLabel;
  final VoidCallback onTap;
  const _SectionLabel({required this.text, required this.linkLabel, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 12, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(text,
                style: TextStyle(fontSize: 17, height: 1.4, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          ),
          TextButton(
            onPressed: onTap,
            style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
            child: Text(linkLabel,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.accentText)),
          ),
        ],
      ),
    );
  }
}
