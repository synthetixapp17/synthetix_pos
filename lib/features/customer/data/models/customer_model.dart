import 'package:hive/hive.dart';

import '../../domain/entities/customer.dart';

part 'customer_model.g.dart';

@HiveType(typeId: 2)
class CustomerModel extends HiveObject {
  @HiveField(0)
  final String id;
  @HiveField(1)
  final String name;
  @HiveField(2)
  final String phone;
  @HiveField(3)
  final String email;
  @HiveField(4)
  final String address;

  CustomerModel({
    required this.id,
    required this.name,
    required this.phone,
    required this.email,
    required this.address,
  });

  factory CustomerModel.fromEntity(Customer customer) => CustomerModel(
        id: customer.id,
        name: customer.name,
        phone: customer.phone,
        email: customer.email,
        address: customer.address,
      );

  Customer toEntity() => Customer(
        id: id,
        name: name,
        phone: phone,
        email: email,
        address: address,
      );
}
