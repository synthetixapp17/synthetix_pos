import 'package:fpdart/fpdart.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/usecase/usecase.dart';
import '../entities/customer.dart';
import '../repositories/customer_repository.dart';

class GetCustomersUseCase implements UseCase<List<Customer>, NoParams> {
  final CustomerRepository repository;
  GetCustomersUseCase(this.repository);

  @override
  Future<Either<Failure, List<Customer>>> call(NoParams params) =>
      repository.getCustomers();
}

class SaveCustomerUseCase implements UseCase<void, Customer> {
  final CustomerRepository repository;
  SaveCustomerUseCase(this.repository);

  @override
  Future<Either<Failure, void>> call(Customer params) =>
      repository.saveCustomer(params);
}

class DeleteCustomerUseCase implements UseCase<void, String> {
  final CustomerRepository repository;
  DeleteCustomerUseCase(this.repository);

  @override
  Future<Either<Failure, void>> call(String params) =>
      repository.deleteCustomer(params);
}
