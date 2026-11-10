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
  final double quantity;
  const AddProductToCartEvent(this.product, {this.quantity = 1});
  @override
  List<Object> get props => [product, quantity];
}

class RemoveProductFromCartEvent extends BillingEvent {
  final String productId;
  const RemoveProductFromCartEvent(this.productId);
  @override
  List<Object> get props => [productId];
}

class UpdateQuantityEvent extends BillingEvent {
  final String productId;
  final double quantity;
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
  final String? currencyCode;
  final double exchangeRate;

  const CompleteSaleEvent({
    this.paymentMethod = 'Efectivo',
    this.amountTendered = 0,
    this.isCreditSale = false,
    this.currencyCode,
    this.exchangeRate = 1,
  });

  @override
  List<Object?> get props => [
    paymentMethod,
    amountTendered,
    isCreditSale,
    currencyCode,
    exchangeRate,
  ];
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
  final String rif;
  final String? qrData;
  final String? customerName;
  final String? logoData;
  final String footer;
  final String currencyCode;
  final String paymentMethod;
  final double amountTendered;
  final double changeAmount;
  final double exchangeRate;
  final bool showAddress;
  final bool showPhone;
  final bool showRif;
  final bool showInvoiceQr;
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
    this.rif = '',
    this.qrData,
    this.currencyCode = 'USD',
    this.paymentMethod = 'Efectivo',
    this.amountTendered = 0,
    this.changeAmount = 0,
    this.exchangeRate = 1,
    this.showAddress = true,
    this.showPhone = true,
    this.showRif = true,
    this.showInvoiceQr = true,
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
    rif,
    qrData,
    customerName,
    logoData,
    footer,
    currencyCode,
    paymentMethod,
    amountTendered,
    changeAmount,
    exchangeRate,
    showAddress,
    showPhone,
    showRif,
    showInvoiceQr,
    showDate,
    showBarcode,
    showUnitPrices,
  ];
}
