enum ProductWeightUnit { grams, kilograms }

ProductWeightUnit? weightUnitForLabel(String label) {
  final normalized = label.trim().toLowerCase().replaceAll('.', '');
  return switch (normalized) {
    'g' || 'gr' || 'gram' || 'grams' || 'gramo' || 'gramos' =>
      ProductWeightUnit.grams,
    'kg' || 'kgs' || 'kilo' || 'kilos' || 'kilogram' || 'kilograms' ||
    'kilogramo' || 'kilogramos' => ProductWeightUnit.kilograms,
    _ => null,
  };
}

bool isWeightUnitLabel(String label) => weightUnitForLabel(label) != null;

double convertWeight({
  required double amount,
  required String fromUnit,
  required String toUnit,
}) {
  final source = weightUnitForLabel(fromUnit);
  final target = weightUnitForLabel(toUnit);
  if (source == null || target == null || !amount.isFinite || amount < 0) {
    throw ArgumentError('La cantidad o unidad de peso no es válida.');
  }
  if (source == target) return amount;
  return source == ProductWeightUnit.grams ? amount / 1000 : amount * 1000;
}
