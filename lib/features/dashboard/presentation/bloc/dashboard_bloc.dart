import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/data/hive_database.dart';
import '../../domain/entities/dashboard_summary.dart';
import '../../domain/usecases/dashboard_usecases.dart';

part 'dashboard_event.dart';
part 'dashboard_state.dart';

class DashboardBloc extends Bloc<DashboardEvent, DashboardState> {
  final GetDashboardSummaryUseCase getDashboardSummaryUseCase;

  DashboardBloc({required this.getDashboardSummaryUseCase})
      : super(const DashboardState()) {
    on<LoadDashboardEvent>(_onLoad);
    on<UpdateLowStockThresholdEvent>(_onUpdateThreshold);
  }

  Future<void> _onLoad(
    LoadDashboardEvent event,
    Emitter<DashboardState> emit,
  ) async {
    emit(state.copyWith(status: DashboardStatus.loading, message: null));
    final threshold = event.threshold ??
        (HiveDatabase.settingsBox.get('low_stock_threshold', defaultValue: 5)
            as int);
    final result = await getDashboardSummaryUseCase(threshold);
    result.fold(
      (failure) => emit(state.copyWith(
        status: DashboardStatus.failure,
        message: failure.message,
      )),
      (summary) => emit(state.copyWith(
        status: DashboardStatus.loaded,
        summary: summary,
        threshold: threshold,
      )),
    );
  }

  Future<void> _onUpdateThreshold(
    UpdateLowStockThresholdEvent event,
    Emitter<DashboardState> emit,
  ) async {
    if (event.threshold < 1) {
      emit(state.copyWith(
        status: DashboardStatus.failure,
        message: 'El umbral debe ser mayor que cero.',
      ));
      return;
    }
    await HiveDatabase.settingsBox.put('low_stock_threshold', event.threshold);
    add(LoadDashboardEvent(threshold: event.threshold));
  }
}
