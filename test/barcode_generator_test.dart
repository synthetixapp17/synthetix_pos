import 'package:billing_app/core/utils/barcode_generator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('generates a unique EAN-13 barcode with a valid check digit', () {
    final barcode = BarcodeGenerator.generateEan13(
      excluding: const ['2000000000000'],
    );

    expect(barcode, matches(RegExp(r'^\d{13}$')));
    expect(barcode, isNot('2000000000000'));

    var weightedSum = 0;
    for (var index = 0; index < barcode.length; index++) {
      weightedSum += int.parse(barcode[index]) * (index.isEven ? 1 : 3);
    }
    expect(weightedSum % 10, 0);
  });
}
