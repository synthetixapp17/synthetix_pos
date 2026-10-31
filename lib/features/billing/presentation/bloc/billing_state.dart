part of 'billing_bloc.dart';

class BillingState extends Equatable {
  final List<CartItem> cartItems;
  final String? error;
  final bool isPrinting;
  final bool printSuccess;
  final Customer? customer;
  final bool saleRecorded;
  final bool isSavingSale;
  final SaleRecord? completedSale;

  const BillingState({
    this.cartItems = const [],
    this.error,
    this.isPrinting = false,
    this.printSuccess = false,
    this.customer,
    this.saleRecorded = false,
    this.isSavingSale = false,
    this.completedSale,
  });

  double get totalAmount => cartItems.fold(0, (sum, item) => sum + item.total);

  BillingState copyWith({
    List<CartItem>? cartItems,
    String? error,
    bool clearError = false,
    bool? isPrinting,
    bool? printSuccess,
    Customer? customer,
    bool clearCustomer = false,
    bool? saleRecorded,
    bool? isSavingSale,
    SaleRecord? completedSale,
    bool clearCompletedSale = false,
  }) {
    return BillingState(
      cartItems: cartItems ?? this.cartItems,
      error: clearError ? null : (error ?? this.error),
      isPrinting: isPrinting ?? this.isPrinting,
      printSuccess: printSuccess ?? this.printSuccess,
      customer: clearCustomer ? null : customer ?? this.customer,
      saleRecorded: saleRecorded ?? this.saleRecorded,
      isSavingSale: isSavingSale ?? this.isSavingSale,
      completedSale: clearCompletedSale
          ? null
          : completedSale ?? this.completedSale,
    );
  }

  @override
  List<Object?> get props => [
    cartItems,
    error,
    isPrinting,
    printSuccess,
    customer,
    saleRecorded,
    isSavingSale,
    completedSale,
  ];
}
