import 'package:billing_app/features/credit/domain/entities/credit_record.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'credit balances include initial and later payments after serialization',
    () {
      final credit = CreditRecord(
        id: 'credit-1',
        createdAt: DateTime(2026, 10, 31),
        dueDate: DateTime(2026, 11, 30),
        customerId: 'customer-1',
        customerName: 'Cliente',
        customerPhone: '55512345',
        customerIdentity: 'V-12345678',
        total: 120,
        purchaseAmount: 110,
        initialPayment: 20,
        installmentCount: 3,
        daysBetweenPayments: 15,
        interestPercentage: 10,
        interestAmount: 10,
        currencyCode: 'USD',
        pdfBase64: 'cGRm',
        lines: const [
          CreditLineItem(
            productId: 'product-1',
            productName: 'Producto',
            quantity: 2,
            unitPrice: 55,
          ),
        ],
        payments: [
          CreditPayment(
            paidAt: DateTime(2026, 10, 31),
            amount: 20,
            note: 'Abono inicial',
          ),
          CreditPayment(
            paidAt: DateTime(2026, 11, 5),
            amount: 30,
            note: 'Abono',
            method: 'Transferencia',
          ),
        ],
      );

      final restored = CreditRecord.fromJson(credit.toJson());
      expect(restored.paidAmount, 50);
      expect(restored.balance, 70);
      expect(restored.isPaid, isFalse);
      expect(restored.pdfBase64, 'cGRm');
      expect(restored.customerIdentity, 'V-12345678');
      expect(restored.interestPercentage, 10);
      expect(restored.interestAmount, 10);
      expect(restored.payments, hasLength(2));
      expect(restored.payments.last.method, 'Transferencia');
      expect(restored.purchaseAmount, 110);
      expect(restored.initialPayment, 20);
      expect(restored.installmentCount, 3);
      expect(restored.daysBetweenPayments, 15);
      expect(restored.lines.single.total, 110);
    },
  );

  test('reads older credit records without payment and schedule metadata', () {
    final legacy = CreditRecord.fromJson({
      'id': 'legacy-credit',
      'createdAt': '2026-10-31T00:00:00.000',
      'customerId': 'customer-1',
      'customerName': 'Cliente',
      'total': 10,
      'currencyCode': 'USD',
      'pdfBase64': '',
      'payments': [
        {
          'paidAt': '2026-10-31T00:00:00.000',
          'amount': 2,
          'note': 'Abono inicial',
        },
      ],
    });

    expect(legacy.initialPayment, 2);
    expect(legacy.payments.single.method, 'Efectivo');
    expect(legacy.lines, isEmpty);
    expect(legacy.installmentCount, isNull);
  });
}
