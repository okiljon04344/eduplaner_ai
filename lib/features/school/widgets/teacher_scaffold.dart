import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../school_providers.dart';
import '../teacher_overview_providers.dart';

/// Navigation sections available within the teacher portal.
///
/// UZ: O'qituvchi portalida mavjud navigatsiya bo'limlari.
enum TeacherSection {
  overview,
  timetable,
  notices,
  assignments,
  admin,
}

/// Scaffold frame adapting between mobile navigation and desktop sidebar layouts for teacher screens.
///
/// UZ: O'qituvchi ekranlari uchun mobil navigatsiya va desktop yon paneli maketlari o'rtasida
/// moslashuvchi scaffold ramkasi.
class TeacherScaffold extends ConsumerWidget {
  final TeacherSection section;
  final String title;
  final Widget body;
  final List<Widget>? actions;

  const TeacherScaffold({
    super.key,
    required this.section,
    required this.title,
    required this.body,
    this.actions,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDesktop = MediaQuery.sizeOf(context).width >= 1100;

    if (isDesktop) {
      return _DesktopTeacherScaffold(
        section: section,
        title: title,
        body: body,
        actions: actions,
      );
    }

    return _NarrowTeacherScaffold(
      section: section,
      title: title,
      body: body,
      actions: actions,
    );
  }
}

class _NarrowTeacherScaffold extends ConsumerWidget {
  final TeacherSection section;
  final String title;
  final Widget body;
  final List<Widget>? actions;

  const _NarrowTeacherScaffold({
    required this.section,
    required this.title,
    required this.body,
    this.actions,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(schoolRoleProvider);

    final destinations = <NavigationDestination>[
      NavigationDestination(
        icon: const Icon(Icons.grid_view_rounded),
        label: AppStrings.t('tov_nav_overview'),
      ),
      NavigationDestination(
        icon: const Icon(Icons.calendar_today_outlined),
        label: AppStrings.t('tov_nav_timetable_mobile'),
      ),
      NavigationDestination(
        icon: const Icon(Icons.campaign_outlined),
        label: AppStrings.t('tov_nav_notices'),
      ),
      NavigationDestination(
        icon: const Icon(Icons.assignment_outlined),
        label: AppStrings.t('sas_nav_assignments_mobile'),
      ),
      if (role.admin)
        NavigationDestination(
          icon: const Icon(Icons.people_alt_outlined),
          label: AppStrings.t('tov_nav_admin_mobile'),
        ),
    ];

    final selectedIndex = switch (section) {
      TeacherSection.overview => 0,
      TeacherSection.timetable => 1,
      TeacherSection.notices => 2,
      TeacherSection.assignments => 3,
      TeacherSection.admin => role.admin ? 4 : 0,
    };

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Text(
          title,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/settings');
            }
          },
        ),
        actions: actions,
      ),
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex.clamp(0, destinations.length - 1),
        destinations: destinations,
        onDestinationSelected: (idx) {
          switch (idx) {
            case 0:
              context.go('/teacher');
              break;
            case 1:
              context.go('/teacher/timetable');
              break;
            case 2:
              context.go('/teacher/notices');
              break;
            case 3:
              context.go('/teacher/assignments');
              break;
            case 4:
              if (role.admin) context.go('/school-admin');
              break;
          }
        },
      ),
    );
  }
}

class _DesktopTeacherScaffold extends ConsumerWidget {
  final TeacherSection section;
  final String title;
  final Widget body;
  final List<Widget>? actions;

