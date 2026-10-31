class QuotationLine {
  final String productName;
  final String barcode;
  final int quantity;
  final double unitPrice;

  const QuotationLine({
    required this.productName,
    required this.barcode,
    required this.quantity,
    required this.unitPrice,
  });

  double get total => quantity * unitPrice;

  Map<String, Object> toJson() => {
    'productName': productName,
    'barcode': barcode,
    'quantity': quantity,
    'unitPrice': unitPrice,
  };

  factory QuotationLine.fromJson(Map<String, dynamic> json) => QuotationLine(
    productName: json['productName'] as String,
    barcode: json['barcode'] as String? ?? '',
    quantity: json['quantity'] as int,
    unitPrice: (json['unitPrice'] as num).toDouble(),
  );
}

class QuotationRecord {
  final String id;
  final DateTime createdAt;
  final String customerName;
  final String shopName;
  final String currencyCode;
  final List<QuotationLine> lines;

  const QuotationRecord({
    required this.id,
    required this.createdAt,
    required this.customerName,
    required this.shopName,
    required this.currencyCode,
    required this.lines,
  });

  double get total => lines.fold(0, (sum, line) => sum + line.total);

  Map<String, Object> toJson() => {
    'id': id,
    'createdAt': createdAt.toIso8601String(),
    'customerName': customerName,
    'shopName': shopName,
    'currencyCode': currencyCode,
    'lines': lines.map((line) => line.toJson()).toList(),
  };

  factory QuotationRecord.fromJson(Map<String, dynamic> json) =>
      QuotationRecord(
        id: json['id'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        customerName: json['customerName'] as String? ?? '',
        shopName: json['shopName'] as String? ?? '',
        currencyCode: json['currencyCode'] as String? ?? 'USD',
        lines: (json['lines'] as List<dynamic>)
            .map((line) => QuotationLine.fromJson(line as Map<String, dynamic>))
            .toList(),
      );
}
