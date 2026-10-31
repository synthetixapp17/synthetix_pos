part of 'dashboard_bloc.dart';

enum DashboardStatus { initial, loading, loaded, failure }

class DashboardState extends Equatable {
  final DashboardStatus status;
  final DashboardSummary? summary;
  final int threshold;
  final String? message;

  const DashboardState({
    this.status = DashboardStatus.initial,
    this.summary,
    this.threshold = 5,
    this.message,
  });

  DashboardState copyWith({
    DashboardStatus? status,
    DashboardSummary? summary,
    int? threshold,
    String? message,
  }) =>
      DashboardState(
        status: status ?? this.status,
        summary: summary ?? this.summary,
        threshold: threshold ?? this.threshold,
        message: message,
      );

  @override
  List<Object?> get props => [status, summary, threshold, message];
}
