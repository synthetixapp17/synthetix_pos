import 'dart:convert';

import 'package:hive/hive.dart';

import '../../domain/entities/sale_record.dart';

part 'sale_model.g.dart';

@HiveType(typeId: 3)
class SaleModel extends HiveObject {
  @HiveField(0)
  final String id;
  @HiveField(1)
  final DateTime soldAt;
  @HiveField(2)
  final double total;
  @HiveField(3)
  final String? customerId;
  @HiveField(4)
  final String? customerName;
  @HiveField(5, defaultValue: '[]')
  final String linesJson;
  @HiveField(6, defaultValue: 'USD')
  final String currencyCode;
  @HiveField(7, defaultValue: 'Efectivo')
  final String paymentMethod;
  @HiveField(8, defaultValue: 0.0)
  final double amountTendered;
  @HiveField(9, defaultValue: 0.0)
  final double changeAmount;
  @HiveField(10, defaultValue: 0.0)
  final double totalInCurrency;
  @HiveField(11, defaultValue: 1.0)
  final double exchangeRate;

  SaleModel({
    required this.id,
    required this.soldAt,
    required this.total,
    required this.linesJson,
    this.currencyCode = 'USD',
    this.paymentMethod = 'Efectivo',
    this.amountTendered = 0,
    this.changeAmount = 0,
    this.totalInCurrency = 0,
    this.exchangeRate = 1,
    this.customerId,
    this.customerName,
  });

  factory SaleModel.fromEntity(SaleRecord sale) => SaleModel(
    id: sale.id,
    soldAt: sale.soldAt,
    total: sale.total,
    customerId: sale.customerId,
    customerName: sale.customerName,
    linesJson: sale.linesJson,
    currencyCode: sale.currencyCode,
    paymentMethod: sale.paymentMethod,
    amountTendered: sale.amountTendered,
    changeAmount: sale.changeAmount,
    totalInCurrency: sale.totalInCurrency,
    exchangeRate: sale.exchangeRate,
  );

  SaleRecord toEntity() => SaleRecord(
    id: id,
    soldAt: soldAt,
    total: total,
    customerId: customerId,
    customerName: customerName,
    currencyCode: currencyCode,
    paymentMethod: paymentMethod,
    amountTendered: amountTendered,
    changeAmount: changeAmount,
    totalInCurrency: totalInCurrency == 0 ? total : totalInCurrency,
    exchangeRate: exchangeRate,
    lines: decodeSaleLines(linesJson),
  );
}

List<SaleLine> decodeSaleLines(String source) =>
    (jsonDecode(source) as List<dynamic>)
        .map((item) => SaleLine.fromJson(item as Map<String, dynamic>))
        .toList();
