import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeManager {
  static const String _themeKey = 'theme_mode';
  static ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.dark);

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    themeNotifier.value = ThemeMode.values[prefs.getInt(_themeKey) ?? 1];
  }

  static Future<void> toggleTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final newIndex = themeNotifier.value.index == 0 ? 1 : 0;
    themeNotifier.value = ThemeMode.values[newIndex];
    await prefs.setInt(_themeKey, newIndex);
  }

  static ThemeData get lightTheme => ThemeData(useMaterial3: true, brightness: Brightness.light, colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple));
  static ThemeData get darkTheme => ThemeData(useMaterial3: true, brightness: Brightness.dark, colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple, brightness: Brightness.dark));
}
