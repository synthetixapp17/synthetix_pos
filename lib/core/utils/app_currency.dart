import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

import '../data/models/app_settings.dart';
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

  static String get currentSymbol => symbolFor(currentCode);

  static AppSettings get appSettings {
    final saved = HiveDatabase.settingsBox.get('app_settings');
    if (saved is AppSettings) return saved;
    final base = optionFor(currentCode);
    return AppSettings(
      currencies: [
        CurrencyConfig(
          code: base.code,
          symbol: base.symbol,
          isBase: true,
          rate: 1,
        ),
      ],
    );
  }

  static List<CurrencyConfig> get configuredCurrencies =>
      List.unmodifiable(appSettings.currencies);

  static CurrencyConfig get baseCurrency =>
      appSettings.currencies.singleWhere((currency) => currency.isBase);

  static double rateFor(String code) => appSettings.currencies
      .singleWhere((currency) => currency.code == code)
      .rate;

  static String symbolFor(String code) {
    for (final currency in appSettings.currencies) {
      if (currency.code == code) return currency.symbol;
    }
    return optionFor(code).symbol;
  }

  static Future<void> ensureSettings() async {
    if (HiveDatabase.settingsBox.get('app_settings') is AppSettings) return;
    await HiveDatabase.settingsBox.put('app_settings', appSettings);
  }

  static void loadSavedCurrency() {
    selectedCode.value = currentCode;
  }

  static Future<void> setCurrentCode(String code) async {
    if (!options.any((option) => option.code == code)) {
      throw ArgumentError.value(code, 'code', 'Moneda no admitida');
    }
    final currentSettings = appSettings;
    final matchingCurrency = currentSettings.currencies.where(
      (currency) => currency.code == code,
    );
    final existingBaseRate = matchingCurrency.isEmpty
        ? null
        : matchingCurrency.first.rate;
    final divisor = existingBaseRate ?? 1.0;
    final updatedCurrencies = <CurrencyConfig>[
      for (final currency in currentSettings.currencies)
        currency.copyWith(
          isBase: currency.code == code,
          rate: currency.code == code ? 1 : currency.rate / divisor,
        ),
    ];
    if (!updatedCurrencies.any((currency) => currency.code == code)) {
      updatedCurrencies.add(
        CurrencyConfig(
          code: code,
          symbol: optionFor(code).symbol,
          isBase: true,
          rate: 1,
        ),
      );
    }
    await HiveDatabase.settingsBox.put('currency_code', code);
    await saveCurrencies(updatedCurrencies);
    selectedCode.value = code;
  }

  static Future<void> saveCurrencies(List<CurrencyConfig> currencies) async {
    if (currencies.isEmpty ||
        currencies.where((currency) => currency.isBase).length != 1) {
      throw ArgumentError('Debe configurarse exactamente una moneda base.');
    }
    final codes = currencies.map((currency) => currency.code).toSet();
    if (codes.length != currencies.length) {
      throw ArgumentError('No se permiten monedas duplicadas.');
    }
    for (final currency in currencies) {
      if (!currency.rate.isFinite || currency.rate <= 0) {
        throw ArgumentError.value(
          currency.rate,
          'rate',
          'La tasa debe ser un número mayor que cero.',
        );
      }
      if (currency.isBase && currency.rate != 1) {
        throw ArgumentError('La tasa de la moneda base debe ser 1.0.');
      }
    }
    await HiveDatabase.settingsBox.put(
      'app_settings',
      AppSettings(currencies: List.unmodifiable(currencies)),
    );
  }

  static Future<void> addCurrency(String code) async {
    final option = options.firstWhere(
      (option) => option.code == code,
      orElse: () => throw ArgumentError.value(code, 'code'),
    );
    if (appSettings.currencies.any((currency) => currency.code == code)) {
      throw ArgumentError.value(code, 'code', 'La moneda ya está agregada.');
    }
    await saveCurrencies([
      ...appSettings.currencies,
      CurrencyConfig(
        code: option.code,
        symbol: option.symbol,
        isBase: false,
        rate: 1,
      ),
    ]);
  }

  static CurrencyOption optionFor(String code) => options.firstWhere(
    (option) => option.code == code,
    orElse: () => options.first,
  );

  static String format(num amount, {String? code}) {
    final formatted = NumberFormat('#,##0.00', 'es').format(amount);
    return '${symbolFor(code ?? currentCode)} $formatted';
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
