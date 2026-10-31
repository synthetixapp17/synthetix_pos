import 'package:fpdart/fpdart.dart';

import '../../../../core/data/hive_database.dart';
import '../../../../core/error/failure.dart';
import '../../../product/domain/entities/product.dart';
import '../../../reports/data/models/sale_model.dart';
import '../../domain/entities/dashboard_summary.dart';
import '../../domain/repositories/dashboard_repository.dart';

class DashboardRepositoryImpl implements DashboardRepository {
  @override
  Future<Either<Failure, DashboardSummary>> getSummary({
    required int lowStockThreshold,
  }) async {
    try {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final tomorrow = today.add(const Duration(days: 1));
      final sales = HiveDatabase.salesBox.values
          .where(
            (sale) =>
                !sale.soldAt.isBefore(today) && sale.soldAt.isBefore(tomorrow),
          )
          .toList();
      final amountsByDay = <String, double>{};
      final productQuantities = <String, int>{};
      final productNames = <String, String>{};

      for (final model in HiveDatabase.salesBox.values) {
        final sale = model.toEntity();
        final saleDay = DateTime(
          sale.soldAt.year,
          sale.soldAt.month,
          sale.soldAt.day,
        );
        if (!saleDay.isBefore(today.subtract(const Duration(days: 6))) &&
            !saleDay.isAfter(today)) {
          final key = '${saleDay.toIso8601String()}|${sale.currencyCode}';
          amountsByDay.update(
            key,
            (amount) => amount + sale.total,
            ifAbsent: () => sale.total,
          );
        }
      }
      for (final model in sales) {
        for (final line in decodeSaleLines(model.linesJson)) {
          productQuantities.update(
            line.productId,
            (quantity) => quantity + line.quantity,
            ifAbsent: () => line.quantity,
          );
          productNames[line.productId] = line.productName;
        }
      }

      final bestSellers =
          productQuantities.entries
              .map(
                (entry) => ProductSales(
                  name: productNames[entry.key] ?? 'Producto',
                  quantity: entry.value,
                ),
              )
              .toList()
            ..sort((a, b) => b.quantity.compareTo(a.quantity));

      final products =
          HiveDatabase.productBox.values
              .map(
                (model) => Product(
                  id: model.id,
                  name: model.name,
                  barcode: model.barcode,
                  price: model.price,
                  stock: model.stock,
                ),
              )
              .where((product) => product.stock < lowStockThreshold)
              .toList()
            ..sort((a, b) => a.stock.compareTo(b.stock));

      return Right(
        DashboardSummary(
          dailyTotal: sales.fold<double>(
            0,
            (total, sale) => total + sale.total,
          ),
          transactionCount: sales.length,
          bestSellers: bestSellers.take(5).toList(),
          lowStock: products,
          lastSevenDays: [
            for (var offset = 6; offset >= 0; offset--)
              for (final code in {
                ...amountsByDay.keys.map((key) => key.split('|').last),
                'USD',
              })
                DailySales(
                  date: today.subtract(Duration(days: offset)),
                  amount:
                      amountsByDay['${today.subtract(Duration(days: offset)).toIso8601String()}|$code'] ??
                      0,
                  currencyCode: code,
                ),
          ],
          lowStockThreshold: lowStockThreshold,
          dailyTotals: {
            for (final sale in sales)
              sale.currencyCode: sales
                  .where((item) => item.currencyCode == sale.currencyCode)
                  .fold<double>(0, (total, item) => total + item.total),
          },
        ),
      );
    } catch (error) {
      return Left(CacheFailure(error.toString()));
    }
  }
}
