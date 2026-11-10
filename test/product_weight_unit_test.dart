import 'package:billing_app/features/product/domain/entities/product_weight_unit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('recognizes common gram and kilogram labels', () {
    expect(isWeightUnitLabel('g'), isTrue);
    expect(isWeightUnitLabel('gramos'), isTrue);
    expect(isWeightUnitLabel('KG.'), isTrue);
    expect(isWeightUnitLabel('unidad'), isFalse);
  });

  test('converts calculator input to the product inventory unit', () {
    expect(convertWeight(amount: 250, fromUnit: 'g', toUnit: 'kg'), 0.25);
    expect(convertWeight(amount: 1.5, fromUnit: 'kg', toUnit: 'g'), 1500);
    expect(convertWeight(amount: 0.5, fromUnit: 'kg', toUnit: 'kg'), 0.5);
  });
}
