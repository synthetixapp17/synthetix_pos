import 'package:flutter/widgets.dart';
import 'package:hive/hive.dart';
import 'package:intl/intl.dart';

import '../data/models/app_settings.dart';
import '../data/hive_database.dart';
import '../../features/product/data/models/product_model.dart';

class CurrencyOption {
  final String code;
  final String name;
  final String symbol;

  const CurrencyOption(this.code, this.name, this.symbol);
}

class AppCurrency {
  static const baseCode = 'USD';
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
    final base = optionFor(baseCode);
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

  static CurrencyConfig get baseCurrency => appSettings.currencies.firstWhere(
    (currency) => currency.code == baseCode,
    orElse: () => CurrencyConfig(
      code: baseCode,
      symbol: optionFor(baseCode).symbol,
      isBase: true,
      rate: 1,
    ),
  );

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
    final saved = HiveDatabase.settingsBox.get('app_settings');
    if (saved is! AppSettings) {
      final currencies = [...appSettings.currencies];
      final savedCode = currentCode;
      if (savedCode != baseCode &&
          options.any((option) => option.code == savedCode)) {
        final option = optionFor(savedCode);
        currencies.add(
          CurrencyConfig(
            code: option.code,
            symbol: option.symbol,
            isBase: false,
            rate: 1,
          ),
        );
      }
      await saveCurrencies(currencies);
      return;
    }

    final usd = saved.currencies.where((currency) => currency.code == baseCode);
    final usdRate = usd.isEmpty ? 1.0 : usd.first.rate;
    if (!usdRate.isFinite || usdRate <= 0) {
      throw StateError('La tasa existente de USD no es válida.');
    }
    final oldBase = saved.currencies.where((currency) => currency.isBase);
    final needsCatalogMigration =
        oldBase.isNotEmpty && oldBase.first.code != baseCode;
    if (needsCatalogMigration &&
        usd.isNotEmpty &&
        Hive.isBoxOpen(HiveDatabase.productBoxName)) {
      final products = HiveDatabase.productBox;
      final rates = {
        for (final currency in saved.currencies) currency.code: currency.rate,
      };
      final migratedProducts = <dynamic, ProductModel>{};
      for (final entry in products.toMap().entries) {
        final product = entry.value;
        final oldRate = rates[product.currencyCode];
        if (oldRate == null || !oldRate.isFinite || oldRate <= 0) continue;
        migratedProducts[entry.key] = product.copyWith(
          price: product.price * usdRate / oldRate,
          currencyCode: baseCode,
        );
      }
      if (migratedProducts.isNotEmpty) {
        await products.putAll(migratedProducts);
      }
    }

    final migrated = <CurrencyConfig>[
      for (final currency in saved.currencies)
        if (currency.code == baseCode)
          currency.copyWith(isBase: true, rate: 1)
        else
          currency.copyWith(isBase: false, rate: currency.rate / usdRate),
    ];
    if (usd.isEmpty) {
      migrated.insert(
        0,
        CurrencyConfig(
          code: baseCode,
          symbol: optionFor(baseCode).symbol,
          isBase: true,
          rate: 1,
        ),
      );
    }
    final savedCode = currentCode;
    if (!migrated.any((currency) => currency.code == savedCode) &&
        options.any((option) => option.code == savedCode)) {
      final option = optionFor(savedCode);
      migrated.add(
        CurrencyConfig(
          code: option.code,
          symbol: option.symbol,
          isBase: false,
          rate: 1,
        ),
      );
    }
    await saveCurrencies(migrated);
  }

  static void loadSavedCurrency() {
    selectedCode.value = currentCode;
  }

  static Future<void> setCurrentCode(String code) async {
    if (!options.any((option) => option.code == code)) {
      throw ArgumentError.value(code, 'code', 'Moneda no admitida');
    }
    if (!appSettings.currencies.any((currency) => currency.code == code)) {
      throw ArgumentError.value(
        code,
        'code',
        'Configura la moneda y su tasa antes de seleccionarla.',
      );
    }
    await HiveDatabase.settingsBox.put('currency_code', code);
    selectedCode.value = code;
  }

  static Future<void> saveCurrencies(List<CurrencyConfig> currencies) async {
    if (currencies.isEmpty ||
        currencies.where((currency) => currency.code == baseCode).length != 1 ||
        currencies.where((currency) => currency.isBase).length != 1 ||
        !currencies.any(
          (currency) =>
              currency.code == baseCode &&
              currency.isBase &&
              currency.rate == 1,
        )) {
      throw ArgumentError('USD debe ser la única moneda base con tasa 1.0.');
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

  static String formatReference(num amount, {String prefix = 'Ref.'}) =>
      '$prefix ${format(amount, code: baseCode)}';

  static String formatWithUsdReference(
    num amount, {
    required String code,
    required double exchangeRate,
  }) {
    if (!exchangeRate.isFinite || exchangeRate <= 0) {
      throw ArgumentError.value(exchangeRate, 'exchangeRate');
    }
    return '${format(amount, code: code)}\n'
        '${formatReference(amount / exchangeRate)}';
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
