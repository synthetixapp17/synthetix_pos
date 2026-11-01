import 'dart:io';

import 'package:billing_app/core/data/hive_database.dart';
import 'package:billing_app/features/product/data/models/product_model.dart';
import 'package:billing_app/features/reports/data/models/sale_model.dart';
import 'package:billing_app/features/reports/data/repositories/reports_repository_impl.dart';
import 'package:billing_app/features/reports/domain/entities/sale_record.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory directory;

  setUpAll(() {
    Hive.registerAdapter(ProductModelAdapter());
    Hive.registerAdapter(SaleModelAdapter());
  });

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('sale-inventory-test-');
    Hive.init(directory.path);
    await Hive.openBox<ProductModel>(HiveDatabase.productBoxName);
    await Hive.openBox<SaleModel>(HiveDatabase.salesBoxName);
  });

  tearDown(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  test('deducts sold stock once, even when updating the saved sale', () async {
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
    final sale = SaleRecord(
      id: 'sale-1',
      soldAt: DateTime(2026, 11, 1),
      total: 15,
      paymentMethod: 'Tarjeta',
      lines: [
        SaleLine(
          productId: 'product-1',
          productName: 'Café',
          quantity: 3,
          unitPrice: 5,
        ),
      ],
    );
    final repository = ReportsRepositoryImpl();

    final result = await repository.recordSale(sale);
    expect(result.isRight(), isTrue);
    expect(HiveDatabase.productBox.get('product-1')?.stock, 5);
    expect(
      HiveDatabase.salesBox.get('sale-1')?.toEntity().paymentMethod,
      'Tarjeta',
    );

    await repository.recordSale(
      SaleRecord(
        id: 'sale-1',
        soldAt: DateTime(2026, 11, 1),
        total: 15,
        customerId: 'customer-1',
        customerName: 'Cliente',
        paymentMethod: 'Tarjeta',
        lines: [
          SaleLine(
            productId: 'product-1',
            productName: 'Café',
            quantity: 3,
            unitPrice: 5,
          ),
        ],
      ),
    );

    expect(HiveDatabase.productBox.get('product-1')?.stock, 5);
    expect(
      HiveDatabase.salesBox.get('sale-1')?.toEntity().paymentMethod,
      'Tarjeta',
    );
  });

  test('rejects a sale that exceeds available stock', () async {
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
    final sale = SaleRecord(
      id: 'sale-2',
      soldAt: DateTime(2026, 11, 1),
      total: 10,
      lines: [
        SaleLine(
          productId: 'product-1',
          productName: 'Café',
          quantity: 2,
          unitPrice: 5,
        ),
      ],
    );

    final result = await ReportsRepositoryImpl().recordSale(sale);

    expect(result.isLeft(), isTrue);
    expect(HiveDatabase.productBox.get('product-1')?.stock, 1);
    expect(HiveDatabase.salesBox.values, isEmpty);
  });
}
