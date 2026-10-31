import 'dart:convert';

import '../../../core/data/hive_database.dart';
import '../domain/entities/quotation.dart';

class QuotationPreferences {
  static const enabledKey = 'quotation_enabled';
  static const templateKey = 'quotation_template';
  static const primaryColorKey = 'quotation_primary_color';
  static const accentColorKey = 'quotation_accent_color';
  static const historyKey = 'quotation_history';

  static bool get enabled =>
      HiveDatabase.settingsBox.get(enabledKey, defaultValue: true) as bool;

  static String get template =>
      HiveDatabase.settingsBox.get(templateKey, defaultValue: 'Clásica')
          as String;

  static int get primaryColor =>
      HiveDatabase.settingsBox.get(primaryColorKey, defaultValue: 0xFF2E7D6F)
          as int;

  static int get accentColor =>
      HiveDatabase.settingsBox.get(accentColorKey, defaultValue: 0xFF00BFA5)
          as int;

  static List<QuotationRecord> get history {
    final stored = HiveDatabase.settingsBox.get(historyKey, defaultValue: '[]');
    if (stored is! String) {
      throw const FormatException('El historial de cotizaciones no es válido.');
    }
    final decoded = jsonDecode(stored);
    if (decoded is! List) {
      throw const FormatException('El historial de cotizaciones no es válido.');
    }
    return decoded
        .map((entry) => QuotationRecord.fromJson(entry as Map<String, dynamic>))
        .toList()
      ..sort((first, second) => second.createdAt.compareTo(first.createdAt));
  }

  static Future<void> save({
    required bool enabled,
    required String template,
    required int primaryColor,
    required int accentColor,
  }) async {
    await HiveDatabase.settingsBox.putAll({
      enabledKey: enabled,
      templateKey: template,
      primaryColorKey: primaryColor,
      accentColorKey: accentColor,
    });
  }

  static Future<void> addToHistory(QuotationRecord quotation) async {
    final entries = history.map((entry) => entry.toJson()).toList();
    entries.insert(0, quotation.toJson());
    await HiveDatabase.settingsBox.put(historyKey, jsonEncode(entries));
  }
}
