import 'dart:convert';

import 'package:equatable/equatable.dart';

class SaleLine extends Equatable {
  final String productId;
  final String productName;
  final double quantity;
  final double unitPrice;
  final String category;
  final String barcode;
  final String? variantId;
  final Map<String, String> variantAttributes;
  final String unitLabel;

  const SaleLine({
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.unitPrice,
    this.category = '',
    this.barcode = '',
    this.variantId,
    this.variantAttributes = const {},
    this.unitLabel = 'ud.',
  });

  double get total => quantity * unitPrice;
  String get displayQuantity => quantity == quantity.roundToDouble()
      ? '${quantity.toInt()}'
      : '$quantity';

  String get variationLabel => variantAttributes.entries
      .map((entry) => '${entry.key}: ${entry.value}')
      .join(' · ');

  Map<String, Object?> toJson() => {
    'productId': productId,
    'productName': productName,
    'quantity': quantity,
    'unitPrice': unitPrice,
    'category': category,
    'barcode': barcode,
    'variantId': variantId,
    'variantAttributes': variantAttributes,
    'unitLabel': unitLabel,
  };

  factory SaleLine.fromJson(Map<String, dynamic> json) => SaleLine(
    productId: json['productId'] as String,
    productName: json['productName'] as String,
    quantity: (json['quantity'] as num).toDouble(),
    unitPrice: (json['unitPrice'] as num).toDouble(),
    category: json['category'] as String? ?? '',
    barcode: json['barcode'] as String? ?? '',
    variantId: json['variantId'] as String?,
    variantAttributes:
        (json['variantAttributes'] as Map<String, dynamic>? ?? {}).map(
          (key, value) => MapEntry(key, value.toString()),
        ),
    unitLabel: json['unitLabel'] as String? ?? 'ud.',
  );

  @override
  List<Object?> get props => [
    productId,
    productName,
    quantity,
    unitPrice,
    category,
    barcode,
    variantId,
    variantAttributes,
    unitLabel,
  ];
}

class SaleRecord extends Equatable {
  final String id;
  final DateTime soldAt;
  final double total;
  final double totalInCurrency;
  final double exchangeRate;
  final String? customerId;
  final String? customerName;
  final String currencyCode;
  final String paymentMethod;
  final double amountTendered;
  final double changeAmount;
  final List<SaleLine> lines;

  const SaleRecord({
    required this.id,
    required this.soldAt,
    required this.total,
    double? totalInCurrency,
    this.exchangeRate = 1,
    required this.lines,
    this.customerId,
    this.customerName,
    this.currencyCode = 'USD',
    this.paymentMethod = 'Efectivo',
    this.amountTendered = 0,
    this.changeAmount = 0,
  }) : totalInCurrency = totalInCurrency ?? total;

  String get linesJson =>
      jsonEncode(lines.map((line) => line.toJson()).toList());

  @override
  List<Object?> get props => [
    id,
    soldAt,
    total,
    totalInCurrency,
    exchangeRate,
    customerId,
    customerName,
    currencyCode,
    paymentMethod,
    amountTendered,
    changeAmount,
    lines,
  ];
}
