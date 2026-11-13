import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/responsive.dart';
import '../../timetable/widgets/school_changes_list.dart';
import '../models/school_notice.dart';
import '../school_providers.dart';
import '../widgets/school_notices_card.dart';

/// Urgent notices first (pinned), then newest first. Notices whose server
/// time is still pending sort as newest.
List<SchoolNotice> sortBoard(Iterable<SchoolNotice> notices) => [...notices]..sort((a, b) {
    if (a.urgent != b.urgent) return a.urgent ? -1 : 1;
    final x = a.createdAt, y = b.createdAt;
    if (x == null || y == null) return x == y ? 0 : (x == null ? -1 : 1);
    return y.compareTo(x);
  });

/// 掲示板: every notice teachers sent to the student's class. Read-only for
/// students — no replies or comments by design. Filter by category, and by
/// subject when opened from a timetable lesson.
class BoardScreen extends ConsumerStatefulWidget {
  /// Subject tag to pre-filter on (the lesson that was tapped), or null.
  final String? subject;
  const BoardScreen({super.key, this.subject});

  @override
  ConsumerState<BoardScreen> createState() => _BoardScreenState();
}

class _BoardScreenState extends ConsumerState<BoardScreen> {
  NoticeCategory? _category;
  late String? _subject = (widget.subject ?? '').trim().isEmpty ? null : widget.subject!.trim();

  @override
  Widget build(BuildContext context) {
    final seen = ref.watch(seenNoticesProvider);
    final subject = _subject;
    final notices = sortBoard(ref.watch(myNoticesProvider).where((n) =>
        (_category == null || n.category == _category) && (subject == null || n.hasSubject(subject))));
    // The synced 休講/変更 feed is per class, not per subject.
    final showChanges = subject == null && (_category == null || _category == NoticeCategory.change);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Text(AppStrings.t('board_title')),
      ),
      body: SafeArea(
        child: ResponsiveBody(
          maxWidth: 720,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final c in <NoticeCategory?>[null, ...NoticeCategory.values])
                    ChoiceChip(
                      label: Text(c == null ? AppStrings.t('board_cat_all') : c.label),
                      selected: _category == c,
                      onSelected: (_) => setState(() => _category = c),
                    ),
                  if (subject != null)
                    InputChip(
                      label: Text(AppStrings.t('board_subject_only', {'subject': subject})),
                      onDeleted: () => setState(() => _subject = null),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              if (showChanges) const SchoolChangesList(compact: true),
              if (notices.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Text(AppStrings.t('board_empty'),
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
                )
              else
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  decoration: BoxDecoration(
                    color: AppColors.cardSurface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.cardStroke),
                  ),
                  child: Column(
                    children: [
                      for (final n in notices) NoticeRow(notice: n, unread: !seen.contains(n.id)),
                    ],
                  ),
                ),
              const SchoolLastSyncLine(padding: EdgeInsets.only(top: 16)),
            ],
          ),
        ),
      ),
    );
  }
}
