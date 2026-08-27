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
import '../../../core/services/functions_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/responsive.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../auth/models/school_type.dart';
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
    final ok = await showConfirmDialog(context,
        title: AppStrings.t('set_logout'),
        message: AppStrings.t('set_logout_msg'),
        confirmLabel: AppStrings.t('set_logout'));
    if (!ok) return;
    await ref.read(authNotifierProvider.notifier).signOut();
    if (mounted) context.go('/login');
  }

  Future<void> _deleteAccount() async {
    final ok = await showConfirmDialog(
      context,
      title: AppStrings.t('set_delete_account'),
      message: AppStrings.t('set_delete_msg'),
      confirmLabel: AppStrings.t('set_delete_confirm'),
    );
    if (!ok || !mounted) return;

    setState(() => _deletingAccount = true);
    try {
      await FunctionsService.callable('deleteAccount').call();
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
        title: Text(AppStrings.t('set_delete_failed')),
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
      appBar: AppBar(title: Text(AppStrings.t('set_title')), backgroundColor: AppColors.background, elevation: 0),
      body: ResponsiveBody(
        maxWidth: 640,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
          children: [
            // Profile hero — gradient-tinted card so it reads as the top of the
            // page, not just another row.
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.primary.withValues(alpha: 0.16), AppColors.primary.withValues(alpha: 0.04)],
                ),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      gradient: AppColors.avatarGradient,
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: AppColors.primaryMid.withValues(alpha: 0.5), blurRadius: 18)],
                    ),
                    alignment: Alignment.center,
                    child: Text(initials, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user?.name ?? AppStrings.t('set_user_fallback'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary, fontFamily: 'Plus Jakarta Sans', fontFamilyFallback: const ['NotoSansJP']),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          user?.email ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            _SectionTitle(AppStrings.t('settings_school_info')),
            _SettingsCard(
              children: [
                _SettingsRow(
                  icon: Icons.school_outlined,
                  iconColor: AppColors.primaryMid,
                  title: (user?.school?.isNotEmpty ?? false) ? user!.school! : AppStrings.t('school_setup_title'),
                  subtitle: SchoolType.fromKey(user?.schoolType)?.label,
                  trailing: Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
                  onTap: () => context.push('/profile-setup'),
                ),
              ],
            ),
            _SectionTitle(AppStrings.t('settings_section_ai')),
            _SettingsCard(
              children: [
                _SettingsRow(
                  icon: Icons.smart_toy_outlined,
                  iconColor: AppColors.primary,
                  title: AppStrings.t('set_ai_assistant'),
                  subtitle: AppStrings.t('set_ai_enabled_sub'),
                  subtitleColor: AppColors.accentText,
                ),
              ],
            ),
            _SectionTitle(AppStrings.t('set_class_share')),
            _SettingsCard(children: [GroupShareSection()]),
            _SectionTitle(AppStrings.t('settings_section_notifications')),
            _SettingsCard(
              children: [
                _SettingsRow(
                  icon: Icons.notifications_outlined,
                  iconColor: AppColors.primaryMid,
                  title: AppStrings.t('settings_notifications'),
                  trailing: Switch(
                    value: _notificationsEnabled,
                    onChanged: _toggleNotifications,
                    activeThumbColor: AppColors.primary,
                  ),
                ),
              ],
            ),
            _SectionTitle(AppStrings.t('settings_section_display')),
            _SettingsCard(
              children: [
                _LanguageTile(),
                Divider(height: 1, color: AppColors.dividerSubtle),
                _SettingsRow(
                  icon: Icons.palette_outlined,
                  iconColor: AppColors.primaryMid,
                  title: AppStrings.t('settings_theme'),
                  trailing: SegmentedButton<ThemeMode>(
                    showSelectedIcon: false,
                    style: SegmentedButton.styleFrom(
                      backgroundColor: AppColors.surfaceVar,
                      selectedBackgroundColor: AppColors.primary.withValues(alpha: 0.22),
                      selectedForegroundColor: AppColors.accentText,
                      foregroundColor: AppColors.textSecondary,
                      side: BorderSide(color: AppColors.border),
                      textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                    segments: [
                      ButtonSegment(value: ThemeMode.light, label: Text(AppStrings.t('set_theme_light'))),
                      ButtonSegment(value: ThemeMode.system, label: Text(AppStrings.t('set_theme_system'))),
                      ButtonSegment(value: ThemeMode.dark, label: Text(AppStrings.t('set_theme_dark'))),
                    ],
                    selected: {themeMode},
                    onSelectionChanged: (s) => ref.read(themeProvider.notifier).setTheme(s.first),
                  ),
                ),
              ],
            ),
            _SectionTitle(AppStrings.t('settings_section_other')),
            _SettingsCard(
              children: [
                _SettingsRow(
                  icon: Icons.info_outline,
                  iconColor: AppColors.textMuted,
                  title: AppStrings.t('settings_version'),
                  trailing: Text('1.0.0', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
                ),
                Divider(height: 1, color: AppColors.dividerSubtle),
                _SettingsRow(
                  icon: Icons.privacy_tip_outlined,
                  iconColor: AppColors.textMuted,
                  title: AppStrings.t('set_privacy'),
                  trailing: Icon(Icons.open_in_new, size: 16, color: AppColors.textMuted),
                  onTap: () => launchUrl(Uri.parse('https://okiljon04344.github.io/eduplaner_ai/privacy-policy.html')),
                ),
                Divider(height: 1, color: AppColors.dividerSubtle),
                _SettingsRow(
                  icon: Icons.gavel_outlined,
                  iconColor: AppColors.textMuted,
                  title: AppStrings.t('set_terms'),
                  trailing: Icon(Icons.open_in_new, size: 16, color: AppColors.textMuted),
                  onTap: () => launchUrl(Uri.parse('https://okiljon04344.github.io/eduplaner_ai/terms-of-service.html')),
                ),
              ],
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _signOut,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.danger,
                  side: BorderSide(color: AppColors.danger.withValues(alpha: 0.4)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: Text(AppStrings.t('set_logout'), style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: TextButton(
                onPressed: _deletingAccount ? null : _deleteAccount,
                child: _deletingAccount
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.danger))
                    : Text(AppStrings.t('set_delete_account'), style: TextStyle(color: AppColors.danger.withValues(alpha: 0.7), fontSize: 12)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Rounded card grouping related settings rows — the single visual
/// container every section below uses, replacing bare `ListTile`s directly
/// on the scaffold background.
class _SettingsCard extends StatelessWidget {
  final List<Widget> children;
  const _SettingsCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.cardStroke),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}

/// One row inside a [_SettingsCard]: colored icon chip + title (+ optional
/// subtitle) + trailing widget, tappable when [onTap] is given.
class _SettingsRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final Color? subtitleColor;
  final Widget? trailing;
  final VoidCallback? onTap;
  const _SettingsRow({
    required this.icon,
    required this.iconColor,
    required this.title,
    this.subtitle,
    this.subtitleColor,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: iconColor.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(11)),
              alignment: Alignment.center,
              child: Icon(icon, size: 18, color: iconColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary, fontFamily: 'Plus Jakarta Sans', fontFamilyFallback: const ['NotoSansJP']),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: subtitleColor ?? AppColors.textSecondary),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 8), trailing!],
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
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 10),
      child: Text(
        title,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: AppColors.textMuted),
      ),
    );
  }
}

class _LanguageTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentLocale = ref.watch(localeProvider);
    final currentEntry = AppStrings.locales.where((l) => l.$1 == currentLocale).firstOrNull;
    final currentLabel = currentEntry != null ? '${currentEntry.$3} ${currentEntry.$2}' : currentLocale;

    return _SettingsRow(
      icon: Icons.language_outlined,
      iconColor: AppColors.primaryMid,
      title: AppStrings.t('settings_language'),
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
