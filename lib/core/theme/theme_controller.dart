import 'package:flutter/material.dart';

import '../data/hive_database.dart';

class AppThemeController {
  static const _primaryColorVersionKey = 'primary_color_theme_version';
  static const _primaryColorVersion = 1;
  static const _defaultPrimaryColor = Color(0xFF111111);

  static final ValueNotifier<ThemeMode> mode = ValueNotifier(ThemeMode.system);
  static final ValueNotifier<Color> primaryColor = ValueNotifier(
    _defaultPrimaryColor,
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

  static Future<void> loadSavedMode() async {
    final saved = HiveDatabase.settingsBox.get('theme_mode') as String?;
    mode.value = switch (saved) {
      'dark' => ThemeMode.dark,
      'light' => ThemeMode.light,
      _ => ThemeMode.system,
    };
    final colorVersion =
        HiveDatabase.settingsBox.get(_primaryColorVersionKey, defaultValue: 0)
            as int;
    if (colorVersion < _primaryColorVersion) {
      primaryColor.value = _defaultPrimaryColor;
      await HiveDatabase.settingsBox.put(
        'primary_color',
        _defaultPrimaryColor.toARGB32(),
      );
      await HiveDatabase.settingsBox.put(
        _primaryColorVersionKey,
        _primaryColorVersion,
      );
      return;
    }

    final savedColor = HiveDatabase.settingsBox.get('primary_color') as int?;
    if (savedColor != null) primaryColor.value = Color(savedColor);
  }

  static Future<void> toggle() async {
    final brightness = mode.value == ThemeMode.system
        ? WidgetsBinding.instance.platformDispatcher.platformBrightness
        : mode.value == ThemeMode.dark
        ? Brightness.dark
        : Brightness.light;
    await setMode(
      brightness == Brightness.dark ? ThemeMode.light : ThemeMode.dark,
    );
  }

  static Future<void> setMode(ThemeMode value) async {
    mode.value = value;
    await HiveDatabase.settingsBox.put('theme_mode', switch (value) {
      ThemeMode.dark => 'dark',
      ThemeMode.light => 'light',
      ThemeMode.system => 'system',
    });
  }

  static Future<void> setPrimaryColor(Color color) async {
    primaryColor.value = color;
    await HiveDatabase.settingsBox.putAll({
      'primary_color': color.toARGB32(),
      _primaryColorVersionKey: _primaryColorVersion,
    });
  }
}
