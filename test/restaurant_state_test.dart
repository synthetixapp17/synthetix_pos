import 'package:billing_app/features/restaurant/domain/entities/restaurant_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('round-trips dining tables, open orders, and reservations', () {
    final startsAt = DateTime(2026, 11, 12, 19, 30);
    final state = RestaurantState(
      tables: [
        DiningTable(
          id: 'table-1',
          name: 'Terraza 1',
          seats: 4,
          openedAt: startsAt,
          order: const [
            TableOrderLine(
              productId: 'product-1',
              variantId: 'variant-1',
              name: 'Hamburguesa · Doble',
              currencyCode: 'USD',
              quantity: 2,
              unitPrice: 12.5,
            ),
          ],
        ),
      ],
      reservations: [
        TableReservation(
          id: 'reservation-1',
          tableId: 'table-1',
          customerName: 'Ana Pérez',
          phone: '04121234567',
          guests: 3,
          startsAt: startsAt,
          notes: 'Mesa cerca de la ventana',
        ),
      ],
    );

    final decoded = RestaurantState.fromMap(state.toMap());

    expect(decoded.tables.single.name, 'Terraza 1');
    expect(decoded.tables.single.isOpen, isTrue);
    expect(decoded.tables.single.order.single.total, 25);
    expect(decoded.tables.single.order.single.variantId, 'variant-1');
    expect(decoded.reservations.single.customerName, 'Ana Pérez');
    expect(decoded.reservations.single.startsAt, startsAt);
    expect(decoded.reservations.single.isActive, isTrue);
  });

  test('rejects invalid table capacities and order quantities', () {
    expect(
      () =>
          DiningTable.fromMap({'id': 'table-1', 'name': 'Mesa 1', 'seats': 0}),
      throwsFormatException,
    );
    expect(
      () => TableOrderLine.fromMap({
        'productId': 'product-1',
        'name': 'Producto',
        'quantity': 0,
        'unitPrice': 1,
      }),
      throwsFormatException,
    );
  });
}
