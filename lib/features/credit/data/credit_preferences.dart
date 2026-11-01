import '../../../core/data/hive_database.dart';

class CreditPreferences {
  static const templateKey = 'credit_pdf_template';
  static const enabledKey = 'credit_enabled';
  static const primaryColorKey = 'credit_pdf_primary_color';
  static const accentColorKey = 'credit_pdf_accent_color';
  static const termsKey = 'credit_contract_terms';

  static String get template =>
      HiveDatabase.settingsBox.get(templateKey, defaultValue: 'Profesional')
          as String;

  static bool get enabled =>
      HiveDatabase.settingsBox.get(enabledKey, defaultValue: true) as bool;

  static int get primaryColor =>
      HiveDatabase.settingsBox.get(primaryColorKey, defaultValue: 0xFF174B3B)
          as int;

  static int get accentColor =>
      HiveDatabase.settingsBox.get(accentColorKey, defaultValue: 0xFF2E7D6F)
          as int;

  static String get terms =>
      HiveDatabase.settingsBox.get(
            termsKey,
            defaultValue:
                'El cliente se compromete a pagar las cuotas en las fechas '
                'indicadas en el cronograma. El abono inicial se descuenta del '
                'monto de la venta y el interés pactado se calcula sobre el saldo '
                'financiado. Las partes declaran haber leído y aceptado estas '
                'condiciones.',
          )
          as String;

  static Future<void> save({
    required bool enabled,
    required String template,
    required int primaryColor,
    required int accentColor,
    required String terms,
  }) async {
    await HiveDatabase.settingsBox.putAll({
      enabledKey: enabled,
      templateKey: template,
      primaryColorKey: primaryColor,
      accentColorKey: accentColor,
      termsKey: terms,
    });
  }
}
