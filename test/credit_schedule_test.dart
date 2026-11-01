import 'package:billing_app/features/credit/domain/entities/credit_schedule.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('calculates simple interest on financed principal', () {
    expect(CreditSchedule.simpleInterest(principal: 100, percentage: 10), 10);
  });

  test('splits the balance into cent-accurate installments', () {
    final installments = CreditSchedule.splitEvenly(10, 3);

    expect(installments, [3.34, 3.33, 3.33]);
    expect(
      installments.reduce((sum, amount) => sum + amount),
      closeTo(10, 0.00001),
    );
  });

  test('rejects invalid interest and installment inputs', () {
    expect(
      () => CreditSchedule.simpleInterest(principal: 100, percentage: -1),
      throwsArgumentError,
    );
    expect(() => CreditSchedule.splitEvenly(100, 0), throwsArgumentError);
  });
}
