part of 'reports_bloc.dart';

enum ReportsStatus { initial, loading, loaded, failure }

class ReportsState extends Equatable {
  final ReportsStatus status;
  final List<SaleRecord> sales;
  final DateTime? from;
  final DateTime? to;
  final String? message;

  const ReportsState({
    this.status = ReportsStatus.initial,
    this.sales = const [],
    this.from,
    this.to,
    this.message,
  });

  ReportsState copyWith({
    ReportsStatus? status,
    List<SaleRecord>? sales,
    DateTime? from,
    DateTime? to,
    String? message,
  }) =>
      ReportsState(
        status: status ?? this.status,
        sales: sales ?? this.sales,
        from: from ?? this.from,
        to: to ?? this.to,
        message: message,
      );

  @override
  List<Object?> get props => [status, sales, from, to, message];
}
