import '../../../../core/data/hive_database.dart';
import '../domain/entities/restaurant_state.dart';

class RestaurantRepository {
  static const storageKey = 'restaurant_tables_v1';

  RestaurantState load() {
    final stored = HiveDatabase.settingsBox.get(storageKey);
    if (stored == null) return const RestaurantState();
    if (stored is! Map) {
      throw const FormatException('Los datos del restaurante no son válidos.');
    }
    return RestaurantState.fromMap(stored);
  }

  Future<void> save(RestaurantState state) async {
    final names = <String>{};
    final tableIds = <String>{};
    for (final table in state.tables) {
      final normalizedName = table.name.trim().toLowerCase();
      if (!tableIds.add(table.id) ||
          normalizedName.isEmpty ||
          !names.add(normalizedName)) {
        throw const FormatException(
          'Cada mesa debe tener un identificador y nombre únicos.',
        );
      }
    }
    final reservationIds = <String>{};
    final reservationWindows = <(String, DateTime, DateTime)>[];
    for (final reservation in state.reservations) {
      if (!reservationIds.add(reservation.id) ||
          !tableIds.contains(reservation.tableId)) {
        throw const FormatException(
          'La reserva debe pertenecer a una mesa existente.',
        );
      }
      final table = state.tables.firstWhere(
        (item) => item.id == reservation.tableId,
      );
      if (reservation.guests > table.seats) {
        throw FormatException(
          'La reserva de ${reservation.customerName} supera la capacidad de ${table.name}.',
        );
      }
      if (!reservation.isActive) continue;
      final start = reservation.startsAt;
      final end = start.add(const Duration(hours: 2));
      final conflict = reservationWindows.any(
        (window) =>
            window.$1 == reservation.tableId &&
            start.isBefore(window.$3) &&
            window.$2.isBefore(end),
      );
      if (conflict) {
        throw const FormatException(
          'Una mesa no puede tener reservas con horarios superpuestos.',
        );
      }
      reservationWindows.add((reservation.tableId, start, end));
    }
    await HiveDatabase.settingsBox.put(storageKey, state.toMap());
  }

  Future<void> clearTableSession(String tableId) async {
    final state = load();
    final index = state.tables.indexWhere((table) => table.id == tableId);
    if (index < 0) return;
    final tables = [...state.tables];
    tables[index] = tables[index].copyWith(clearSession: true);
    await save(RestaurantState(tables: tables, reservations: state.reservations));
  }
}
