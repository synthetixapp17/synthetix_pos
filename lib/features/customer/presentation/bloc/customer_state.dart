part of 'customer_bloc.dart';

enum CustomerStatus { initial, loading, loaded, saved, failure }

class CustomerState extends Equatable {
  final CustomerStatus status;
  final List<Customer> customers;
  final Customer? savedCustomer;
  final String? message;

  const CustomerState({
    this.status = CustomerStatus.initial,
    this.customers = const [],
    this.savedCustomer,
    this.message,
  });

  CustomerState copyWith({
    CustomerStatus? status,
    List<Customer>? customers,
    Customer? savedCustomer,
    String? message,
    bool clearMessage = false,
  }) =>
      CustomerState(
        status: status ?? this.status,
        customers: customers ?? this.customers,
        savedCustomer: savedCustomer,
        message: clearMessage ? null : message ?? this.message,
      );

  @override
  List<Object?> get props => [status, customers, savedCustomer, message];
}
