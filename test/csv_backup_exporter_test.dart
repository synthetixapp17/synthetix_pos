import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:billing_app/core/data/hive_database.dart';
import 'package:billing_app/core/data/models/app_settings.dart';
import 'package:billing_app/features/customer/data/models/customer_model.dart';
import 'package:billing_app/features/credit/domain/entities/credit_record.dart';
import 'package:billing_app/features/product/data/models/product_model.dart';
import 'package:billing_app/features/product/domain/entities/product.dart';
import 'package:billing_app/features/reports/data/models/sale_model.dart';
import 'package:billing_app/features/reports/domain/entities/sale_record.dart';
import 'package:billing_app/features/settings/data/csv_backup_exporter.dart';
import 'package:billing_app/features/settings/data/csv_backup_importer.dart';
import 'package:billing_app/features/shop/data/models/shop_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory directory;

  setUpAll(() {
    Hive.registerAdapter(ProductModelAdapter());
    Hive.registerAdapter(ShopModelAdapter());
    Hive.registerAdapter(CustomerModelAdapter());
    Hive.registerAdapter(SaleModelAdapter());
    Hive.registerAdapter(CurrencyConfigAdapter());
    Hive.registerAdapter(AppSettingsAdapter());
  });

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('csv-backup-test-');
    Hive.init(directory.path);
    await Hive.openBox<ProductModel>(HiveDatabase.productBoxName);
    await Hive.openBox<ShopModel>(HiveDatabase.shopBoxName);
    await Hive.openBox<CustomerModel>(HiveDatabase.customerBoxName);
    await Hive.openBox<SaleModel>(HiveDatabase.salesBoxName);
    await Hive.openBox<String>(HiveDatabase.creditBoxName);
    await Hive.openBox(HiveDatabase.settingsBoxName);
  });

  tearDown(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  test(
    'exports all backup data, including saved and product categories',
    () async {
      const categoryIcon = 0xe3af;
      await HiveDatabase.settingsBox.put(
        'product_categories',
        jsonEncode([
          {'name': 'Servicios', 'icon': categoryIcon},
        ]),
      );
      await HiveDatabase.settingsBox.putAll({
        'currency_code': 'USD',
        'low_stock_threshold': 12,
        'theme_mode': 'light',
        'primary_color': 0xFF1565C0,
        'printer_mac': '00:11:22:33:44:55',
        'app_settings': AppSettings(
          currencies: const [
            CurrencyConfig(code: 'USD', symbol: r'$', isBase: true, rate: 1),
            CurrencyConfig(code: 'VES', symbol: 'Bs.', isBase: false, rate: 40),
          ],
        ),
        'quotation_history': jsonEncode([
          {'id': 'quotation-1', 'title': 'Cotización de prueba'},
        ]),
      });
      await HiveDatabase.productBox.put(
        'product-1',
        ProductModel.fromEntity(
          Product(
          id: 'product-1',
          name: 'Café, "Especial"',
          barcode: '123',
          price: 25,
          stock: 4,
          description: 'Molido\nartesanal',
          category: 'Bebidas',
          unitLabel: 'kg',
          imageData: 'aW1hZ2U=',
          variants: const [
            ProductVariant(
              id: 'coffee-500g',
              attributes: {'Peso': '500 g'},
              price: 25,
              stock: 2.5,
              unitLabel: 'kg',
            ),
          ],
          ),
        ),
      );
      await HiveDatabase.shopBox.put(
        'shop_details',
        const ShopModel(
          name: 'Mi tienda',
          addressLine1: 'Calle 1',
          addressLine2: '',
          phoneNumber: '555123',
          rif: 'J-12345678-9',
          upiId: '',
          footerText: 'Gracias',
          logoData: 'bG9nbw==',
        ),
      );
      await HiveDatabase.salesBox.put(
        'sale-1',
        SaleModel.fromEntity(
          SaleRecord(
            id: 'sale-1',
            soldAt: DateTime(2026, 11, 1),
            total: 200,
            totalInCurrency: 200,
            exchangeRate: 40,
            customerId: 'customer-1',
            customerName: 'Ana',
            currencyCode: 'VES',
            paymentMethod: 'Efectivo',
            amountTendered: 220,
            changeAmount: 20,
            lines: const [
              SaleLine(
                productId: 'product-1',
                productName: 'Café, "Especial"',
                category: 'Bebidas',
                barcode: '123',
                quantity: 2,
                unitPrice: 100,
                variantId: 'coffee-500g',
                variantAttributes: {'Peso': '500 g'},
                unitLabel: 'kg',
              ),
            ],
          ),
        ),
      );
      await HiveDatabase.customerBox.put(
        'customer-1',
        CustomerModel(
          id: 'customer-1',
          name: 'Ana',
          phone: '555123',
          email: 'ana@example.com',
          address: 'Calle 1',
          identityNumber: 'ID-123',
        ),
      );
      final credit = CreditRecord(
        id: 'credit-1',
        createdAt: DateTime(2026, 11, 1),
        customerId: 'customer-1',
        customerName: 'Ana',
        customerIdentity: 'ID-123',
        total: 50,
        purchaseAmount: 45,
        initialPayment: 10,
        installmentCount: 4,
        daysBetweenPayments: 7,
        interestPercentage: 10,
        interestAmount: 5,
        currencyCode: 'USD',
        pdfBase64: 'cGRm',
        lines: const [
          CreditLineItem(
            productId: 'product-1',
            productName: 'Café',
            category: 'Bebidas',
            quantity: 2,
            unitPrice: 25,
          ),
        ],
        payments: [
          CreditPayment(
            paidAt: DateTime(2026, 11, 1),
            amount: 10,
            method: 'Tarjeta',
          ),
        ],
      );
      await HiveDatabase.creditBox.put('credit-1', jsonEncode(credit.toJson()));

      final backup = CsvBackupExporter().createBackup();
      final contents = {
        for (final file in backup)
          file.name.split('_').elementAt(1): utf8.decode(file.bytes),
      };

      expect(backup, hasLength(6));
      expect(contents['productos'], contains('Café'));
      expect(contents['productos'], contains('aW1hZ2U='));
      expect(contents['productos'], contains('coffee-500g'));
      expect(contents['productos'], contains('unidad'));
      expect(contents['ventas'], contains('variacion_id'));
      expect(contents['categorias'], contains('"Bebidas"'));
      expect(
        contents['categorias'],
        contains('"Servicios","$categoryIcon","0"'),
      );
      expect(contents['clientes'], contains('ID-123'));
      expect(contents['creditos'], contains('ID-123'));
      expect(contents['creditos'], contains('Tarjeta'));
      expect(contents['creditos'], contains('Café'));
      expect(contents['creditos'], contains('comprobante_pdf_base64'));
      expect(contents['ventas'], contains('Efectivo'));
      expect(contents['ventas'], contains('codigo_producto'));
      expect(contents['ventas'], contains('efectivo_recibido'));
      expect(contents['ventas'], contains('total_en_moneda'));
      expect(contents['ventas'], contains('tasa_cambio'));
      expect(contents['ventas'], contains('"200.0","200.0","40.0","VES"'));
      expect(contents['tienda'], contains('J-12345678-9'));
      expect(
        backup.every(
          (file) => file.bytes.take(3).toList().join(',') == '239,187,191',
        ),
        isTrue,
      );

      final package = CsvBackupExporter().createBackupPackage();
      expect(package.name, endsWith('.zip'));

      await HiveDatabase.productBox.put(
        'stale-product',
        const ProductModel(
          id: 'stale-product',
          name: 'Antiguo',
          barcode: '',
          price: 1,
          stock: 1,
        ),
      );
      await HiveDatabase.settingsBox.put('stale-setting', true);
      await HiveDatabase.settingsBox.put('currency_code', 'EUR');
      await HiveDatabase.settingsBox.put('theme_mode', 'dark');

      final importer = CsvBackupImporter();
      final plan = importer.parsePackage(package.bytes);
      expect(importer.summarize(plan).products, 1);
      expect(importer.summarize(plan).categories, 2);
      expect(importer.summarize(plan).sales, 1);
      expect(importer.summarize(plan).credits, 1);
      await importer.restore(plan);

      expect(HiveDatabase.productBox.containsKey('stale-product'), isFalse);
      expect(HiveDatabase.settingsBox.containsKey('stale-setting'), isFalse);
      expect(
        HiveDatabase.productBox.get('product-1')?.name,
        'Café, "Especial"',
      );
      expect(
        HiveDatabase.productBox.get('product-1')?.description,
        'Molido\nartesanal',
      );
      expect(
        HiveDatabase.productBox.get('product-1')?.variants.single.stock,
        2.5,
      );
      expect(HiveDatabase.productBox.get('product-1')?.unitLabel, 'kg');
      expect(
        HiveDatabase.salesBox
            .get('sale-1')
            ?.toEntity()
            .lines
            .single
            .variantAttributes,
        {'Peso': '500 g'},
      );
      expect(
        HiveDatabase.customerBox.get('customer-1')?.identityNumber,
        'ID-123',
      );
      expect(HiveDatabase.salesBox.get('sale-1')?.paymentMethod, 'Efectivo');
      expect(HiveDatabase.salesBox.get('sale-1')?.totalInCurrency, 200);
      expect(HiveDatabase.salesBox.get('sale-1')?.exchangeRate, 40);
      expect(HiveDatabase.salesBox.get('sale-1')?.currencyCode, 'VES');
      expect(HiveDatabase.salesBox.get('sale-1')?.amountTendered, 220);
      expect(HiveDatabase.salesBox.get('sale-1')?.changeAmount, 20);
      expect(HiveDatabase.creditBox.containsKey('credit-1'), isTrue);
      expect(HiveDatabase.shopBox.get('shop_details')?.logoData, 'bG9nbw==');
      expect(HiveDatabase.shopBox.get('shop_details')?.rif, 'J-12345678-9');
      expect(HiveDatabase.settingsBox.get('currency_code'), 'USD');
      expect(
        (HiveDatabase.settingsBox.get('app_settings') as AppSettings).currencies
            .singleWhere((currency) => currency.code == 'VES')
            .rate,
        40,
      );
      expect(HiveDatabase.settingsBox.get('low_stock_threshold'), 12);
      expect(HiveDatabase.settingsBox.get('theme_mode'), 'light');
      expect(HiveDatabase.settingsBox.get('primary_color'), 0xFF1565C0);
      expect(HiveDatabase.settingsBox.get('printer_mac'), '00:11:22:33:44:55');
      expect(
        HiveDatabase.settingsBox.get('quotation_history'),
        contains('quotation-1'),
      );
      expect(
        HiveDatabase.settingsBox.get('product_categories'),
        contains('Servicios'),
      );

      final configurationCsv = backup.singleWhere(
        (file) => file.name.startsWith('respaldo_tienda_configuracion_'),
      );
      await HiveDatabase.settingsBox.put('stale-setting', true);
      final configurationPlan = importer.parseCsvFile(
        'configuracion.csv',
        configurationCsv.bytes,
      );
      expect(configurationPlan.scope, CsvBackupScope.configuration);
      final legacyConfiguration = utf8.encode(
        utf8
            .decode(configurationCsv.bytes)
            .split(RegExp(r'\r?\n'))
            .where((line) => !RegExp(r'^"?RIF"?,').hasMatch(line))
            .join('\n'),
      );
      final legacyPlan = importer.parseCsvFile(
        'configuracion.csv',
        Uint8List.fromList(legacyConfiguration),
      );
      expect(legacyPlan.shop?.rif, '');
      await importer.restore(configurationPlan);
      expect(HiveDatabase.settingsBox.containsKey('stale-setting'), isFalse);
      expect(HiveDatabase.settingsBox.get('currency_code'), 'USD');
      expect(HiveDatabase.productBox.containsKey('product-1'), isTrue);
      expect(HiveDatabase.customerBox.containsKey('customer-1'), isTrue);
      expect(HiveDatabase.salesBox.containsKey('sale-1'), isTrue);
    },
  );

  test('restores a single CSV without replacing other data', () async {
    await HiveDatabase.productBox.put(
      'product-1',
      const ProductModel(
        id: 'product-1',
        name: 'Restaurado',
        barcode: '123',
        price: 25,
        stock: 4,
        unitLabel: 'g',
      ),
    );
    await HiveDatabase.customerBox.put(
      'customer-1',
      CustomerModel(
        id: 'customer-1',
        name: 'Ana',
        phone: '555123',
        email: 'ana@example.com',
        address: 'Calle 1',
      ),
    );
    await HiveDatabase.settingsBox.put('currency_code', 'USD');

    final productCsv = CsvBackupExporter().createBackup().singleWhere(
      (file) => file.name.startsWith('respaldo_productos_'),
    );
    await HiveDatabase.productBox.put(
      'stale-product',
      const ProductModel(
        id: 'stale-product',
        name: 'Antiguo',
        barcode: '',
        price: 1,
        stock: 1,
      ),
    );

    final importer = CsvBackupImporter();
    final plan = importer.parseCsvFile('inventario.csv', productCsv.bytes);
    expect(plan.scope, CsvBackupScope.products);
    expect(importer.summarize(plan).products, 1);
    await importer.restore(plan);

    expect(HiveDatabase.productBox.containsKey('stale-product'), isFalse);
    expect(HiveDatabase.productBox.get('product-1')?.name, 'Restaurado');
    expect(HiveDatabase.productBox.get('product-1')?.unitLabel, 'g');
    expect(HiveDatabase.customerBox.containsKey('customer-1'), isTrue);
    expect(HiveDatabase.settingsBox.get('currency_code'), 'USD');
  });

  test(
    'restores categories from their own CSV and preserves products',
    () async {
      await HiveDatabase.settingsBox.put(
        'product_categories',
        jsonEncode([
          {'name': 'Bebidas', 'icon': 100},
        ]),
      );
      await HiveDatabase.settingsBox.put('currency_code', 'USD');
      await HiveDatabase.productBox.put(
        'product-1',
        const ProductModel(
          id: 'product-1',
          name: 'Agua',
          barcode: '123',
          price: 2,
          stock: 5,
          category: 'Bebidas',
        ),
      );

      final categoryCsv = CsvBackupExporter().createBackup().singleWhere(
        (file) => file.name.startsWith('respaldo_categorias_'),
      );
      await HiveDatabase.settingsBox.put(
        'product_categories',
        jsonEncode([
          {'name': 'Antigua', 'icon': 101},
        ]),
      );

      final importer = CsvBackupImporter();
      final plan = importer.parseCsvFile('categorias.csv', categoryCsv.bytes);
      expect(plan.scope, CsvBackupScope.categories);
      expect(importer.summarize(plan).categories, 1);
      await importer.restore(plan);

      expect(
        HiveDatabase.settingsBox.get('product_categories'),
        contains('Bebidas'),
      );
      expect(
        HiveDatabase.settingsBox.get('product_categories'),
        isNot(contains('Antigua')),
      );
      expect(HiveDatabase.productBox.get('product-1')?.category, 'Bebidas');
      expect(HiveDatabase.settingsBox.get('currency_code'), 'USD');
    },
  );

  test('rejects invalid packages without changing local records', () async {
    await HiveDatabase.productBox.put(
      'existing-product',
      const ProductModel(
        id: 'existing-product',
        name: 'Conservar',
        barcode: '',
        price: 1,
        stock: 2,
      ),
    );

    expect(
      () => CsvBackupImporter().parsePackage(Uint8List.fromList([1, 2, 3])),
      throwsFormatException,
    );
    expect(HiveDatabase.productBox.containsKey('existing-product'), isTrue);
    expect(HiveDatabase.productBox.length, 1);
  });
}
