import 'package:billing_app/core/error/failure.dart';
import 'package:billing_app/features/billing/presentation/bloc/billing_bloc.dart';
import 'package:billing_app/features/product/domain/entities/product.dart';
import 'package:billing_app/features/product/domain/repositories/product_repository.dart';
import 'package:billing_app/features/product/domain/usecases/product_usecases.dart';
import 'package:billing_app/features/reports/domain/entities/sale_record.dart';
import 'package:billing_app/features/reports/data/models/sale_model.dart';
import 'package:billing_app/features/reports/domain/repositories/reports_repository.dart';
import 'package:billing_app/features/reports/domain/usecases/reports_usecases.dart';
import 'package:fpdart/fpdart.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sale is persisted before any receipt or printer action', () async {
    final reportsRepository = _FakeReportsRepository();
    final bloc = BillingBloc(
      getProductByBarcodeUseCase: GetProductByBarcodeUseCase(
        _FakeProductRepository(),
      ),
      recordSaleUseCase: RecordSaleUseCase(reportsRepository),
    );
    addTearDown(bloc.close);

    const product = Product(
      id: 'product-1',
      name: 'Café',
      barcode: '12345678',
      price: 4.5,
      currencyCode: 'USD',
    );
    bloc.add(const AddProductToCartEvent(product));
    await bloc.stream.firstWhere((state) => state.cartItems.isNotEmpty);

    bloc.add(CompleteSaleEvent());
    final completed = await bloc.stream.firstWhere(
      (state) => state.saleRecorded,
    );

    expect(reportsRepository.sales, hasLength(1));
    expect(completed.completedSale?.total, 4.5);
    expect(completed.completedSale?.lines.single.barcode, '12345678');
    expect(completed.printSuccess, isFalse);
    expect(
      decodeSaleLines(completed.completedSale!.linesJson).single.barcode,
      '12345678',
    );

    bloc.add(CompleteSaleEvent());
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(reportsRepository.sales, hasLength(1));
  });
}

class _FakeProductRepository implements ProductRepository {
  @override
  Future<Either<Failure, Product>> getProductByBarcode(String barcode) async =>
      Left(CacheFailure('No encontrado'));

  @override
  Future<Either<Failure, List<Product>>> getProducts() async => const Right([]);

  @override
  Future<Either<Failure, void>> addProduct(Product product) async =>
      const Right(null);

  @override
  Future<Either<Failure, void>> updateProduct(Product product) async =>
      const Right(null);

  @override
  Future<Either<Failure, void>> deleteProduct(String id) async =>
      const Right(null);
}

class _FakeReportsRepository implements ReportsRepository {
  final List<SaleRecord> sales = [];

  @override
  Future<Either<Failure, List<SaleRecord>>> getSales({
    required DateTime from,
    required DateTime to,
  }) async => Right(sales);

  @override
  Future<Either<Failure, void>> recordSale(SaleRecord sale) async {
    sales.add(sale);
    return const Right(null);
  }
}
