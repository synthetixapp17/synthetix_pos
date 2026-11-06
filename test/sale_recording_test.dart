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
  test('cart does not allow quantities above available stock', () async {
    final bloc = BillingBloc(
      getProductByBarcodeUseCase: GetProductByBarcodeUseCase(
        _FakeProductRepository(),
      ),
      recordSaleUseCase: RecordSaleUseCase(_FakeReportsRepository()),
      playCartAddSound: () async {},
    );
    addTearDown(bloc.close);

    const product = Product(
      id: 'limited-product',
      name: 'Producto limitado',
      barcode: '98765432',
      price: 4.5,
      stock: 1,
    );
    bloc.add(const AddProductToCartEvent(product));
    await bloc.stream.firstWhere((state) => state.cartItems.isNotEmpty);

    bloc.add(const AddProductToCartEvent(product));
    final rejected = await bloc.stream.firstWhere(
      (state) => state.error != null,
    );

    expect(rejected.cartItems.single.quantity, 1);
    expect(rejected.error, contains('Solo hay 1 unidad disponible'));
  });

  test('sale is persisted before any receipt or printer action', () async {
    final reportsRepository = _FakeReportsRepository();
    final bloc = BillingBloc(
      getProductByBarcodeUseCase: GetProductByBarcodeUseCase(
        _FakeProductRepository(),
      ),
      recordSaleUseCase: RecordSaleUseCase(reportsRepository),
      playCartAddSound: () async {},
    );
    addTearDown(bloc.close);

    const product = Product(
      id: 'product-1',
      name: 'Café',
      barcode: '12345678',
      price: 4.5,
      stock: 5,
      currencyCode: 'USD',
    );
    bloc.add(const AddProductToCartEvent(product));
    await bloc.stream.firstWhere((state) => state.cartItems.isNotEmpty);

    bloc.add(const CompleteSaleEvent(paymentMethod: 'Transferencia'));
    final completed = await bloc.stream.firstWhere(
      (state) => state.saleRecorded,
    );

    expect(reportsRepository.sales, hasLength(1));
    expect(completed.completedSale?.total, 4.5);
    expect(completed.completedSale?.paymentMethod, 'Transferencia');
    expect(completed.completedSale?.lines.single.barcode, '12345678');
    expect(completed.printSuccess, isFalse);
    expect(
      decodeSaleLines(completed.completedSale!.linesJson).single.barcode,
      '12345678',
    );
    final persistedSale = SaleModel.fromEntity(completed.completedSale!);
    final restoredSale = persistedSale.toEntity();
    expect(restoredSale.amountTendered, 0);
    expect(restoredSale.changeAmount, 0);

    bloc.add(CompleteSaleEvent());
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(reportsRepository.sales, hasLength(1));
  });

  test('cash sale stores the received amount and calculated change', () async {
    final reportsRepository = _FakeReportsRepository();
    final bloc = BillingBloc(
      getProductByBarcodeUseCase: GetProductByBarcodeUseCase(
        _FakeProductRepository(),
      ),
      recordSaleUseCase: RecordSaleUseCase(reportsRepository),
      playCartAddSound: () async {},
    );
    addTearDown(bloc.close);

    const product = Product(
      id: 'cash-product',
      name: 'Producto',
      barcode: '12345678',
      price: 4.5,
      stock: 5,
      currencyCode: 'USD',
    );
    bloc.add(const AddProductToCartEvent(product));
    await bloc.stream.firstWhere((state) => state.cartItems.isNotEmpty);

    bloc.add(
      const CompleteSaleEvent(paymentMethod: 'Efectivo', amountTendered: 10),
    );
    final completed = await bloc.stream.firstWhere(
      (state) => state.saleRecorded,
    );
    final sale = completed.completedSale!;

    expect(sale.amountTendered, 10);
    expect(sale.changeAmount, 5.5);
    final restoredSale = SaleModel.fromEntity(sale).toEntity();
    expect(restoredSale.amountTendered, 10);
    expect(restoredSale.changeAmount, 5.5);
  });

  test(
    'sale stores converted total, currency, rate, and line prices',
    () async {
      final reportsRepository = _FakeReportsRepository();
      final bloc = BillingBloc(
        getProductByBarcodeUseCase: GetProductByBarcodeUseCase(
          _FakeProductRepository(),
        ),
        recordSaleUseCase: RecordSaleUseCase(reportsRepository),
        playCartAddSound: () async {},
      );
      addTearDown(bloc.close);

      const product = Product(
        id: 'converted-product',
        name: 'Producto',
        barcode: '12345678',
        price: 4.5,
        stock: 5,
        currencyCode: 'USD',
      );
      bloc.add(const AddProductToCartEvent(product));
      await bloc.stream.firstWhere((state) => state.cartItems.isNotEmpty);

      bloc.add(
        const CompleteSaleEvent(
          paymentMethod: 'Efectivo',
          amountTendered: 200,
          currencyCode: 'VES',
          exchangeRate: 40,
        ),
      );
      final completed = await bloc.stream.firstWhere(
        (state) => state.saleRecorded,
      );
      final persistedSale = SaleModel.fromEntity(
        completed.completedSale!,
      ).toEntity();

      expect(persistedSale.currencyCode, 'VES');
      expect(persistedSale.total, 180);
      expect(persistedSale.totalInCurrency, 180);
      expect(persistedSale.exchangeRate, 40);
      expect(persistedSale.amountTendered, 200);
      expect(persistedSale.changeAmount, 20);
      expect(persistedSale.lines.single.unitPrice, 180);
    },
  );

  test('cash sale rejects a received amount below the total', () async {
    final reportsRepository = _FakeReportsRepository();
    final bloc = BillingBloc(
      getProductByBarcodeUseCase: GetProductByBarcodeUseCase(
        _FakeProductRepository(),
      ),
      recordSaleUseCase: RecordSaleUseCase(reportsRepository),
      playCartAddSound: () async {},
    );
    addTearDown(bloc.close);

    const product = Product(
      id: 'underpaid-product',
      name: 'Producto',
      barcode: '12345678',
      price: 4.5,
      stock: 5,
    );
    bloc.add(const AddProductToCartEvent(product));
    await bloc.stream.firstWhere((state) => state.cartItems.isNotEmpty);

    bloc.add(
      const CompleteSaleEvent(paymentMethod: 'Efectivo', amountTendered: 4),
    );
    final rejected = await bloc.stream.firstWhere(
      (state) => state.error != null,
    );

    expect(rejected.saleRecorded, isFalse);
    expect(reportsRepository.sales, isEmpty);
    expect(rejected.error, contains('igual o mayor'));
  });

  test('plays the cart sound for each successful product addition', () async {
    var soundCount = 0;
    final bloc = BillingBloc(
      getProductByBarcodeUseCase: GetProductByBarcodeUseCase(
        _FakeProductRepository(),
      ),
      playCartAddSound: () async {
        soundCount++;
      },
    );
    addTearDown(bloc.close);

    const product = Product(
      id: 'product-with-sound',
      name: 'Producto',
      barcode: '12345678',
      price: 4.5,
      stock: 3,
    );

    bloc.add(const AddProductToCartEvent(product));
    await bloc.stream.firstWhere(
      (state) => state.cartItems.single.quantity == 1,
    );
    bloc.add(const AddProductToCartEvent(product));
    await bloc.stream.firstWhere(
      (state) => state.cartItems.single.quantity == 2,
    );

    expect(soundCount, 2);
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
