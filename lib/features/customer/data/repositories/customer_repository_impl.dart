import 'package:fpdart/fpdart.dart';

import '../../../../core/data/hive_database.dart';
import '../../../../core/error/failure.dart';
import '../../domain/entities/customer.dart';
import '../../domain/repositories/customer_repository.dart';
import '../models/customer_model.dart';

class CustomerRepositoryImpl implements CustomerRepository {
  @override
  Future<Either<Failure, List<Customer>>> getCustomers() async {
    try {
      final customers = HiveDatabase.customerBox.values
          .map((customer) => customer.toEntity())
          .toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return Right(customers);
    } catch (error) {
      return Left(CacheFailure(error.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> saveCustomer(Customer customer) async {
    try {
      await HiveDatabase.customerBox.put(
        customer.id,
        CustomerModel.fromEntity(customer),
      );
      return const Right(null);
    } catch (error) {
      return Left(CacheFailure(error.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> deleteCustomer(String id) async {
    try {
      await HiveDatabase.customerBox.delete(id);
      return const Right(null);
    } catch (error) {
      return Left(CacheFailure(error.toString()));
    }
  }
}
