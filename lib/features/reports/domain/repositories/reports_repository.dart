import 'package:fpdart/fpdart.dart';

import '../../../../core/error/failure.dart';
import '../entities/sale_record.dart';

abstract class ReportsRepository {
  Future<Either<Failure, List<SaleRecord>>> getSales({
    required DateTime from,
    required DateTime to,
  });
  Future<Either<Failure, void>> recordSale(SaleRecord sale);
}
