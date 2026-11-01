class CreditPayment {
  final DateTime paidAt;
  final double amount;
  final String note;

  const CreditPayment({
    required this.paidAt,
    required this.amount,
    this.note = '',
  });

  Map<String, Object> toJson() => {
    'paidAt': paidAt.toIso8601String(),
    'amount': amount,
    'note': note,
  };

  factory CreditPayment.fromJson(Map<String, dynamic> json) => CreditPayment(
    paidAt: DateTime.parse(json['paidAt'] as String),
    amount: (json['amount'] as num).toDouble(),
    note: json['note'] as String? ?? '',
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
  final double interestPercentage;
  final double interestAmount;
  final String currencyCode;
  final String pdfBase64;
  final List<CreditPayment> payments;

  const CreditRecord({
    required this.id,
    required this.createdAt,
    required this.customerId,
    required this.customerName,
    required this.total,
    required this.currencyCode,
    required this.pdfBase64,
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
        interestPercentage: interestPercentage,
        interestAmount: interestAmount,
        currencyCode: currencyCode,
        pdfBase64: pdfBase64 ?? this.pdfBase64,
        payments: payments ?? this.payments,
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
    'interestPercentage': interestPercentage,
    'interestAmount': interestAmount,
    'currencyCode': currencyCode,
    'pdfBase64': pdfBase64,
    'payments': payments.map((payment) => payment.toJson()).toList(),
  };

  factory CreditRecord.fromJson(Map<String, dynamic> json) => CreditRecord(
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
    interestPercentage: (json['interestPercentage'] as num?)?.toDouble() ?? 0,
    interestAmount: (json['interestAmount'] as num?)?.toDouble() ?? 0,
    currencyCode: json['currencyCode'] as String? ?? 'USD',
    pdfBase64: json['pdfBase64'] as String? ?? '',
    payments: (json['payments'] as List<dynamic>? ?? const [])
        .map(
          (payment) => CreditPayment.fromJson(payment as Map<String, dynamic>),
        )
        .toList(),
  );
}
