import 'package:equatable/equatable.dart';

class VirtualStoreOrderLine extends Equatable {
  final String productId;
  final String productName;
  final double quantity;
  final double unitPriceUsd;
  final String category;
  final String barcode;
  final String? variantId;
  final Map<String, String> variantAttributes;
  final String unitLabel;
  final bool inventoryTracked;

  const VirtualStoreOrderLine({
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.unitPriceUsd,
    this.category = '',
    this.barcode = '',
    this.variantId,
    this.variantAttributes = const {},
    this.unitLabel = 'ud.',
    this.inventoryTracked = true,
  });

  double get totalUsd => quantity * unitPriceUsd;

  Map<String, Object?> toJson() => {
    'productId': productId,
    'productName': productName,
    'quantity': quantity,
    'unitPriceUsd': unitPriceUsd,
    'category': category,
    'barcode': barcode,
    'variantId': variantId,
    'variantAttributes': variantAttributes,
    'unitLabel': unitLabel,
    'inventoryTracked': inventoryTracked,
  };

  factory VirtualStoreOrderLine.fromJson(Map<String, dynamic> json) {
    final quantity = json['quantity'];
    final unitPrice = json['unitPriceUsd'];
    if (quantity is! num ||
        !quantity.toDouble().isFinite ||
        quantity <= 0 ||
        unitPrice is! num ||
        !unitPrice.toDouble().isFinite ||
        unitPrice < 0) {
      throw const FormatException('Una línea del pedido no es válida.');
    }
    return VirtualStoreOrderLine(
      productId: _requiredString(json, 'productId'),
      productName: _requiredString(json, 'productName'),
      quantity: quantity.toDouble(),
      unitPriceUsd: unitPrice.toDouble(),
      category: json['category'] as String? ?? '',
      barcode: json['barcode'] as String? ?? '',
      variantId: json['variantId'] as String?,
      variantAttributes:
          (json['variantAttributes'] as Map<String, dynamic>? ?? {}).map(
            (key, value) => MapEntry(key, value.toString()),
          ),
      unitLabel: json['unitLabel'] as String? ?? 'ud.',
      inventoryTracked: json['inventoryTracked'] as bool? ?? true,
    );
  }

  @override
  List<Object?> get props => [
    productId,
    productName,
    quantity,
    unitPriceUsd,
    category,
    barcode,
    variantId,
    variantAttributes,
    unitLabel,
    inventoryTracked,
  ];
}

class VirtualStoreOrder extends Equatable {
  final String id;
  final DateTime createdAt;
  final String customerName;
  final String customerPhone;
  final List<VirtualStoreOrderLine> lines;
  final DateTime? deliveredAt;

  const VirtualStoreOrder({
    required this.id,
    required this.createdAt,
    required this.customerName,
    required this.customerPhone,
    required this.lines,
    this.deliveredAt,
  });

  bool get isDelivered => deliveredAt != null;
  double get totalUsd => lines.fold(0, (total, line) => total + line.totalUsd);

  VirtualStoreOrder copyWith({DateTime? deliveredAt}) => VirtualStoreOrder(
    id: id,
    createdAt: createdAt,
    customerName: customerName,
    customerPhone: customerPhone,
    lines: lines,
    deliveredAt: deliveredAt ?? this.deliveredAt,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'createdAt': createdAt.toIso8601String(),
    'customerName': customerName,
    'customerPhone': customerPhone,
    'lines': lines.map((line) => line.toJson()).toList(),
    'deliveredAt': deliveredAt?.toIso8601String(),
  };

  factory VirtualStoreOrder.fromJson(Map<String, dynamic> json) {
    final lines = json['lines'];
    final createdAt = DateTime.tryParse(json['createdAt']?.toString() ?? '');
    final deliveredAtSource = json['deliveredAt'];
    final deliveredAt = deliveredAtSource == null
        ? null
        : DateTime.tryParse(deliveredAtSource.toString());
    if (createdAt == null ||
        deliveredAtSource != null && deliveredAt == null ||
        lines is! List ||
        lines.isEmpty) {
      throw const FormatException('Un pedido guardado no es válido.');
    }
    return VirtualStoreOrder(
      id: _requiredString(json, 'id'),
      createdAt: createdAt,
      customerName: json['customerName'] as String? ?? '',
      customerPhone: json['customerPhone'] as String? ?? '',
      lines: lines
          .map(
            (line) => VirtualStoreOrderLine.fromJson(
              (line as Map).cast<String, dynamic>(),
            ),
          )
          .toList(),
      deliveredAt: deliveredAt,
    );
  }

  @override
  List<Object?> get props => [
    id,
    createdAt,
    customerName,
    customerPhone,
    lines,
    deliveredAt,
  ];
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('El campo "$key" del pedido no es válido.');
  }
  return value;
}
