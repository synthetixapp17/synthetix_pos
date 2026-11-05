part of 'billing_bloc.dart';

abstract class BillingEvent extends Equatable {
  const BillingEvent();
  @override
  List<Object?> get props => [];
}

class ScanBarcodeEvent extends BillingEvent {
  final String barcode;
  const ScanBarcodeEvent(this.barcode);
  @override
  List<Object> get props => [barcode];
}

class AddProductToCartEvent extends BillingEvent {
  final Product product;
  const AddProductToCartEvent(this.product);
  @override
  List<Object> get props => [product];
}

class RemoveProductFromCartEvent extends BillingEvent {
  final String productId;
  const RemoveProductFromCartEvent(this.productId);
  @override
  List<Object> get props => [productId];
}

class UpdateQuantityEvent extends BillingEvent {
  final String productId;
  final int quantity;
  const UpdateQuantityEvent(this.productId, this.quantity);
  @override
  List<Object> get props => [productId, quantity];
}

class ClearCartEvent extends BillingEvent {}

class SelectCustomerEvent extends BillingEvent {
  final Customer? customer;
  const SelectCustomerEvent(this.customer);
  @override
  List<Object?> get props => [customer];
}

class CompleteSaleEvent extends BillingEvent {
  final String paymentMethod;
  final double amountTendered;
  final bool isCreditSale;

  const CompleteSaleEvent({
    this.paymentMethod = 'Efectivo',
    this.amountTendered = 0,
    this.isCreditSale = false,
  });

  @override
  List<Object> get props => [paymentMethod, amountTendered, isCreditSale];
}

class UpdateSaleCustomerEvent extends BillingEvent {
  final Customer customer;

  const UpdateSaleCustomerEvent(this.customer);

  @override
  List<Object> get props => [customer];
}

class PrintReceiptEvent extends BillingEvent {
  final String shopName;
  final String address1;
  final String address2;
  final String phone;
  final String? customerName;
  final String? logoData;
  final String footer;
  final String currencyCode;
  final String paymentMethod;
  final double amountTendered;
  final double changeAmount;
  final bool showAddress;
  final bool showPhone;
  final bool showDate;
  final bool showBarcode;
  final bool showUnitPrices;

  const PrintReceiptEvent({
    required this.shopName,
    required this.address1,
    required this.address2,
    required this.phone,
    required this.footer,
    this.customerName,
    this.logoData,
    this.currencyCode = 'USD',
    this.paymentMethod = 'Efectivo',
    this.amountTendered = 0,
    this.changeAmount = 0,
    this.showAddress = true,
    this.showPhone = true,
    this.showDate = true,
    this.showBarcode = false,
    this.showUnitPrices = true,
  });

  @override
  List<Object?> get props => [
    shopName,
    address1,
    address2,
    phone,
    customerName,
    logoData,
    footer,
    currencyCode,
    paymentMethod,
    amountTendered,
    changeAmount,
    showAddress,
    showPhone,
    showDate,
    showBarcode,
    showUnitPrices,
  ];
}
