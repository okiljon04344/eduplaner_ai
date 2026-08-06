import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../timetable/models/class_model.dart';

const Map<int, (String start, String end)> _periodTimes = {
  1: ('09:00', '10:30'),
  2: ('10:40', '12:10'),
  3: ('13:00', '14:30'),
  4: ('14:40', '16:10'),
  5: ('16:20', '17:50'),
  6: ('18:00', '19:30'),
};

enum _ClassStatus { live, soon, later }

class HomeClassCard extends StatelessWidget {
  final ClassModel classModel;
  const HomeClassCard({super.key, required this.classModel});

  ({_ClassStatus status, String label}) _computeStatus() {
    final times = _periodTimes[classModel.period];
    if (times == null) return (status: _ClassStatus.later, label: '');
    final now = DateTime.now();
    DateTime parse(String t) {
      final parts = t.split(':');
      return DateTime(now.year, now.month, now.day, int.parse(parts[0]), int.parse(parts[1]));
    }

    final start = parse(times.$1);
    final end = parse(times.$2);
    if (now.isAfter(start) && now.isBefore(end)) return (status: _ClassStatus.live, label: '授業中');
    if (now.isBefore(start)) {
      final diff = start.difference(now);
      if (diff.inHours < 1) return (status: _ClassStatus.soon, label: '${diff.inMinutes}分後');
      return (status: _ClassStatus.later, label: '${diff.inHours}時間後');
    }
    return (status: _ClassStatus.later, label: '終了');
  }

  @override
  Widget build(BuildContext context) {
    final times = _periodTimes[classModel.period] ?? ('--:--', '--:--');
    final result = _computeStatus();
    final isLive = result.status == _ClassStatus.live;

    return Container(
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
        color: isLive && AppColors.isDark
            ? null
            : (AppColors.isDark ? AppColors.cardBg : AppColors.surface),
        borderRadius: BorderRadius.circular(AppColors.isDark ? 22 : 20),
        border: Border.all(
          color: isLive
              ? AppColors.primaryMid.withValues(alpha: AppColors.isDark ? 0.4 : 0.35)
              : AppColors.cardBorder,
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
                  : (AppColors.isDark ? AppColors.surfaceVar : AppColors.surfaceVar),
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
                  '${times.$1} – ${times.$2} · ${classModel.room}',
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
          _StatusBadge(status: result.status, label: result.label),
        ],
      ),
    );
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
        bg = AppColors.isDark ? AppColors.surfaceVar : AppColors.surfaceVar;
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
