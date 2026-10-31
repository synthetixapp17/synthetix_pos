import 'package:fpdart/fpdart.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/usecase/usecase.dart';
import '../entities/dashboard_summary.dart';
import '../repositories/dashboard_repository.dart';

class GetDashboardSummaryUseCase
    implements UseCase<DashboardSummary, int> {
  final DashboardRepository repository;
  GetDashboardSummaryUseCase(this.repository);

  @override
  Future<Either<Failure, DashboardSummary>> call(int threshold) =>
      repository.getSummary(lowStockThreshold: threshold);
}
