import 'package:equatable/equatable.dart';
import 'package:fpdart/fpdart.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/usecase/usecase.dart';
import '../entities/sale_record.dart';
import '../repositories/reports_repository.dart';

class SalesRange extends Equatable {
  final DateTime from;
  final DateTime to;

  const SalesRange({required this.from, required this.to});

  @override
  List<Object?> get props => [from, to];
}

class GetSalesReportUseCase
    implements UseCase<List<SaleRecord>, SalesRange> {
  final ReportsRepository repository;
  GetSalesReportUseCase(this.repository);

  @override
  Future<Either<Failure, List<SaleRecord>>> call(SalesRange params) =>
      repository.getSales(from: params.from, to: params.to);
}

class RecordSaleUseCase implements UseCase<void, SaleRecord> {
  final ReportsRepository repository;
  RecordSaleUseCase(this.repository);

  @override
  Future<Either<Failure, void>> call(SaleRecord params) =>
      repository.recordSale(params);
}
