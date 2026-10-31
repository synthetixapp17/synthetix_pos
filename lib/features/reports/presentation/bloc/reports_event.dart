part of 'reports_bloc.dart';

abstract class ReportsEvent extends Equatable {
  const ReportsEvent();

  @override
  List<Object?> get props => [];
}

class LoadReportsEvent extends ReportsEvent {
  final DateTime from;
  final DateTime to;

  const LoadReportsEvent({required this.from, required this.to});

  @override
  List<Object?> get props => [from, to];
}
