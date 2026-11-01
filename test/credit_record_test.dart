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
        interestPercentage: 10,
        interestAmount: 10,
        currencyCode: 'USD',
        pdfBase64: 'cGRm',
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
    },
  );
}
