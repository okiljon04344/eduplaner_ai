import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Manages the application's [ThemeMode], persisting preferences to
/// local storage and defaulting to the system theme.
///
/// UZ: Ilovaning [ThemeMode] holatini boshqaradi, sozlamalarni mahalliy
/// xotirada saqlaydi va sukut bo'yicha tizim mavzusiga moslashadi.
class ThemeNotifier extends Notifier<ThemeMode> {
  static const _key = 'theme_mode';

  @override
  ThemeMode build() {
    _loadFromPrefs();
    return ThemeMode.system;
  }

  // Fire-and-forget from build() — must not let a SharedPreferences failure
  // escape as an unhandled async error.
  // UZ: build() dan fire-and-forget tarzida chaqiriladi — SharedPreferences xatosi
  // ushlanmagan asinxron xato sifatida chiqib ketmasligi kerak.
  Future<void> _loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_key);
      if (saved == 'light') {
        state = ThemeMode.light;
      } else if (saved == 'dark') {
        state = ThemeMode.dark;
      } else {
        state = ThemeMode.system;
      }
    } catch (e) {
      debugPrint('Theme prefs load error: $e');
    }
  }

  Future<void> setTheme(ThemeMode mode) async {
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, mode.name);
  }
}

/// Riverpod provider exposing the current [ThemeMode] and theme controller.
///
/// UZ: Joriy [ThemeMode] va mavzu kontrollerini taqdim etuvchi Riverpod provayderi.
final themeProvider = NotifierProvider<ThemeNotifier, ThemeMode>(ThemeNotifier.new);
