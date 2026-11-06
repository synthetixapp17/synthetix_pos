import 'dart:io';

import 'package:billing_app/core/data/hive_database.dart';
import 'package:billing_app/core/data/models/app_settings.dart';
import 'package:billing_app/core/utils/app_currency.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory directory;

  setUpAll(() {
    Hive.registerAdapter(CurrencyConfigAdapter());
    Hive.registerAdapter(AppSettingsAdapter());
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

  test('persists configured rates and keeps the base rate fixed at one', () async {
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
      AppCurrency.configuredCurrencies.singleWhere((item) => item.isBase).rate,
      1,
    );
  });

  test('rejects invalid exchange rates', () async {
    await AppCurrency.ensureSettings();
    await AppCurrency.addCurrency('VES');

    await expectLater(
      AppCurrency.saveCurrencies([
        for (final currency in AppCurrency.configuredCurrencies)
          currency.copyWith(
            rate: currency.isBase ? 1 : double.infinity,
          ),
      ]),
      throwsArgumentError,
    );
  });
}
