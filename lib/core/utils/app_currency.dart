import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

import '../data/hive_database.dart';

class CurrencyOption {
  final String code;
  final String name;
  final String symbol;

  const CurrencyOption(this.code, this.name, this.symbol);
}

class AppCurrency {
  static final ValueNotifier<String> selectedCode = ValueNotifier('USD');

  static const options = [
    CurrencyOption('INR', 'Rupia india', '₹'),
    CurrencyOption('USD', 'Dólar estadounidense', r'$'),
    CurrencyOption('EUR', 'Euro', '€'),
    CurrencyOption('VES', 'Bolívar venezolano', 'Bs.'),
    CurrencyOption('COP', 'Peso colombiano', r'$'),
    CurrencyOption('MXN', 'Peso mexicano', r'$'),
    CurrencyOption('ARS', 'Peso argentino', r'$'),
    CurrencyOption('CLP', 'Peso chileno', r'$'),
    CurrencyOption('DOP', 'Peso dominicano', r'$'),
    CurrencyOption('PEN', 'Sol peruano', 'S/'),
    CurrencyOption('GBP', 'Libra esterlina', '£'),
    CurrencyOption('BRL', 'Real brasileño', r'R$'),
    CurrencyOption('CAD', 'Dólar canadiense', r'$'),
    CurrencyOption('AUD', 'Dólar australiano', r'$'),
    CurrencyOption('JPY', 'Yen japonés', '¥'),
    CurrencyOption('CHF', 'Franco suizo', 'CHF'),
  ];

  static String get currentCode =>
      HiveDatabase.settingsBox.get('currency_code', defaultValue: 'USD')
          as String;

  static String get currentSymbol => optionFor(currentCode).symbol;

  static void loadSavedCurrency() {
    selectedCode.value = currentCode;
  }

  static Future<void> setCurrentCode(String code) async {
    if (!options.any((option) => option.code == code)) {
      throw ArgumentError.value(code, 'code', 'Moneda no admitida');
    }
    await HiveDatabase.settingsBox.put('currency_code', code);
    selectedCode.value = code;
  }

  static CurrencyOption optionFor(String code) => options.firstWhere(
    (option) => option.code == code,
    orElse: () => options.first,
  );

  static String format(num amount, {String? code}) {
    final option = optionFor(code ?? currentCode);
    final formatted = NumberFormat('#,##0.00', 'es').format(amount);
    return '${option.symbol} $formatted';
  }

  static String formatConfigured(num amount) =>
      format(amount, code: selectedCode.value);
}

class AppCurrencyScope extends InheritedWidget {
  final String currencyCode;

  const AppCurrencyScope({
    required this.currencyCode,
    required super.child,
    super.key,
  });

  static String of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<AppCurrencyScope>()
          ?.currencyCode ??
      AppCurrency.currentCode;

  @override
  bool updateShouldNotify(AppCurrencyScope oldWidget) =>
      currencyCode != oldWidget.currencyCode;
}
