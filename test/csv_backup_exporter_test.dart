import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:billing_app/core/data/hive_database.dart';
import 'package:billing_app/features/customer/data/models/customer_model.dart';
import 'package:billing_app/features/credit/domain/entities/credit_record.dart';
import 'package:billing_app/features/product/data/models/product_model.dart';
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
        'quotation_history': jsonEncode([
          {'id': 'quotation-1', 'title': 'Cotización de prueba'},
        ]),
      });
      await HiveDatabase.productBox.put(
        'product-1',
        const ProductModel(
          id: 'product-1',
          name: 'Café, "Especial"',
          barcode: '123',
          price: 25,
          stock: 4,
          description: 'Molido\nartesanal',
          category: 'Bebidas',
          imageData: 'aW1hZ2U=',
        ),
      );
      await HiveDatabase.shopBox.put(
        'shop_details',
        const ShopModel(
          name: 'Mi tienda',
          addressLine1: 'Calle 1',
          addressLine2: '',
          phoneNumber: '555123',
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
            total: 50,
            customerId: 'customer-1',
            customerName: 'Ana',
            paymentMethod: 'Tarjeta',
            lines: const [
              SaleLine(
                productId: 'product-1',
                productName: 'Café, "Especial"',
                category: 'Bebidas',
                barcode: '123',
                quantity: 2,
                unitPrice: 25,
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
      expect(contents['ventas'], contains('Tarjeta'));
      expect(contents['ventas'], contains('codigo_producto'));
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
        HiveDatabase.customerBox.get('customer-1')?.identityNumber,
        'ID-123',
      );
      expect(HiveDatabase.salesBox.get('sale-1')?.paymentMethod, 'Tarjeta');
      expect(HiveDatabase.creditBox.containsKey('credit-1'), isTrue);
      expect(HiveDatabase.shopBox.get('shop_details')?.logoData, 'bG9nbw==');
      expect(HiveDatabase.settingsBox.get('currency_code'), 'USD');
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
    expect(HiveDatabase.customerBox.containsKey('customer-1'), isTrue);
    expect(HiveDatabase.settingsBox.get('currency_code'), 'USD');
  });

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
