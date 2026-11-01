import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/usecase/usecase.dart';
import '../../domain/entities/customer.dart';
import '../../domain/usecases/customer_usecases.dart';

part 'customer_event.dart';
part 'customer_state.dart';

class CustomerBloc extends Bloc<CustomerEvent, CustomerState> {
  final GetCustomersUseCase getCustomersUseCase;
  final SaveCustomerUseCase saveCustomerUseCase;
  final DeleteCustomerUseCase deleteCustomerUseCase;

  CustomerBloc({
    required this.getCustomersUseCase,
    required this.saveCustomerUseCase,
    required this.deleteCustomerUseCase,
  }) : super(const CustomerState()) {
    on<LoadCustomersEvent>(_onLoad);
    on<SaveCustomerEvent>(_onSave);
    on<DeleteCustomerEvent>(_onDelete);
  }

  Future<void> _onLoad(
    LoadCustomersEvent event,
    Emitter<CustomerState> emit,
  ) async {
    emit(state.copyWith(status: CustomerStatus.loading, clearMessage: true));
    final result = await getCustomersUseCase(NoParams());
    result.fold(
      (failure) => emit(state.copyWith(
        status: CustomerStatus.failure,
        message: failure.message,
      )),
      (customers) => emit(state.copyWith(
        status: CustomerStatus.loaded,
        customers: customers,
      )),
    );
  }

  Future<void> _onSave(
    SaveCustomerEvent event,
    Emitter<CustomerState> emit,
  ) async {
    final customer = event.customer ??
        Customer(
          id: const Uuid().v4(),
          name: event.name.trim(),
          phone: event.phone.trim(),
          email: event.email.trim(),
          address: event.address.trim(),
          identityNumber: event.identityNumber.trim(),
        );
    final result = await saveCustomerUseCase(customer);
    await result.match(
      (failure) async => emit(state.copyWith(
        status: CustomerStatus.failure,
        message: failure.message,
      )),
      (_) async {
        final refreshed = await getCustomersUseCase(NoParams());
        refreshed.fold(
          (failure) => emit(state.copyWith(
            status: CustomerStatus.failure,
            message: failure.message,
          )),
          (customers) => emit(state.copyWith(
            status: CustomerStatus.saved,
            customers: customers,
            savedCustomer: customer,
            message: 'Cliente guardado correctamente.',
          )),
        );
      },
    );
  }

  Future<void> _onDelete(
    DeleteCustomerEvent event,
    Emitter<CustomerState> emit,
  ) async {
    final result = await deleteCustomerUseCase(event.id);
    result.fold(
      (failure) => emit(state.copyWith(
        status: CustomerStatus.failure,
        message: failure.message,
      )),
      (_) => add(const LoadCustomersEvent()),
    );
  }
}
