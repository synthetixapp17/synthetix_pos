import 'dart:io';

import 'package:billing_app/core/data/hive_database.dart';
import 'package:billing_app/features/product/data/models/product_model.dart';
import 'package:billing_app/features/reports/data/repositories/reports_repository_impl.dart';
import 'package:billing_app/features/reports/data/models/sale_model.dart';
import 'package:billing_app/features/reports/domain/entities/sale_record.dart';
import 'package:billing_app/features/settings/data/virtual_store_order_storage.dart';
import 'package:billing_app/features/settings/domain/entities/virtual_store_order.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory directory;

  setUpAll(() {
    Hive.registerAdapter(ProductModelAdapter());
    Hive.registerAdapter(SaleModelAdapter());
  });

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('store-order-test-');
    Hive.init(directory.path);
    await Hive.openBox<ProductModel>(HiveDatabase.productBoxName);
    await Hive.openBox<SaleModel>(HiveDatabase.salesBoxName);
    await Hive.openBox(HiveDatabase.settingsBoxName);
  });

  tearDown(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  test('delivery records a sale and deducts stock exactly once', () async {
    await HiveDatabase.productBox.put(
      'product-1',
      const ProductModel(
        id: 'product-1',
        name: 'Café',
        barcode: '123',
        price: 5,
        stock: 8,
      ),
    );
    final storage = VirtualStoreOrderStorage();
    await storage.add(
      VirtualStoreOrder(
        id: 'order-1',
        createdAt: DateTime(2026, 11, 1),
        customerName: 'Cliente',
        customerPhone: '',
        lines: const [
          VirtualStoreOrderLine(
            productId: 'product-1',
            productName: 'Café',
            quantity: 2,
            unitPriceUsd: 5,
            barcode: '123',
          ),
        ],
      ),
    );

    await storage.markDelivered('order-1');
    await storage.markDelivered('order-1');

    expect(HiveDatabase.productBox.get('product-1')?.stock, 6);
    expect(HiveDatabase.salesBox.length, 1);
    final sale = HiveDatabase.salesBox.values.single.toEntity();
    expect(sale.id, 'virtual-store-order-order-1');
    expect(sale.total, 10);
    expect(storage.load().single.isDelivered, isTrue);
  });

  test('does not deliver an order when inventory is insufficient', () async {
    await HiveDatabase.productBox.put(
      'product-1',
      const ProductModel(
        id: 'product-1',
        name: 'Café',
        barcode: '123',
        price: 5,
        stock: 1,
      ),
    );
    final storage = VirtualStoreOrderStorage();
    await storage.add(
      VirtualStoreOrder(
        id: 'order-2',
        createdAt: DateTime(2026, 11, 1),
        customerName: '',
        customerPhone: '',
        lines: const [
          VirtualStoreOrderLine(
            productId: 'product-1',
            productName: 'Café',
            quantity: 2,
            unitPriceUsd: 5,
          ),
        ],
      ),
    );

    await expectLater(storage.markDelivered('order-2'), throwsStateError);

    expect(HiveDatabase.productBox.get('product-1')?.stock, 1);
    expect(HiveDatabase.salesBox, isEmpty);
    expect(storage.load().single.isDelivered, isFalse);
  });

  test(
    'recovers delivery when the sale was saved before the order status',
    () async {
      await HiveDatabase.productBox.put(
        'product-1',
        const ProductModel(
          id: 'product-1',
          name: 'Café',
          barcode: '123',
          price: 5,
          stock: 5,
        ),
      );
      final storage = VirtualStoreOrderStorage();
      await storage.add(
        VirtualStoreOrder(
          id: 'recover',
          createdAt: DateTime(2026, 11, 1),
          customerName: '',
          customerPhone: '',
          lines: const [
            VirtualStoreOrderLine(
              productId: 'product-1',
              productName: 'Café',
              quantity: 1,
              unitPriceUsd: 5,
            ),
          ],
        ),
      );
      await ReportsRepositoryImpl().recordSale(
        SaleRecord(
          id: 'virtual-store-order-recover',
          soldAt: DateTime(2026, 11, 1),
          total: 5,
          lines: const [
            SaleLine(
              productId: 'product-1',
              productName: 'Café',
              quantity: 1,
              unitPrice: 5,
            ),
          ],
        ),
      );

      await storage.markDelivered('recover');

      expect(HiveDatabase.productBox.get('product-1')?.stock, 4);
      expect(storage.load().single.isDelivered, isTrue);
      expect(HiveDatabase.salesBox.length, 1);
    },
  );
}
