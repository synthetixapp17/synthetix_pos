class RestaurantState {
  final List<DiningTable> tables;
  final List<TableReservation> reservations;

  const RestaurantState({this.tables = const [], this.reservations = const []});

  factory RestaurantState.fromMap(Map<dynamic, dynamic> map) {
    final tables = map['tables'];
    final reservations = map['reservations'];
    if (tables is! List || reservations is! List) {
      throw const FormatException('La configuración de mesas no es válida.');
    }
    return RestaurantState(
      tables: tables.map((item) => DiningTable.fromMap(item as Map)).toList(),
      reservations: reservations
          .map((item) => TableReservation.fromMap(item as Map))
          .toList(),
    );
  }

  Map<String, Object> toMap() => {
    'tables': tables.map((table) => table.toMap()).toList(),
    'reservations': reservations
        .map((reservation) => reservation.toMap())
        .toList(),
  };
}

class DiningTable {
  final String id;
  final String name;
  final int seats;
  final DateTime? openedAt;
  final List<TableOrderLine> order;

  const DiningTable({
    required this.id,
    required this.name,
    required this.seats,
    this.openedAt,
    this.order = const [],
  });

  bool get isOpen => openedAt != null;

  DiningTable copyWith({
    String? name,
    int? seats,
    DateTime? openedAt,
    bool clearSession = false,
    List<TableOrderLine>? order,
  }) => DiningTable(
    id: id,
    name: name ?? this.name,
    seats: seats ?? this.seats,
    openedAt: clearSession ? null : openedAt ?? this.openedAt,
    order: clearSession ? const [] : order ?? this.order,
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'name': name,
    'seats': seats,
    'openedAt': openedAt?.toIso8601String(),
    'order': order.map((line) => line.toMap()).toList(),
  };

  factory DiningTable.fromMap(Map map) {
    final id = map['id'];
    final name = map['name'];
    final seats = map['seats'];
    final rawOrder = map['order'] ?? const [];
    final openedAt = map['openedAt'] == null
        ? null
        : DateTime.tryParse(map['openedAt'].toString());
    if (id is! String ||
        id.isEmpty ||
        name is! String ||
        name.trim().isEmpty ||
        seats is! int ||
        seats < 1 ||
        rawOrder is! List ||
        (map['openedAt'] != null && openedAt == null)) {
      throw const FormatException('Una mesa guardada no es válida.');
    }
    return DiningTable(
      id: id,
      name: name,
      seats: seats,
      openedAt: openedAt,
      order: rawOrder
          .map((item) => TableOrderLine.fromMap(item as Map))
          .toList(),
    );
  }
}

class TableOrderLine {
  final String productId;
  final String? variantId;
  final String name;
  final String currencyCode;
  final double quantity;
  final double unitPrice;
  final String category;
  final bool inventoryTracked;

  const TableOrderLine({
    required this.productId,
    required this.variantId,
    required this.name,
    required this.currencyCode,
    required this.quantity,
    required this.unitPrice,
    this.category = '',
    this.inventoryTracked = true,
  });

  double get total => quantity * unitPrice;

  Map<String, Object?> toMap() => {
    'productId': productId,
    'variantId': variantId,
    'name': name,
    'currencyCode': currencyCode,
    'quantity': quantity,
    'unitPrice': unitPrice,
    'category': category,
    'inventoryTracked': inventoryTracked,
  };

  factory TableOrderLine.fromMap(Map map) {
    final productId = map['productId'];
    final variantId = map['variantId'];
    final name = map['name'];
    final currencyCode = map['currencyCode'] ?? 'USD';
    final quantity = map['quantity'];
    final unitPrice = map['unitPrice'];
    final category = map['category'] ?? '';
    final inventoryTracked = map['inventoryTracked'] ?? true;
    if (productId is! String ||
        productId.isEmpty ||
        (variantId != null && variantId is! String) ||
        name is! String ||
        currencyCode is! String ||
        quantity is! num ||
        !quantity.toDouble().isFinite ||
        quantity <= 0 ||
        unitPrice is! num ||
        !unitPrice.toDouble().isFinite ||
        unitPrice < 0 ||
        category is! String ||
        inventoryTracked is! bool) {
      throw const FormatException('Un producto de un pedido no es válido.');
    }
    return TableOrderLine(
      productId: productId,
      variantId: variantId as String?,
      name: name,
      currencyCode: currencyCode,
      quantity: quantity.toDouble(),
      unitPrice: unitPrice.toDouble(),
      category: category,
      inventoryTracked: inventoryTracked,
    );
  }
}

class TableReservation {
  final String id;
  final String tableId;
  final String customerName;
  final String phone;
  final int guests;
  final DateTime startsAt;
  final String notes;
  final String status;

  const TableReservation({
    required this.id,
    required this.tableId,
    required this.customerName,
    required this.phone,
    required this.guests,
    required this.startsAt,
    this.notes = '',
    this.status = 'reserved',
  });

  bool get isActive => status == 'reserved';

  TableReservation copyWith({String? status}) => TableReservation(
    id: id,
    tableId: tableId,
    customerName: customerName,
    phone: phone,
    guests: guests,
    startsAt: startsAt,
    notes: notes,
    status: status ?? this.status,
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'tableId': tableId,
    'customerName': customerName,
    'phone': phone,
    'guests': guests,
    'startsAt': startsAt.toIso8601String(),
    'notes': notes,
    'status': status,
  };

  factory TableReservation.fromMap(Map map) {
    final id = map['id'];
    final tableId = map['tableId'];
    final name = map['customerName'];
    final phone = map['phone'];
    final guests = map['guests'];
    final startsAt = DateTime.tryParse(map['startsAt']?.toString() ?? '');
    final notes = map['notes'] ?? '';
    final status = map['status'] ?? 'reserved';
    if (id is! String ||
        id.isEmpty ||
        tableId is! String ||
        tableId.isEmpty ||
        name is! String ||
        name.trim().isEmpty ||
        phone is! String ||
        guests is! int ||
        guests < 1 ||
        startsAt == null ||
        notes is! String ||
        status is! String ||
        !const {'reserved', 'seated', 'cancelled'}.contains(status)) {
      throw const FormatException('Una reserva guardada no es válida.');
    }
    return TableReservation(
      id: id,
      tableId: tableId,
      customerName: name,
      phone: phone,
      guests: guests,
      startsAt: startsAt,
      notes: notes,
      status: status,
    );
  }
}
