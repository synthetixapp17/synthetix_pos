import 'package:billing_app/features/restaurant/data/restaurant_kitchen_ticket.dart';
import 'package:billing_app/features/restaurant/domain/entities/restaurant_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const ticket = RestaurantKitchenTicket();

  test('includes only new quantities after a prior kitchen send', () {
    const table = DiningTable(
      id: 'table-1',
      name: 'Terraza 1',
      seats: 4,
      order: [
        TableOrderLine(
          productId: 'coffee',
          variantId: null,
          name: 'Café',
          currencyCode: 'USD',
          quantity: 3,
          unitPrice: 2,
          category: 'Bebidas',
        ),
      ],
      sentKitchenOrder: [
        TableOrderLine(
          productId: 'coffee',
          variantId: null,
          name: 'Café',
          currencyCode: 'USD',
          quantity: 2,
          unitPrice: 2,
          category: 'Bebidas',
        ),
      ],
    );

    final changes = ticket.changesFor(table);

    expect(changes, hasLength(1));
    expect(changes.single.quantity, 1);
    expect(changes.single.isCancellation, isFalse);
  });

  test('creates a cancellation change when a sent item is removed', () {
    const table = DiningTable(
      id: 'table-1',
      name: 'Terraza 1',
      seats: 4,
      sentKitchenOrder: [
        TableOrderLine(
          productId: 'coffee',
          variantId: null,
          name: 'Café',
          currencyCode: 'USD',
          quantity: 2,
          unitPrice: 2,
        ),
      ],
    );

    final change = ticket.changesFor(table).single;

    expect(change.quantity, 2);
    expect(change.isCancellation, isTrue);
    expect(
      ticket.format(
        table: table,
        changes: [change],
        printedAt: DateTime(2026, 11, 14, 18),
      ),
      contains('ANULAR 2 x Café'),
    );
  });
}
