import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../auth/providers/auth_provider.dart';

/// Asks for notification permission on Home, after sign-in, with the reason
/// in view — instead of a bare OS dialog at first launch. Shown once.
///
/// UZ: Ilk ishga tushirilgandagi quruq OT muloqot oynasi o'rniga, sababi ko'rsatilgan holda
/// tizimga kirgandan keyin Asosiy ekranda bildirishnoma ruxsatini so'raydi. Bir marta ko'rsatiladi.
class NotificationPromptCard extends ConsumerStatefulWidget {
  const NotificationPromptCard({super.key});

  @override
  ConsumerState<NotificationPromptCard> createState() => _NotificationPromptCardState();
}

class _NotificationPromptCardState extends ConsumerState<NotificationPromptCard> {
  bool _show = false;

  @override
  void initState() {
    super.initState();
    NotificationService.needsPermissionPrompt().then((v) {
      if (mounted && v) setState(() => _show = true);
    });
  }

  Future<void> _turnOn() async {
    setState(() => _show = false);
    final granted = await NotificationService.requestPermission(uid: ref.read(currentUserProvider)?.uid);
    if (granted && !kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      final exactAllowed = await NotificationService.refreshExactAlarmPermission();
      if (!exactAllowed) {
        await NotificationService.requestExactAlarmPermission();
      }
    }
  }

  Future<void> _later() async {
    setState(() => _show = false);
    await NotificationService.dismissPermissionPrompt();
  }

  @override
  Widget build(BuildContext context) {
    if (!_show) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
        decoration: BoxDecoration(
          color: AppColors.cardSurface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.borderPrimary),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.notifications_active_outlined, size: 20, color: AppColors.accentText),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(AppStrings.t('notif_prompt_title'),
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(AppStrings.t('notif_prompt_body'),
                style: TextStyle(fontSize: 13, height: 1.5, color: AppColors.textSecondary)),
            const SizedBox(height: 8),
            Row(
              children: [
                FilledButton(onPressed: _turnOn, child: Text(AppStrings.t('notif_prompt_on'))),
                const SizedBox(width: 4),
                TextButton(onPressed: _later, child: Text(AppStrings.t('notif_prompt_later'))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
