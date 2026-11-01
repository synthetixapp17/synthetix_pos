class CreditSchedule {
  static double roundMoney(double amount) =>
      (amount * 100).roundToDouble() / 100;

  static double simpleInterest({
    required double principal,
    required double percentage,
  }) {
    if (!principal.isFinite ||
        principal < 0 ||
        !percentage.isFinite ||
        percentage < 0) {
      throw ArgumentError('El capital y la tasa deben ser válidos.');
    }
    final interest = roundMoney(principal * percentage / 100);
    if (!interest.isFinite) {
      throw ArgumentError('El interés calculado no es válido.');
    }
    return interest;
  }

  static List<double> splitEvenly(double amount, int installments) {
    if (!amount.isFinite || amount < 0 || installments < 1) {
      throw ArgumentError('El monto y el número de cuotas deben ser válidos.');
    }
    final cents = (roundMoney(amount) * 100).round();
    final base = cents ~/ installments;
    final remainder = cents.remainder(installments);
    return List.generate(
      installments,
      (index) => (base + (index < remainder ? 1 : 0)) / 100,
    );
  }
}
