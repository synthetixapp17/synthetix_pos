import 'package:fpdart/fpdart.dart';

import '../../../../core/data/hive_database.dart';
import '../../../../core/error/failure.dart';
import '../../domain/entities/sale_record.dart';
import '../../domain/repositories/reports_repository.dart';
import '../models/sale_model.dart';

class ReportsRepositoryImpl implements ReportsRepository {
  @override
  Future<Either<Failure, List<SaleRecord>>> getSales({
    required DateTime from,
    required DateTime to,
  }) async {
    try {
      final sales = HiveDatabase.salesBox.values
          .where((sale) =>
              !sale.soldAt.isBefore(from) && !sale.soldAt.isAfter(to))
          .map((sale) => sale.toEntity())
          .toList()
        ..sort((a, b) => a.soldAt.compareTo(b.soldAt));
      return Right(sales);
    } catch (error) {
      return Left(CacheFailure(error.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> recordSale(SaleRecord sale) async {
    try {
      await HiveDatabase.salesBox.put(sale.id, SaleModel.fromEntity(sale));
      return const Right(null);
    } catch (error) {
      return Left(CacheFailure(error.toString()));
    }
  }
}
