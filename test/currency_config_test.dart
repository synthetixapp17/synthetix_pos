import 'dart:io';

import 'package:billing_app/core/data/hive_database.dart';
import 'package:billing_app/core/data/models/app_settings.dart';
import 'package:billing_app/core/utils/app_currency.dart';
import 'package:billing_app/features/product/data/models/product_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory directory;

  setUpAll(() {
    Hive.registerAdapter(CurrencyConfigAdapter());
    Hive.registerAdapter(AppSettingsAdapter());
    Hive.registerAdapter(ProductModelAdapter());
  });

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('currency-config-test-');
    Hive.init(directory.path);
    await Hive.openBox(HiveDatabase.settingsBoxName);
  });

  tearDown(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  test(
    'persists configured rates and keeps the base rate fixed at one',
    () async {
      await AppCurrency.ensureSettings();
      await AppCurrency.addCurrency('VES');
      await AppCurrency.saveCurrencies([
        for (final currency in AppCurrency.configuredCurrencies)
          currency.copyWith(rate: currency.code == 'VES' ? 40 : currency.rate),
      ]);

      expect(AppCurrency.rateFor('USD'), 1);
      expect(AppCurrency.rateFor('VES'), 40);

      await Hive.close();
      Hive.init(directory.path);
      await Hive.openBox(HiveDatabase.settingsBoxName);

      expect(AppCurrency.rateFor('VES'), 40);
      expect(
        AppCurrency.configuredCurrencies
            .singleWhere((item) => item.isBase)
            .rate,
        1,
      );
    },
  );

  test('rejects invalid exchange rates', () async {
    await AppCurrency.ensureSettings();
    await AppCurrency.addCurrency('VES');

    await expectLater(
      AppCurrency.saveCurrencies([
        for (final currency in AppCurrency.configuredCurrencies)
          currency.copyWith(rate: currency.isBase ? 1 : double.infinity),
      ]),
      throwsArgumentError,
    );
  });

  test('normalizes saved currency rates against USD', () async {
    await HiveDatabase.settingsBox.put(
      'app_settings',
      AppSettings(
        currencies: [
          const CurrencyConfig(
            code: 'USD',
            symbol: r'$',
            isBase: false,
            rate: 0.02,
          ),
          const CurrencyConfig(
            code: 'VES',
            symbol: 'Bs.',
            isBase: true,
            rate: 2,
          ),
        ],
      ),
    );

    await AppCurrency.ensureSettings();

    expect(AppCurrency.rateFor('USD'), 1);
    expect(AppCurrency.rateFor('VES'), 100);
    expect(AppCurrency.baseCurrency.code, 'USD');
  });

  test(
    'converts existing catalog prices to USD when USD becomes the base',
    () async {
      await Hive.openBox<ProductModel>(HiveDatabase.productBoxName);
      await HiveDatabase.productBox.put(
        'legacy-ves',
        const ProductModel(
          id: 'legacy-ves',
          name: 'Producto',
          barcode: 'legacy-ves',
          price: 4000,
          stock: 1,
          currencyCode: 'VES',
        ),
      );
      await HiveDatabase.settingsBox.put(
        'app_settings',
        AppSettings(
          currencies: [
            const CurrencyConfig(
              code: 'USD',
              symbol: r'$',
              isBase: false,
              rate: 0.025,
            ),
            const CurrencyConfig(
              code: 'VES',
              symbol: 'Bs.',
              isBase: true,
              rate: 1,
            ),
          ],
        ),
      );

      await AppCurrency.ensureSettings();

      final product = HiveDatabase.productBox.get('legacy-ves')!;
      expect(product.price, 100);
      expect(product.currencyCode, 'USD');
      expect(AppCurrency.rateFor('VES'), 40);
    },
  );

  test('formats selected currency with a USD reference', () async {
    await AppCurrency.ensureSettings();
    await AppCurrency.addCurrency('VES');
    await AppCurrency.saveCurrencies([
      for (final currency in AppCurrency.configuredCurrencies)
        currency.copyWith(rate: currency.code == 'VES' ? 40 : currency.rate),
    ]);

    final formatted = AppCurrency.formatWithUsdReference(
      4000,
      code: 'VES',
      exchangeRate: 40,
    );

    expect(formatted, contains('Bs.'));
    expect(formatted, contains('Ref. \$ 100,00'));
  });
}
