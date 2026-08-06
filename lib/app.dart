import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toastification/toastification.dart';
import 'core/providers/locale_provider.dart';
import 'core/providers/theme_provider.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';

/// Root widget for EduPlanner AI.
///
/// Watches [themeProvider] and [localeProvider], resolves the effective
/// [Brightness] (including the system value for [ThemeMode.system]), then:
///   1. Mutates [AppColors] static tokens via [AppColors.applyBrightness] so
///      every widget that reads those tokens picks up the new palette.
///   2. Keys [MaterialApp.router] with `ValueKey('${resolvedBrightness}_$locale')`
///      which forces a full subtree remount on theme or locale change — the
///      cheaper alternative to threading `Theme.of(context)` through ~370 call
///      sites.  GoRouter's navigation location is preserved across the remount;
///      in-progress scroll / animation / form state on the visible screen is not.
class EduPlannerApp extends ConsumerWidget {
  const EduPlannerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeProvider);
    final locale = ref.watch(localeProvider);
    final router = ref.watch(routerProvider);

    final resolvedBrightness = switch (themeMode) {
      ThemeMode.light => Brightness.light,
      ThemeMode.dark => Brightness.dark,
      ThemeMode.system => MediaQuery.platformBrightnessOf(context),
    };
    AppColors.applyBrightness(resolvedBrightness);

    // Use only the primary language subtag for MaterialApp locale so standard
    // Material widgets (date pickers, etc.) resolve their own localizations.
    // The full locale code (e.g. 'zh_TW') is still passed to AppStrings
    // separately so we can serve the correct JSON translation file.
    final flutterLocale = Locale(locale.split('_').first);

    return ToastificationWrapper(
      child: MaterialApp.router(
        key: ValueKey('${resolvedBrightness}_$locale'),
        title: 'EduPlanner AI',
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: themeMode,
        routerConfig: router,
        debugShowCheckedModeBanner: false,
        locale: flutterLocale,
        supportedLocales: const [
          Locale('ja'), Locale('en'), Locale('zh'), Locale('ko'),
          Locale('vi'), Locale('th'), Locale('id'), Locale('ms'),
          Locale('hi'), Locale('ar'), Locale('es'), Locale('fr'),
          Locale('de'), Locale('pt'), Locale('ru'), Locale('it'),
          Locale('tr'), Locale('nl'), Locale('fil'), Locale('uz'),
        ],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
      ),
    );
  }
}
