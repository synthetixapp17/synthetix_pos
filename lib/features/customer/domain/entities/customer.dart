import 'package:equatable/equatable.dart';

class Customer extends Equatable {
  final String id;
  final String name;
  final String phone;
  final String email;
  final String address;

  const Customer({
    required this.id,
    required this.name,
    required this.phone,
    required this.email,
    required this.address,
  });

  @override
  List<Object?> get props => [id, name, phone, email, address];
}
