import 'dart:io';

import 'package:billing_app/core/data/hive_database.dart';
import 'package:billing_app/features/product/data/models/product_model.dart';
import 'package:billing_app/features/product/domain/entities/product.dart';
import 'package:billing_app/features/settings/data/virtual_store_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('store-catalog-rate-');
    Hive.init(directory.path);
    await Hive.openBox(HiveDatabase.settingsBoxName);
  });

  tearDown(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  test(
    'publishes the selected platform rate for USD reference display',
    () async {
      await HiveDatabase.settingsBox.put('multi_rate_calculator_rates', {
        'USDT': {'value': 50.25, 'updatedAt': '2026-11-01T10:00:00.000'},
      });
      const settings = VirtualStoreSettings(
        businessName: 'Tienda',
        showUsdReference: true,
        exchangeRateSource: 'USDT',
        logo: 'iVBORw0KGgo=',
        banner: 'iVBORw0KGgo=',
      );

      final catalog = VirtualStoreCatalogBuilder().build(settings, [
        ProductModel.fromEntity(
          const Product(
            id: 'coffee',
            name: 'Café',
            barcode: '123',
            price: 4,
            stock: 5,
          ),
        ),
      ]);

      final business = catalog['business'] as Map<String, Object?>;
      expect(business['vesPerUsd'], 50.25);
      expect(business['showUsdReference'], isTrue);
      expect(business['logo'], 'data:image/png;base64,iVBORw0KGgo=');
      expect(business['banner'], 'data:image/png;base64,iVBORw0KGgo=');
      final product = (catalog['products'] as List).single as Map;
      expect(product['currencyCode'], 'USD');
      expect(product['price'], 4);
    },
  );

  test('requires an available platform rate when references are enabled', () {
    expect(
      () => VirtualStoreCatalogBuilder().build(
        const VirtualStoreSettings(
          businessName: 'Tienda',
          showUsdReference: true,
        ),
        const [],
      ),
      throwsFormatException,
    );
  });
}
