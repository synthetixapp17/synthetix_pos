import 'package:flutter/material.dart';

import '../data/hive_database.dart';

class AppThemeController {
  static final ValueNotifier<ThemeMode> mode = ValueNotifier(ThemeMode.light);
  static final ValueNotifier<Color> primaryColor = ValueNotifier(
    const Color(0xFF111111),
  );

  static const List<Color> availableColors = [
    Color(0xFF111111),
    Color(0xFF263238),
    Color(0xFF455A64),
    Color(0xFF37474F),
    Color(0xFF0D47A1),
    Color(0xFF1565C0),
    Color(0xFF1976D2),
    Color(0xFF0277BD),
    Color(0xFF00838F),
    Color(0xFF00695C),
    Color(0xFF2E7D32),
    Color(0xFF558B2F),
    Color(0xFF827717),
    Color(0xFFF9A825),
    Color(0xFFEF6C00),
    Color(0xFFD84315),
    Color(0xFFC62828),
    Color(0xFFAD1457),
    Color(0xFF6A1B9A),
    Color(0xFF4527A0),
    Color(0xFF5E35B1),
    Color(0xFF795548),
    Color(0xFF8D6E63),
    Color(0xFF607D8B),
    Color(0xFF00897B),
  ];

  static void loadSavedMode() {
    final saved =
        HiveDatabase.settingsBox.get('theme_mode', defaultValue: 'light')
            as String;
    mode.value = saved == 'dark' ? ThemeMode.dark : ThemeMode.light;
    final savedColor = HiveDatabase.settingsBox.get('primary_color') as int?;
    if (savedColor != null) primaryColor.value = Color(savedColor);
  }

  static Future<void> toggle() async {
    final next = mode.value == ThemeMode.dark
        ? ThemeMode.light
        : ThemeMode.dark;
    mode.value = next;
    await HiveDatabase.settingsBox.put(
      'theme_mode',
      next == ThemeMode.dark ? 'dark' : 'light',
    );
  }

  static Future<void> setMode(ThemeMode value) async {
    mode.value = value;
    await HiveDatabase.settingsBox.put(
      'theme_mode',
      value == ThemeMode.dark ? 'dark' : 'light',
    );
  }

  static Future<void> setPrimaryColor(Color color) async {
    primaryColor.value = color;
    await HiveDatabase.settingsBox.put('primary_color', color.toARGB32());
  }
}
