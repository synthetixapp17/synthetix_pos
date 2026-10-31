import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../domain/entities/sale_record.dart';
import '../../domain/usecases/reports_usecases.dart';

part 'reports_event.dart';
part 'reports_state.dart';

class ReportsBloc extends Bloc<ReportsEvent, ReportsState> {
  final GetSalesReportUseCase getSalesReportUseCase;

  ReportsBloc({required this.getSalesReportUseCase})
      : super(const ReportsState()) {
    on<LoadReportsEvent>(_onLoad);
  }

  Future<void> _onLoad(
    LoadReportsEvent event,
    Emitter<ReportsState> emit,
  ) async {
    emit(state.copyWith(
      status: ReportsStatus.loading,
      from: event.from,
      to: event.to,
      message: null,
    ));
    final result = await getSalesReportUseCase(
      SalesRange(from: event.from, to: event.to),
    );
    result.fold(
      (failure) => emit(state.copyWith(
        status: ReportsStatus.failure,
        message: failure.message,
      )),
      (sales) => emit(state.copyWith(
        status: ReportsStatus.loaded,
        sales: sales,
      )),
    );
  }
}
