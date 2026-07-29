import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toastification/toastification.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/providers/theme_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../auth/providers/auth_provider.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  static const _storage = FlutterSecureStorage();
  bool _notificationsEnabled = true;

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

  void _showToast(String title) {
    toastification.show(
      context: context,
      type: ToastificationType.success,
      style: ToastificationStyle.flat,
      title: Text(title),
      autoCloseDuration: const Duration(seconds: 2),
    );
  }

  Future<void> _showApiKeyDialog() async {
    final controller = TextEditingController(text: await _storage.read(key: ApiConstants.geminiApiKeyName) ?? '');
    bool obscure = true;
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Gemini API キー'),
          content: TextField(
            controller: controller,
            obscureText: obscure,
            decoration: InputDecoration(
              hintText: 'APIキーを入力',
              suffixIcon: IconButton(
                icon: Icon(obscure ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setDialogState(() => obscure = !obscure),
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('キャンセル')),
            TextButton(
              onPressed: () async {
                await _storage.write(key: ApiConstants.geminiApiKeyName, value: controller.text.trim());
                if (ctx.mounted) Navigator.pop(ctx);
                if (!mounted) return;
                setState(() {});
                _showToast('APIキーを保存しました');
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
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

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final themeMode = ref.watch(themeProvider);
    final initials = (user?.name.isNotEmpty ?? false) ? user!.name.substring(0, 1) : 'U';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('設定'), backgroundColor: AppColors.background, elevation: 0),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          ListTile(
            leading: CircleAvatar(radius: 20, backgroundColor: AppColors.primary, child: Text(initials, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white))),
            title: Text(user?.name ?? 'ユーザー', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            subtitle: Text(user?.email ?? '', style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          ),
          const Divider(),
          const _SectionTitle('AI設定'),
          FutureBuilder<String?>(
            future: _storage.read(key: ApiConstants.geminiApiKeyName),
            builder: (context, snapshot) {
              final hasKey = (snapshot.data ?? '').isNotEmpty;
              return ListTile(
                leading: const Icon(Icons.key),
                title: const Text('Gemini API キー'),
                subtitle: Text(
                  hasKey ? '設定済み ✓' : '未設定 — AIチャットを使うために必要です',
                  style: TextStyle(color: hasKey ? AppColors.success : AppColors.danger),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: _showApiKeyDialog,
              );
            },
          ),
          const _SectionTitle('通知'),
          SwitchListTile(
            secondary: const Icon(Icons.notifications_outlined),
            title: const Text('通知設定'),
            value: _notificationsEnabled,
            onChanged: _toggleNotifications,
          ),
          const _SectionTitle('表示'),
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
          const ListTile(leading: Icon(Icons.info_outline), title: Text('バージョン'), trailing: Text('1.0.0', style: TextStyle(color: AppColors.textMuted))),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('プライバシーポリシー'),
            trailing: const Icon(Icons.open_in_new),
            onTap: () => launchUrl(Uri.parse('https://example.com/privacy')),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: TextButton(
                onPressed: _signOut,
                child: const Text('ログアウト', style: TextStyle(color: AppColors.danger)),
              ),
            ),
          ),
        ],
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
      child: Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textMuted)),
    );
  }
}
