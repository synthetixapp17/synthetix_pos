import 'dart:convert';

import '../../../core/data/hive_database.dart';
import '../../../core/utils/app_currency.dart';
import '../../reports/data/repositories/reports_repository_impl.dart';
import '../../reports/domain/entities/sale_record.dart';
import '../domain/entities/virtual_store_order.dart';

const virtualStoreOrdersKey = 'virtual_store_orders';

class VirtualStoreOrderStorage {
  List<VirtualStoreOrder> load() {
    final stored = HiveDatabase.settingsBox.get(virtualStoreOrdersKey);
    if (stored == null) return [];
    if (stored is! String) {
      throw const FormatException('El registro de pedidos no es válido.');
    }
    final decoded = jsonDecode(stored);
    if (decoded is! List) {
      throw const FormatException('El registro de pedidos no es válido.');
    }
    return decoded
        .map(
          (entry) => VirtualStoreOrder.fromJson(
            (entry as Map).cast<String, dynamic>(),
          ),
        )
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Future<void> save(List<VirtualStoreOrder> orders) async {
    await HiveDatabase.settingsBox.put(
      virtualStoreOrdersKey,
      jsonEncode(orders.map((order) => order.toJson()).toList()),
    );
  }

  Future<List<VirtualStoreOrder>> add(VirtualStoreOrder order) async {
    final orders = load();
    if (orders.any((existing) => existing.id == order.id)) {
      throw StateError('El identificador del pedido ya existe.');
    }
    orders.insert(0, order);
    await save(orders);
    return orders;
  }

  Future<List<VirtualStoreOrder>> markDelivered(String orderId) async {
    final orders = load();
    final index = orders.indexWhere((order) => order.id == orderId);
    if (index < 0) throw StateError('No se encontró el pedido.');
    final order = orders[index];
    if (order.isDelivered) return orders;

    final saleId = 'virtual-store-order-${order.id}';
    if (HiveDatabase.salesBox.containsKey(saleId)) {
      orders[index] = order.copyWith(deliveredAt: DateTime.now());
      await save(orders);
      return orders;
    }

    final currencyCode = AppCurrency.currentCode;
    final exchangeRate = AppCurrency.rateFor(currencyCode);
    final sale = SaleRecord(
      id: saleId,
      soldAt: DateTime.now(),
      total: order.totalUsd * exchangeRate,
      totalInCurrency: order.totalUsd * exchangeRate,
      exchangeRate: exchangeRate,
      customerName: order.customerName.isEmpty ? null : order.customerName,
      currencyCode: currencyCode,
      paymentMethod: 'Pedido tienda virtual',
      lines: [
        for (final line in order.lines)
          SaleLine(
            productId: line.productId,
            productName: line.productName,
            quantity: line.quantity,
            unitPrice: line.unitPriceUsd * exchangeRate,
            category: line.category,
            barcode: line.barcode,
            variantId: line.variantId,
            variantAttributes: line.variantAttributes,
            unitLabel: line.unitLabel,
            inventoryTracked: line.inventoryTracked,
          ),
      ],
    );
    final result = await ReportsRepositoryImpl().recordSale(sale);
    final failure = result.fold((failure) => failure, (_) => null);
    if (failure != null) {
      throw StateError('No se pudo entregar el pedido: ${failure.message}');
    }

    orders[index] = order.copyWith(deliveredAt: DateTime.now());
    await save(orders);
    return orders;
  }
}
