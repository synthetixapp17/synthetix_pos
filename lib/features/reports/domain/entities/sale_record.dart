import 'dart:convert';

import 'package:equatable/equatable.dart';

class SaleLine extends Equatable {
  final String productId;
  final String productName;
  final int quantity;
  final double unitPrice;
  final String category;
  final String barcode;

  const SaleLine({
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.unitPrice,
    this.category = '',
    this.barcode = '',
  });

  double get total => quantity * unitPrice;

  Map<String, Object> toJson() => {
    'productId': productId,
    'productName': productName,
    'quantity': quantity,
    'unitPrice': unitPrice,
    'category': category,
    'barcode': barcode,
  };

  factory SaleLine.fromJson(Map<String, dynamic> json) => SaleLine(
    productId: json['productId'] as String,
    productName: json['productName'] as String,
    quantity: json['quantity'] as int,
    unitPrice: (json['unitPrice'] as num).toDouble(),
    category: json['category'] as String? ?? '',
    barcode: json['barcode'] as String? ?? '',
  );

  @override
  List<Object?> get props => [
    productId,
    productName,
    quantity,
    unitPrice,
    category,
    barcode,
  ];
}

class SaleRecord extends Equatable {
  final String id;
  final DateTime soldAt;
  final double total;
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
    required this.lines,
    this.customerId,
    this.customerName,
    this.currencyCode = 'USD',
    this.paymentMethod = 'Efectivo',
    this.amountTendered = 0,
    this.changeAmount = 0,
  });

  String get linesJson =>
      jsonEncode(lines.map((line) => line.toJson()).toList());

  @override
  List<Object?> get props => [
    id,
    soldAt,
    total,
    customerId,
    customerName,
    currencyCode,
    paymentMethod,
    amountTendered,
    changeAmount,
    lines,
  ];
}
