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

  SaleModel({
    required this.id,
    required this.soldAt,
    required this.total,
    required this.linesJson,
    this.currencyCode = 'USD',
    this.paymentMethod = 'Efectivo',
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
  );

  SaleRecord toEntity() => SaleRecord(
    id: id,
    soldAt: soldAt,
    total: total,
    customerId: customerId,
    customerName: customerName,
    currencyCode: currencyCode,
    paymentMethod: paymentMethod,
    lines: decodeSaleLines(linesJson),
  );
}

List<SaleLine> decodeSaleLines(String source) =>
    (jsonDecode(source) as List<dynamic>)
        .map((item) => SaleLine.fromJson(item as Map<String, dynamic>))
        .toList();
