import 'dart:io';

import 'package:billing_app/core/data/hive_database.dart';
import 'package:billing_app/features/dashboard/data/repositories/dashboard_repository_impl.dart';
import 'package:billing_app/features/product/data/models/product_model.dart';
import 'package:billing_app/features/reports/data/models/sale_model.dart';
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
    directory = await Directory.systemTemp.createTemp('dashboard-test-');
    Hive.init(directory.path);
    await Hive.openBox<ProductModel>(HiveDatabase.productBoxName);
    await Hive.openBox<SaleModel>(HiveDatabase.salesBoxName);
  });

  tearDown(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  test(
    'summary includes the five latest sales in reverse chronological order',
    () async {
      final now = DateTime.now();
      for (var index = 0; index < 7; index++) {
        final sale = SaleRecord(
          id: 'sale-$index',
          soldAt: now.subtract(Duration(minutes: index)),
          total: 10,
          lines: [
            SaleLine(
              productId: 'product-$index',
              productName: 'Producto $index',
              quantity: index + 1,
              unitPrice: 10,
            ),
          ],
        );
        await HiveDatabase.salesBox.put(sale.id, SaleModel.fromEntity(sale));
      }

      final result = await DashboardRepositoryImpl().getSummary(
        lowStockThreshold: 5,
      );

      final summary = result.getRight().toNullable();
      expect(summary, isNotNull);
      expect(summary!.recentSales.map((sale) => sale.id), [
        'sale-0',
        'sale-1',
        'sale-2',
        'sale-3',
        'sale-4',
      ]);
      expect(summary.unitsSoldToday, 28);
    },
  );
}
