import 'package:intl/intl.dart';

import '../domain/entities/restaurant_state.dart';

class KitchenOrderChange {
  final TableOrderLine line;
  final double quantity;
  final bool isCancellation;

  const KitchenOrderChange({
    required this.line,
    required this.quantity,
    required this.isCancellation,
  });
}

class RestaurantKitchenTicket {
  const RestaurantKitchenTicket();

  List<KitchenOrderChange> changesFor(DiningTable table) {
    final changes = <KitchenOrderChange>[];
    final sentByProduct = {
      for (final line in table.sentKitchenOrder)
        (line.productId, line.variantId): line,
    };
    final currentKeys = <(String, String?)>{};

    for (final line in table.order) {
      final key = (line.productId, line.variantId);
      currentKeys.add(key);
      final sent = sentByProduct[key];
      final difference = line.quantity - (sent?.quantity ?? 0);
      if (difference != 0) {
        changes.add(
          KitchenOrderChange(
            line: line,
            quantity: difference.abs(),
            isCancellation: difference < 0,
          ),
        );
      }
    }

    for (final sent in table.sentKitchenOrder) {
      if (currentKeys.contains((sent.productId, sent.variantId))) continue;
      changes.add(
        KitchenOrderChange(
          line: sent,
          quantity: sent.quantity,
          isCancellation: true,
        ),
      );
    }
    return changes;
  }

  String format({
    required DiningTable table,
    required List<KitchenOrderChange> changes,
    DateTime? printedAt,
  }) {
    final hasCancellations = changes.any((change) => change.isCancellation);
    final output = StringBuffer()
      ..writeln(
        hasCancellations || table.sentKitchenOrder.isNotEmpty
            ? 'ACTUALIZACION DE COMANDA'
            : 'COMANDA',
      )
      ..writeln('MESA: ${table.name}')
      ..writeln(
        DateFormat('dd/MM/yyyy HH:mm').format(printedAt ?? DateTime.now()),
      )
      ..writeln('--------------------------------');

    for (final change in changes) {
      final quantity = _formatQuantity(change.quantity);
      final action = change.isCancellation ? 'ANULAR' : 'PREPARAR';
      output.writeln('$action $quantity x ${change.line.name}');
      if (change.line.category.isNotEmpty) {
        output.writeln('  ${change.line.category}');
      }
    }
    output
      ..writeln('--------------------------------')
      ..writeln()
      ..writeln();
    return output.toString();
  }

  String _formatQuantity(double quantity) =>
      quantity == quantity.roundToDouble()
      ? quantity.toInt().toString()
      : quantity.toString();
}
