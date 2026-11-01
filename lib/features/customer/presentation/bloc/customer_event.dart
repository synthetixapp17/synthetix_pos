part of 'customer_bloc.dart';

abstract class CustomerEvent extends Equatable {
  const CustomerEvent();

  @override
  List<Object?> get props => [];
}

class LoadCustomersEvent extends CustomerEvent {
  const LoadCustomersEvent();
}

class SaveCustomerEvent extends CustomerEvent {
  final Customer? customer;
  final String name;
  final String phone;
  final String email;
  final String address;
  final String identityNumber;

  const SaveCustomerEvent({
    this.customer,
    this.name = '',
    this.phone = '',
    this.email = '',
    this.address = '',
    this.identityNumber = '',
  });

  @override
  List<Object?> get props =>
      [customer, name, phone, email, address, identityNumber];
}

class DeleteCustomerEvent extends CustomerEvent {
  final String id;
  const DeleteCustomerEvent(this.id);

  @override
  List<Object?> get props => [id];
}
