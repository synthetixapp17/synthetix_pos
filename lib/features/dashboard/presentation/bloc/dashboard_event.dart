part of 'dashboard_bloc.dart';

abstract class DashboardEvent extends Equatable {
  const DashboardEvent();

  @override
  List<Object?> get props => [];
}

class LoadDashboardEvent extends DashboardEvent {
  final int? threshold;
  const LoadDashboardEvent({this.threshold});

  @override
  List<Object?> get props => [threshold];
}

class UpdateLowStockThresholdEvent extends DashboardEvent {
  final int threshold;
  const UpdateLowStockThresholdEvent(this.threshold);

  @override
  List<Object?> get props => [threshold];
}
