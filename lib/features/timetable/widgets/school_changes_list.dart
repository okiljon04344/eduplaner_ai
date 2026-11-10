import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/app_sheet.dart';
import '../../../shared/widgets/pressable.dart';
import '../../auth/providers/auth_provider.dart';
import '../../school/models/school.dart';
import '../../school/school_providers.dart';

const _seenKey = 'school_changes_seen_at';

/// Newest first; the server order isn't guaranteed and items without `at` go last.
List<SchoolChange> _newestFirst(List<SchoolChange> l) => [...l]..sort((a, b) {
    final x = a.at, y = b.at;
    if (x == null || y == null) return x == y ? 0 : (x == null ? 1 : -1);
    return y.compareTo(x);
  });

/// `M/d` for a `YYYY-MM-DD` change date; unparseable values pass through.
String _md(String date) {
  final d = DateTime.tryParse(date);
  return d == null ? date : '${d.month}/${d.day}';
}

/// The "last synced" footer line, or nothing without school data.
class SchoolLastSyncLine extends ConsumerWidget {
  final EdgeInsetsGeometry padding;
  final TextAlign textAlign;
  const SchoolLastSyncLine(
      {super.key,
      this.padding = EdgeInsets.zero,
      this.textAlign = TextAlign.center});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final at = ref.watch(schoolInfoProvider).valueOrNull?.lastSyncAt;
    if (at == null || ref.watch(schoolClassProvider) == null) {
      return const SizedBox.shrink();
    }
    final time = DateFormat('M/d HH:mm').format(at.toLocal());
    return Padding(
      padding: padding,
      child: Text(
        AppStrings.t('school_last_sync', {'time': time}),
        textAlign: textAlign,
        style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: AppColors.textMuted),
      ),
    );
  }
}

/// 「最近の変更」 feed. Sizes to its content; callers provide scrolling.
class SchoolChangesList extends ConsumerWidget {
  final bool compact;
  const SchoolChangesList({super.key, this.compact = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Loading/error show only the title, so a slow load never flashes
    // "no changes".
    final changes = ref.watch(schoolChangesProvider).valueOrNull;
    final periods = ref.watch(schoolInfoProvider).valueOrNull?.periods ??
        const <SchoolPeriod>[];
    String periodLabel(String key) {
      for (final p in periods) {
        if (p.key == key) return p.label;
      }
      return key;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: EdgeInsets.only(bottom: compact ? 8 : 12),
          child: Text(AppStrings.t('school_recent_changes'),
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary)),
        ),
        if (changes != null && changes.isEmpty)
          Text(AppStrings.t('school_no_changes'),
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textMuted)),
        for (final c in _newestFirst(changes ?? const []))
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 8),
            padding: EdgeInsets.symmetric(
                horizontal: 12, vertical: compact ? 8 : 10),
            decoration: BoxDecoration(
              color: AppColors.cardSurface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.cardStroke),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${_md(c.date)} · ${periodLabel(c.period)}',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary)),
                const SizedBox(height: 2),
                Text('${c.subject}  ${c.what}',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
              ],
            ),
          ),
      ],
    );
  }
}

/// Home banner: the newest change, shown while something is newer than the
/// stored [_seenKey]. Tapping opens the full feed and marks it seen.
class SchoolChangesBanner extends ConsumerStatefulWidget {
  const SchoolChangesBanner({super.key});

  @override
  ConsumerState<SchoolChangesBanner> createState() =>
      _SchoolChangesBannerState();
}

class _SchoolChangesBannerState extends ConsumerState<SchoolChangesBanner> {
  /// Null until prefs are read (banner stays hidden meanwhile); 0 = never seen.
  int? _seenAt;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => _seenAt = prefs.getInt(_seenKey) ?? 0);
  }

  Future<void> _open(DateTime newest, List<SchoolChange> changes) async {
    final ms = newest.millisecondsSinceEpoch;
    _markRead(changes);
    setState(() => _seenAt = ms);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_seenKey, ms);
    if (!mounted) return;
    await showAppSheet<void>(
      context,
      (_) => const SafeArea(
        child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(20, 20, 20, 24),
            child: SchoolChangesList()),
      ),
    );
  }

  /// 既読 for the teacher: every change newer than what was seen before.
  /// Teachers opening the banner are not counted.
  void _markRead(List<SchoolChange> changes) {
    // Best effort, like the write itself: never block opening the feed.
    try {
      final domain = ref.read(schoolDomainProvider);
      final cls = ref.read(schoolClassProvider);
      final user = ref.read(currentUserProvider);
      if (domain == null || cls == null || user == null) return;
      if (ref.read(schoolInfoProvider).valueOrNull?.isTeacher(user.uid, user.email) ?? false) return;
      final before = _seenAt ?? 0;
      final unseen = changes.where((c) => (c.at?.millisecondsSinceEpoch ?? 0) > before);
      ref.read(schoolRepositoryProvider).markRead(
          domain: domain, grade: cls.grade, course: cls.course, uid: user.uid, changes: unseen);
    } catch (e) {
      debugPrint('markRead skipped: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final seen = _seenAt;
    final changes =
        _newestFirst(ref.watch(schoolChangesProvider).valueOrNull ?? const []);
    final newest = changes.isEmpty ? null : changes.first;
    final at = newest?.at;
    if (seen == null ||
        newest == null ||
        at == null ||
        at.millisecondsSinceEpoch <= seen) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Pressable(
        child: Material(
          color: AppColors.warning.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => _open(at, changes),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                const Icon(Icons.notifications_active_outlined,
                    size: 20, color: AppColors.warning),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(AppStrings.t('school_recent_changes'),
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary)),
                      const SizedBox(height: 2),
                      Text(
                          '${_md(newest.date)} ${newest.subject} ${newest.what}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 12, color: AppColors.textSecondary)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  }
}