  const _DesktopTeacherScaffold({
    required this.section,
    required this.title,
    required this.body,
    this.actions,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(schoolInfoProvider).valueOrNull;
    final role = ref.watch(schoolRoleProvider);
    final user = ref.watch(schoolUserIdentityProvider);
    final mine = info?.profileOf(user.email);
    final weekChanges = ref.watch(weekChangesProvider);
    final noticesSummary = ref.watch(myNoticesReadSummaryProvider);
    final lessonProgress = ref.watch(todayTeacherLessonsProgressProvider);

    final teacherName = (mine != null && mine.name.isNotEmpty)
        ? mine.name
        : ((user.displayName?.isNotEmpty ?? false)
            ? user.displayName!
            : AppStrings.t('tov_title'));

    final homeroom = (mine != null &&
            mine.homeroomGrade != null &&
            mine.homeroomCourse != null &&
            mine.homeroomCourse!.isNotEmpty)
        ? AppStrings.t('tov_homeroom_role', {'cls': '${mine.homeroomGrade}年${mine.homeroomCourse}'})
        : '';

    final avatarLetter = teacherName.isNotEmpty ? teacherName.characters.first : '教';

    int unreadCount = 0;
    if (noticesSummary.totalSize != null) {
      final unread = noticesSummary.totalSize! - noticesSummary.totalReads;
      unreadCount = unread > 0 ? unread : 0;
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Sidebar 236px
          // UZ: Yon panel 236px
          Padding(
            padding: const EdgeInsets.all(16),
            child: Container(
              width: 236,
              decoration: BoxDecoration(
                color: AppColors.cardSurface,
                border: Border.all(color: AppColors.cardStroke),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Logo row
                    // UZ: Logo qatori
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 0, 4, 14),
                      child: Row(
                        children: [
                          Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.school_rounded,
                              size: 18,
                              color: AppColors.onPrimary,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'EduPlanner AI',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                Text(
                                  '${info?.name ?? ''} · ${AppStrings.t('tov_title')}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Group: 授業
                    // UZ: Guruh: 授業
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
                      child: Text(
                        AppStrings.t('tov_group_classes'),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ),
                    _SidebarItem(
                      icon: Icons.grid_view_rounded,
                      label: AppStrings.t('tov_nav_overview'),
                      selected: section == TeacherSection.overview,
                      onTap: () => context.go('/teacher'),
                    ),
                    const SizedBox(height: 2),
                    _SidebarItem(
                      icon: Icons.calendar_today_outlined,
                      label: AppStrings.t('tov_nav_timetable'),
                      selected: section == TeacherSection.timetable,
                      badge: weekChanges.total > 0
                          ? Text(
                              '${weekChanges.total}',
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.textMuted,
                              ),
                            )
                          : null,
                      onTap: () => context.go('/teacher/timetable'),
                    ),

                    // Group: 連絡
                    // UZ: Guruh: 連絡
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 14, 10, 4),
                      child: Text(
                        AppStrings.t('tov_group_contact'),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ),
                    _SidebarItem(
                      icon: Icons.campaign_outlined,
                      label: AppStrings.t('tov_nav_notices'),
                      selected: section == TeacherSection.notices,
                      badge: unreadCount > 0
                          ? Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                              decoration: BoxDecoration(
                                color: AppColors.danger.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                AppStrings.t('tov_unread_badge', {'n': unreadCount}),
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.danger,
                                ),
                              ),
                            )
                          : null,
                      onTap: () => context.go('/teacher/notices'),
                    ),
                    const SizedBox(height: 2),
                    _SidebarItem(
                      icon: Icons.assignment_outlined,
                      label: AppStrings.t('tov_nav_assignments'),
                      selected: section == TeacherSection.assignments,
                      onTap: () => context.go('/teacher/assignments'),
                    ),

                    // Group: 管理
                    // UZ: Guruh: 管理
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 14, 10, 4),
                      child: Text(
                        AppStrings.t('tov_group_admin'),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ),
                    if (role.admin) ...[
                      _SidebarItem(
                        icon: Icons.people_alt_outlined,
                        label: AppStrings.t('tov_nav_admin'),
                        selected: section == TeacherSection.admin,
                        onTap: () => context.go('/school-admin'),
                      ),
                      const SizedBox(height: 2),
                    ],
                    _SidebarItem(
                      icon: Icons.settings_outlined,
                      label: AppStrings.t('tov_nav_settings'),
                      onTap: () => context.push('/settings'),
                    ),

                    const Spacer(),

                    // Today's progress card
                    // UZ: Bugungi progress kartochkasi
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(color: AppColors.cardStroke),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                AppStrings.t('tov_today_lessons_progress'),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              Text(
                                AppStrings.t('tov_lessons_finished', {
                                  'done': lessonProgress.done,
                                  'total': lessonProgress.total,
                                }),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Container(
                            height: 6,
                            decoration: BoxDecoration(
                              color: AppColors.borderLight,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: FractionallySizedBox(
                              alignment: Alignment.centerLeft,
                              widthFactor: lessonProgress.progress,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: AppColors.primary,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Teacher row
                    // UZ: O'qituvchi qatori
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Row(
                        children: [
                          Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.14),
                              shape: BoxShape.circle,
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              avatarLetter,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: AppColors.accentText,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  teacherName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                if (homeroom.isNotEmpty)
                                  Text(
                                    homeroom,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: AppColors.textMuted,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 10),

                    // Link back to /home
                    // UZ: /home ga qaytish havolasi
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => context.go('/home'),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        child: Row(
                          children: [
                            Icon(
                              Icons.arrow_back_rounded,
                              size: 16,
                              color: AppColors.textSecondary,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              AppStrings.t('tov_nav_return_app'),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Main area
          // UZ: Asosiy soha
          Expanded(
            child: (section == TeacherSection.overview ||
                    section == TeacherSection.notices ||
                    section == TeacherSection.assignments)
                ? body
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 20, 24, 12),
                        child: Row(
                          children: [
                            Text(
                              title,
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const Spacer(),
                            if (actions != null) ...actions!,
                          ],
                        ),
                      ),
                      Expanded(child: body),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final Widget? badge;

  const _SidebarItem({
    required this.icon,
    required this.label,
    this.selected = false,
    this.onTap,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final fg = selected
        ? AppColors.accentText
        : AppColors.textSecondary;
    final bg = selected ? AppColors.primary.withValues(alpha: 0.14) : Colors.transparent;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 40),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: fg),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    color: fg,
                  ),
                ),
              ),
              if (badge != null) badge!,
            ],
          ),
        ),
      ),
    );
  }
}
