import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toastification/toastification.dart';
import 'core/providers/locale_provider.dart';
import 'core/providers/theme_provider.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/providers/auth_provider.dart';
import 'features/onboarding/providers/onboarding_provider.dart';

/// Root widget. Resolves the effective brightness, applies it to [AppColors]
/// and keys [MaterialApp.router] on brightness + locale.
///
/// The key forces a full remount on theme or locale change. That is cheaper
/// than threading `Theme.of(context)` through every call site; the GoRouter
/// location survives, but scroll and form state on the visible screen do not.
class EduPlannerApp extends ConsumerWidget {
  const EduPlannerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeProvider);
    final locale = ref.watch(localeProvider);
    final resolvedBrightness = switch (themeMode) {
      ThemeMode.light => Brightness.light,
      ThemeMode.dark => Brightness.dark,
      ThemeMode.system => MediaQuery.platformBrightnessOf(context),
    };
    AppColors.applyBrightness(resolvedBrightness);

    // Material widgets only know the primary language subtag; AppStrings still
    // gets the full code (e.g. 'zh_TW') to pick its JSON file.
    final flutterLocale = Locale(locale.split('_').first);

    // Paint a splash over the router until auth/onboarding are known, so Home
    // never flashes or fires unauthenticated AI calls. The router itself must
    // exist from the first frame: swapping in a plain MaterialApp resets the
    // web URL and loses deep links such as /login/reset?oobCode=...
    final authState = ref.watch(authStateProvider);
    final onboardingState = ref.watch(onboardingProvider);
    final booting = (authState.isLoading && !authState.hasValue) ||
        (onboardingState.isLoading && !onboardingState.hasValue);
    final router = ref.watch(routerProvider);

    return ToastificationWrapper(
      child: MaterialApp.router(
        key: ValueKey('${resolvedBrightness}_$locale'),
        title: 'EduPlanner AI',
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: themeMode,
        routerConfig: router,
        builder: (context, child) => booting ? const _SplashScreen() : child!,
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

/// Shown while auth/onboarding state is still loading.
class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Image.asset('assets/images/app_icon.png', width: 72, height: 72),
            ),
            const SizedBox(height: 24),
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2.5),
            ),
          ],
        ),
      ),
    );
  }
}
