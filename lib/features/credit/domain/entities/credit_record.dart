import '../../../../core/utils/payment_methods.dart';

class CreditPayment {
  static List<String> get methods => loadPaymentMethods();

  final DateTime paidAt;
  final double amount;
  final String note;
  final String method;

  const CreditPayment({
    required this.paidAt,
    required this.amount,
    this.note = '',
    this.method = 'Efectivo',
  });

  Map<String, Object> toJson() => {
    'paidAt': paidAt.toIso8601String(),
    'amount': amount,
    'note': note,
    'method': method,
  };

  factory CreditPayment.fromJson(Map<String, dynamic> json) => CreditPayment(
    paidAt: DateTime.parse(json['paidAt'] as String),
    amount: (json['amount'] as num).toDouble(),
    note: json['note'] as String? ?? '',
    method: json['method'] as String? ?? 'Efectivo',
  );
}

class CreditLineItem {
  final String productId;
  final String productName;
  final String category;
  final String barcode;
  final double quantity;
  final double unitPrice;
  final String? variantId;
  final Map<String, String> variantAttributes;
  final String unitLabel;

  const CreditLineItem({
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.unitPrice,
    this.category = '',
    this.barcode = '',
    this.variantId,
    this.variantAttributes = const {},
    this.unitLabel = 'ud.',
  });

  double get total => quantity * unitPrice;
  String get displayQuantity => quantity == quantity.roundToDouble()
      ? '${quantity.toInt()}'
      : '$quantity';

  Map<String, Object?> toJson() => {
    'productId': productId,
    'productName': productName,
    'category': category,
    'barcode': barcode,
    'quantity': quantity,
    'unitPrice': unitPrice,
    'variantId': variantId,
    'variantAttributes': variantAttributes,
    'unitLabel': unitLabel,
  };

  factory CreditLineItem.fromJson(Map<String, dynamic> json) => CreditLineItem(
    productId: json['productId'] as String? ?? '',
    productName: json['productName'] as String,
    category: json['category'] as String? ?? '',
    barcode: json['barcode'] as String? ?? '',
    quantity: (json['quantity'] as num).toDouble(),
    unitPrice: (json['unitPrice'] as num).toDouble(),
    variantId: json['variantId'] as String?,
    variantAttributes:
        (json['variantAttributes'] as Map<String, dynamic>? ?? {}).map(
          (key, value) => MapEntry(key, value.toString()),
        ),
    unitLabel: json['unitLabel'] as String? ?? 'ud.',
  );
}

class CreditRecord {
  final String id;
  final DateTime createdAt;
  final DateTime? dueDate;
  final String customerId;
  final String customerName;
  final String customerPhone;
  final String customerIdentity;
  final String customerEmail;
  final String customerAddress;
  final double total;
  final double? purchaseAmount;
  final double initialPayment;
  final int? installmentCount;
  final int? daysBetweenPayments;
  final double interestPercentage;
  final double interestAmount;
  final String currencyCode;
  final double exchangeRate;
  final String pdfBase64;
  final List<CreditPayment> payments;
  final List<CreditLineItem> lines;

  const CreditRecord({
    required this.id,
    required this.createdAt,
    required this.customerId,
    required this.customerName,
    required this.total,
    required this.currencyCode,
    required this.pdfBase64,
    this.exchangeRate = 1,
    this.purchaseAmount,
    this.initialPayment = 0,
    this.installmentCount,
    this.daysBetweenPayments,
    this.lines = const [],
    this.dueDate,
    this.customerPhone = '',
    this.customerIdentity = '',
    this.customerEmail = '',
    this.customerAddress = '',
    this.interestPercentage = 0,
    this.interestAmount = 0,
    this.payments = const [],
  });

  double get paidAmount =>
      payments.fold(0, (total, payment) => total + payment.amount);

  double get balance => (total - paidAmount).clamp(0, total).toDouble();

  bool get isPaid => balance <= 0.001;

  CreditRecord copyWith({String? pdfBase64, List<CreditPayment>? payments}) =>
      CreditRecord(
        id: id,
        createdAt: createdAt,
        dueDate: dueDate,
        customerId: customerId,
        customerName: customerName,
        customerPhone: customerPhone,
        customerIdentity: customerIdentity,
        customerEmail: customerEmail,
        customerAddress: customerAddress,
        total: total,
        purchaseAmount: purchaseAmount,
        initialPayment: initialPayment,
        installmentCount: installmentCount,
        daysBetweenPayments: daysBetweenPayments,
        interestPercentage: interestPercentage,
        interestAmount: interestAmount,
        currencyCode: currencyCode,
        exchangeRate: exchangeRate,
        pdfBase64: pdfBase64 ?? this.pdfBase64,
        payments: payments ?? this.payments,
        lines: lines,
      );

  Map<String, Object?> toJson() => {
    'id': id,
    'createdAt': createdAt.toIso8601String(),
    'dueDate': dueDate?.toIso8601String(),
    'customerId': customerId,
    'customerName': customerName,
    'customerPhone': customerPhone,
    'customerIdentity': customerIdentity,
    'customerEmail': customerEmail,
    'customerAddress': customerAddress,
    'total': total,
    'purchaseAmount': purchaseAmount,
    'initialPayment': initialPayment,
    'installmentCount': installmentCount,
    'daysBetweenPayments': daysBetweenPayments,
    'interestPercentage': interestPercentage,
    'interestAmount': interestAmount,
    'currencyCode': currencyCode,
    'exchangeRate': exchangeRate,
    'pdfBase64': pdfBase64,
    'payments': payments.map((payment) => payment.toJson()).toList(),
    'lines': lines.map((line) => line.toJson()).toList(),
  };

  factory CreditRecord.fromJson(Map<String, dynamic> json) {
    final payments = (json['payments'] as List<dynamic>? ?? const [])
        .map(
          (payment) => CreditPayment.fromJson(payment as Map<String, dynamic>),
        )
        .toList();
    return CreditRecord(
      id: json['id'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      dueDate: json['dueDate'] == null
          ? null
          : DateTime.parse(json['dueDate'] as String),
      customerId: json['customerId'] as String,
      customerName: json['customerName'] as String,
      customerPhone: json['customerPhone'] as String? ?? '',
      customerIdentity: json['customerIdentity'] as String? ?? '',
      customerEmail: json['customerEmail'] as String? ?? '',
      customerAddress: json['customerAddress'] as String? ?? '',
      total: (json['total'] as num).toDouble(),
      purchaseAmount: (json['purchaseAmount'] as num?)?.toDouble(),
      initialPayment:
          (json['initialPayment'] as num?)?.toDouble() ??
          payments
              .where((payment) => payment.note == 'Abono inicial')
              .fold<double>(0, (total, payment) => total + payment.amount),
      installmentCount: json['installmentCount'] as int?,
      daysBetweenPayments: json['daysBetweenPayments'] as int?,
      interestPercentage: (json['interestPercentage'] as num?)?.toDouble() ?? 0,
      interestAmount: (json['interestAmount'] as num?)?.toDouble() ?? 0,
      currencyCode: json['currencyCode'] as String? ?? 'USD',
      exchangeRate: (json['exchangeRate'] as num?)?.toDouble() ?? 1,
      pdfBase64: json['pdfBase64'] as String? ?? '',
      payments: payments,
      lines: (json['lines'] as List<dynamic>? ?? const [])
          .map((line) => CreditLineItem.fromJson(line as Map<String, dynamic>))
          .toList(),
    );
  }
}
