import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toastification/toastification.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/providers/locale_provider.dart';
import '../../../core/providers/theme_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/responsive.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../auth/providers/auth_provider.dart';
import '../widgets/group_share_section.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _notificationsEnabled = true;
  bool _deletingAccount = false;

  @override
  void initState() {
    super.initState();
    _loadNotificationPref();
  }

  Future<void> _loadNotificationPref() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => _notificationsEnabled = prefs.getBool('notifications_enabled') ?? true);
  }

  Future<void> _toggleNotifications(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    if (enabled) {
      final status = await Permission.notification.request();
      if (!status.isGranted) {
        await prefs.setBool('notifications_enabled', false);
        if (!mounted) return;
        setState(() => _notificationsEnabled = false);
        return;
      }
    }
    await prefs.setBool('notifications_enabled', enabled);
    if (!mounted) return;
    setState(() => _notificationsEnabled = enabled);
  }

  Future<void> _signOut() async {
    final ok = await showConfirmDialog(context, title: 'ログアウト', message: 'ログアウトしますか？', confirmLabel: 'ログアウト');
    if (!ok) return;
    await ref.read(authNotifierProvider.notifier).signOut();
    if (mounted) context.go('/login');
  }

  Future<void> _deleteAccount() async {
    final ok = await showConfirmDialog(
      context,
      title: 'アカウントを削除',
      message: 'アカウントと課題・時間割・AIチャット履歴を含むすべてのデータが完全に削除されます。この操作は取り消せません。本当に削除しますか？',
      confirmLabel: '完全に削除',
    );
    if (!ok || !mounted) return;

    setState(() => _deletingAccount = true);
    try {
      await FirebaseFunctions.instance.httpsCallable('deleteAccount').call();
      await ref.read(authNotifierProvider.notifier).signOut();
      if (!mounted) return;
      context.go('/login');
    } catch (e) {
      if (!mounted) return;
      setState(() => _deletingAccount = false);
      toastification.show(
        context: context,
        type: ToastificationType.error,
        style: ToastificationStyle.flat,
        title: const Text('削除に失敗しました。もう一度お試しください。'),
        autoCloseDuration: const Duration(seconds: 3),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final themeMode = ref.watch(themeProvider);
    final initials = (user?.name.isNotEmpty ?? false) ? user!.name.substring(0, 1) : 'U';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('設定'), backgroundColor: AppColors.background, elevation: 0),
      body: ResponsiveBody(
        maxWidth: 640,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 40),
          children: [
          ListTile(
            leading: CircleAvatar(radius: 20, backgroundColor: AppColors.primary, child: Text(initials, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white))),
            title: Text(user?.name ?? 'ユーザー', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            subtitle: Text(user?.email ?? '', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          ),
          const Divider(),
          const _SectionTitle('AI設定'),
          const ListTile(
            leading: Icon(Icons.smart_toy_outlined, color: AppColors.success),
            title: Text('AIアシスタント'),
            subtitle: Text('有効 ✓ — 設定不要でご利用いただけます', style: TextStyle(color: AppColors.success)),
          ),
          const _SectionTitle('クラス共有'),
          const GroupShareSection(),
          const _SectionTitle('通知'),
          SwitchListTile(
            secondary: const Icon(Icons.notifications_outlined),
            title: const Text('通知設定'),
            value: _notificationsEnabled,
            onChanged: _toggleNotifications,
          ),
          const _SectionTitle('表示'),
          _LanguageTile(),
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: const Text('テーマ'),
            trailing: SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(value: ThemeMode.light, label: Text('ライト')),
                ButtonSegment(value: ThemeMode.system, label: Text('システム')),
                ButtonSegment(value: ThemeMode.dark, label: Text('ダーク')),
              ],
              selected: {themeMode},
              onSelectionChanged: (s) => ref.read(themeProvider.notifier).setTheme(s.first),
            ),
          ),
          const _SectionTitle('その他'),
          ListTile(leading: const Icon(Icons.info_outline), title: const Text('バージョン'), trailing: Text('1.0.0', style: TextStyle(color: AppColors.textMuted))),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('プライバシーポリシー'),
            trailing: const Icon(Icons.open_in_new),
            onTap: () => launchUrl(Uri.parse('https://okiljon04344.github.io/eduplaner_ai/privacy-policy.html')),
          ),
          ListTile(
            leading: const Icon(Icons.gavel_outlined),
            title: const Text('利用規約'),
            trailing: const Icon(Icons.open_in_new),
            onTap: () => launchUrl(Uri.parse('https://okiljon04344.github.io/eduplaner_ai/terms-of-service.html')),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Center(
              child: TextButton(
                onPressed: _signOut,
                child: const Text('ログアウト', style: TextStyle(color: AppColors.danger)),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Center(
              child: TextButton(
                onPressed: _deletingAccount ? null : _deleteAccount,
                child: _deletingAccount
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.danger))
                    : const Text('アカウントを削除', style: TextStyle(color: AppColors.danger, fontSize: 12)),
              ),
            ),
          ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textMuted)),
    );
  }
}

class _LanguageTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentLocale = ref.watch(localeProvider);
    final currentEntry = AppStrings.locales.where((l) => l.$1 == currentLocale).firstOrNull;
    final currentLabel = currentEntry != null ? '${currentEntry.$3} ${currentEntry.$2}' : currentLocale;

    return ListTile(
      leading: const Icon(Icons.language_outlined),
      title: Text(AppStrings.t('settings_language')),
      trailing: Text(currentLabel, style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
      onTap: () => _showLanguagePicker(context, ref, currentLocale),
    );
  }

  void _showLanguagePicker(BuildContext context, WidgetRef ref, String currentLocale) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, sc) => Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              AppStrings.t('settings_language'),
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                controller: sc,
                itemCount: AppStrings.locales.length,
                itemBuilder: (_, i) {
                  final (code, name, flag) = AppStrings.locales[i];
                  final isSelected = code == currentLocale;
                  return ListTile(
                    leading: Text(flag, style: const TextStyle(fontSize: 24)),
                    title: Text(name, style: TextStyle(
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
                      color: isSelected ? AppColors.primary : AppColors.textPrimary,
                    )),
                    trailing: isSelected ? const Icon(Icons.check_rounded, color: AppColors.primary) : null,
                    onTap: () {
                      Navigator.pop(ctx);
                      ref.read(localeProvider.notifier).setLocale(code);
                    },
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
