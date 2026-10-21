import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/periods.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/providers/clock_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../timetable/models/class_model.dart';
import '../../timetable/widgets/class_detail_sheet.dart';

enum _ClassStatus { live, soon, later }

class HomeClassCard extends ConsumerWidget {
  final ClassModel classModel;
  const HomeClassCard({super.key, required this.classModel});

  /// Live / soon / later / ended label for the class as of [now].
  ({_ClassStatus status, String label}) _computeStatus(DateTime now) {
    final start = periodStartOn(now, classModel.period);
    final end = periodEndOn(now, classModel.period);
    if (start == null || end == null) return (status: _ClassStatus.later, label: '');
    if (!now.isBefore(start) && now.isBefore(end)) return (status: _ClassStatus.live, label: AppStrings.t('class_live'));
    if (now.isBefore(start)) {
      final diff = start.difference(now);
      // Round up so the last partial minute reads "1 min", never "0 min".
      final minutes = (diff.inMicroseconds / Duration.microsecondsPerMinute).ceil();
      if (minutes <= 60) return (status: _ClassStatus.soon, label: AppStrings.t('class_min_later').replaceAll('{n}', '$minutes'));
      return (status: _ClassStatus.later, label: AppStrings.t('class_hour_later').replaceAll('{n}', '${diff.inHours}'));
    }
    return (status: _ClassStatus.later, label: AppStrings.t('class_ended'));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Re-evaluated every minute so live / "in N min" / ended stay current.
    final now = ref.watch(minuteTickProvider).valueOrNull ?? DateTime.now();
    final times = periodTimeLabels(classModel.period);
    final result = _computeStatus(now);
    final isLive = result.status == _ClassStatus.live;

    return RepaintBoundary(child: GestureDetector(
      onTap: () => showClassDetailSheet(context, ref, classModel),
      child: Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: isLive && AppColors.isDark
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppColors.primaryMid.withValues(alpha: 0.2),
                  AppColors.primaryMid.withValues(alpha: 0.06),
                ],
              )
            : null,
        color: isLive && AppColors.isDark ? null : AppColors.cardSurface,
        borderRadius: BorderRadius.circular(AppColors.isDark ? 22 : 20),
        border: Border.all(
          color: isLive
              ? AppColors.primaryMid.withValues(alpha: AppColors.isDark ? 0.4 : 0.35)
              : AppColors.cardStroke,
        ),
        boxShadow: AppColors.isDark
            ? (isLive ? [BoxShadow(color: AppColors.primaryMid.withValues(alpha: 0.25), blurRadius: 20)] : null)
            : AppColors.heroCardShadow,
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: isLive
                  ? AppColors.primaryMid.withValues(alpha: 0.15)
                  : AppColors.surfaceVar,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isLive
                    ? AppColors.primaryMid.withValues(alpha: 0.35)
                    : AppColors.border,
              ),
            ),
            alignment: Alignment.center,
            child: Text(_subjectEmoji(classModel.subject), style: const TextStyle(fontSize: 22)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  classModel.subject,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                    color: AppColors.textPrimary,
                    fontFamily: 'Plus Jakarta Sans',
                    fontFamilyFallback: const ['NotoSansJP'],
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${times.start} – ${times.end} · ${classModel.room}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: isLive ? AppColors.textSecondary : AppColors.textMuted,
                    fontFamily: 'Plus Jakarta Sans',
                    fontFamilyFallback: const ['NotoSansJP'],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (classModel.statusAppliesTo(now))
            _AlertBadge(cancelled: classModel.status == ClassStatus.cancelled, label: classModel.status.label)
          else
            _StatusBadge(status: result.status, label: result.label),
        ],
      ),
      ),
    ));
  }

  String _subjectEmoji(String subject) {
    if (subject.contains('プログラ') || subject.contains('情報')) return '💻';
    if (subject.contains('数学')) return '📐';
    if (subject.contains('英語')) return '🌐';
    if (subject.contains('物理')) return '⚡';
    if (subject.contains('化学')) return '🧪';
    if (subject.contains('歴史')) return '📜';
    if (subject.contains('体育')) return '🏃';
    return '📘';
  }
}

class _StatusBadge extends StatelessWidget {
  final _ClassStatus status;
  final String label;
  const _StatusBadge({required this.status, required this.label});

  @override
  Widget build(BuildContext context) {
    late final Color bg;
    late final Color fg;
    late final List<BoxShadow>? glow;
    switch (status) {
      case _ClassStatus.live:
        bg = AppColors.success;
        fg = Colors.white;
        glow = [BoxShadow(color: AppColors.success.withValues(alpha: 0.5), blurRadius: 14)];
        break;
      case _ClassStatus.soon:
        bg = AppColors.amber.withValues(alpha: 0.12);
        fg = AppColors.amber;
        glow = null;
        break;
      case _ClassStatus.later:
        bg = AppColors.surfaceVar;
        fg = AppColors.textMuted;
        glow = null;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        boxShadow: glow,
        border: status == _ClassStatus.soon ? Border.all(color: AppColors.amber.withValues(alpha: 0.2)) : null,
      ),
      child: Text(
        status == _ClassStatus.live ? '● $label' : label,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: fg, letterSpacing: 0.3),
      ),
    );
  }
}

/// Today's cancellation/change badge (same colors as the timetable's status
/// banner); replaces the time-state badge when an alert is active.
class _AlertBadge extends StatelessWidget {
  final bool cancelled;
  final String label;
  const _AlertBadge({required this.cancelled, required this.label});

  @override
  Widget build(BuildContext context) {
    final color = cancelled ? AppColors.danger : AppColors.warning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: color, letterSpacing: 0.3)),
    );
  }
}
