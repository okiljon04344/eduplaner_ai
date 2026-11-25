import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/app_sheet.dart';
import '../../../shared/widgets/pressable.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/school_notice.dart';
import '../school_providers.dart';

const _shown = 3;

/// "M/d HH:mm" in the app locale; empty while the server time is pending.
///
/// UZ: Ilova lokalida "M/d HH:mm"; server vaqti kutilayotganda bo'sh bo'ladi.
String noticeTime(DateTime? at) =>
    at == null ? '' : DateFormat('M/d HH:mm', AppStrings.currentLocale).format(at);

/// Home card (§9.2-4): the latest notices for the student's class. Hidden when
/// there are none. Opening one shows it in full and counts as 既読.
///
/// UZ: Asosiy ekran kartasi (§9.2-4): talaba sinfi uchun eng so'nggi bildirishnomalar. Ular mavjud
/// bo'lmaganda yashiriladi. Bittasini ochish uni to'liq ko'rsatadi va 既読 sifatida hisoblanadi.
class SchoolNoticesCard extends ConsumerWidget {
  const SchoolNoticesCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notices = ref.watch(myNoticesProvider);
    if (notices.isEmpty) return const SizedBox.shrink();
    final seen = ref.watch(seenNoticesProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.cardSurface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.cardStroke),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 4),
              child: Row(
                children: [
                  Icon(Icons.campaign_outlined, size: 20, color: AppColors.accentText),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(AppStrings.t('notice_title'),
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                  ),
                  TextButton(
                      onPressed: () => context.push('/board'),
                      style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
                      child: Text(AppStrings.t('home_see_all'),
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.accentText)),
                    ),
                ],
              ),
            ),
            for (final n in notices.take(_shown)) NoticeRow(notice: n, unread: !seen.contains(n.id)),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }

}

/// "連絡 · 数学 · 訂正": category, subject tag and the correction stamp.
///
/// UZ: "連絡 · 数学 · 訂正": toifa, fan tegi va tuzatish muhri.
String noticeTags(SchoolNotice n) => [
      n.category.label,
      if (n.subject.isNotEmpty) n.subject,
      if (n.editedAt != null) AppStrings.t('board_edited'),
    ].join(' · ');

/// One notice line: urgent badge, unread dot, title, time · author.
///
/// UZ: Bitta bildirishnoma qatori: shoshilinch nishon, o'qilmagan nuqta, sarlavha, vaqt · muallif.
class NoticeRow extends ConsumerWidget {
  final SchoolNotice notice;
  final bool unread;
  const NoticeRow({super.key, required this.notice, required this.unread});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meta = [
      noticeTime(notice.createdAt),
      if (notice.authorName.isNotEmpty) AppStrings.t('notice_from', {'name': notice.authorName}),
    ].where((s) => s.isNotEmpty).join(' · ');
    return Pressable(
      child: InkWell(
        onTap: () => _open(context, ref),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 6, right: 8),
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: unread ? AppColors.danger : Colors.transparent,
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (notice.urgent) ...[const UrgentBadge(), const SizedBox(width: 6)],
                        Expanded(
                          child: Text(notice.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: unread ? FontWeight.w800 : FontWeight.w600,
                                  color: AppColors.textPrimary)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text([noticeTags(notice), meta].where((s) => s.isNotEmpty).join(' · '),
                        style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context, WidgetRef ref) {
    _markRead(ref);
    return showAppSheet<void>(
      context,
      (_) => SafeArea(child: NoticeDetail(notice: notice)),
    );
  }

  /// Local unread dot always; the teacher's 既読 count only for students.
  ///
  /// UZ: Doimo mahalliy o'qilmagan nuqta; o'qituvchining 既読 hisobi faqat talabalar uchun.
  void _markRead(WidgetRef ref) {
    ref.read(seenNoticesProvider.notifier).markSeen(notice.id);
    try {
      final domain = ref.read(schoolDomainProvider);
      final user = ref.read(currentUserProvider);
      if (domain == null || user == null) return;
      if (ref.read(schoolRoleProvider).teacher) return;
      ref.read(schoolRepositoryProvider).markNoticeRead(domain: domain, id: notice.id, uid: user.uid);
    } catch (e) {
      debugPrint('markNoticeRead skipped: $e');
    }
  }
}

/// Full notice text in a bottom sheet.
///
/// UZ: Pastki varaqda (bottom sheet) to'liq bildirishnoma matni.
class NoticeDetail extends StatelessWidget {
  final SchoolNotice notice;
  const NoticeDetail({super.key, required this.notice});

  @override
  Widget build(BuildContext context) {
    final meta = [
      noticeTime(notice.createdAt),
      if (notice.authorName.isNotEmpty) AppStrings.t('notice_from', {'name': notice.authorName}),
    ].where((s) => s.isNotEmpty).join(' · ');
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (notice.urgent) ...[const UrgentBadge(), const SizedBox(height: 8)],
          SelectableText(notice.title,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
          const SizedBox(height: 4),
          Text([noticeTags(notice), meta].where((s) => s.isNotEmpty).join(' · '),
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          if (notice.body.isNotEmpty) ...[
            const SizedBox(height: 16),
            SelectableText(notice.body,
                style: TextStyle(fontSize: 15, height: 1.6, color: AppColors.textPrimary)),
          ],
          if (notice.safeLink case final link?) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => launchUrl(link, mode: LaunchMode.externalApplication),
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              label: Text(AppStrings.t('board_open_link')),
            ),
            const SizedBox(height: 4),
            SelectableText(link.host, style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ],
        ],
      ),
    );
  }
}

/// Badge indicator displayed on high-priority or emergency school notices.
///
/// UZ: Yuqori ustuvorlikdagi yoki favqulodda maktab bildirishnomalarida ko'rsatiladigan nishon ko'rsatkichi.
class UrgentBadge extends StatelessWidget {
  const UrgentBadge({super.key});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: AppColors.danger.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(AppStrings.t('notice_urgent'),
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.danger)),
      );
}
