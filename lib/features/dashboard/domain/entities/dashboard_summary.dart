import 'package:equatable/equatable.dart';

import '../../../product/domain/entities/product.dart';

class ProductSales extends Equatable {
  final String name;
  final int quantity;

  const ProductSales({required this.name, required this.quantity});

  @override
  List<Object?> get props => [name, quantity];
}

class DailySales extends Equatable {
  final DateTime date;
  final double amount;
  final String currencyCode;

  const DailySales({
    required this.date,
    required this.amount,
    this.currencyCode = 'USD',
  });

  @override
  List<Object?> get props => [date, amount, currencyCode];
}

class DashboardSummary extends Equatable {
  final double dailyTotal;
  final int transactionCount;
  final List<ProductSales> bestSellers;
  final List<Product> lowStock;
  final List<DailySales> lastSevenDays;
  final int lowStockThreshold;
  final Map<String, double> dailyTotals;

  const DashboardSummary({
    required this.dailyTotal,
    required this.transactionCount,
    required this.bestSellers,
    required this.lowStock,
    required this.lastSevenDays,
    required this.lowStockThreshold,
    this.dailyTotals = const {},
  });

  @override
  List<Object?> get props => [
    dailyTotal,
    transactionCount,
    bestSellers,
    lowStock,
    lastSevenDays,
    lowStockThreshold,
    dailyTotals,
  ];
}
