import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toastification/toastification.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/providers/app_providers.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../auth/providers/auth_provider.dart';

/// Asks the user to confirm, then files an `ai_reports` document for AI-generated
/// content (Google Play AI-generated content policy). [kind] is `'chat'` or
/// `'quiz'`; [botId]/[refId] are chat-only.
///
/// Reads providers through [ProviderScope.containerOf] so it works from plain
/// stateless widgets.
Future<void> confirmAndReportAiContent(
  BuildContext context, {
  required String kind,
  String? botId,
  String? refId,
  required String excerpt,
}) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final uid = container.read(currentUserProvider)?.uid;
  if (uid == null || uid.isEmpty) return;
  final ok = await showConfirmDialog(
    context,
    title: AppStrings.t('ai_report_title'),
    message: AppStrings.t('ai_report_msg'),
    confirmLabel: AppStrings.t('ai_report_confirm'),
  );
  if (!ok || !context.mounted) return;
  try {
    await container.read(chatRepositoryProvider).reportAiContent(
          userId: uid,
          kind: kind,
          botId: botId,
          refId: refId,
          excerpt: excerpt,
        );
    if (!context.mounted) return;
    toastification.show(
      context: context,
      type: ToastificationType.success,
      style: ToastificationStyle.flat,
      title: Text(AppStrings.t('ai_report_done')),
      autoCloseDuration: const Duration(seconds: 3),
    );
  } catch (_) {
    if (!context.mounted) return;
    toastification.show(
      context: context,
      type: ToastificationType.error,
      style: ToastificationStyle.flat,
      title: Text(AppStrings.t('err_generic_retry')),
      autoCloseDuration: const Duration(seconds: 3),
    );
  }
}
