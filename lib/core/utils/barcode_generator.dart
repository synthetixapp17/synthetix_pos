import 'dart:math';

class BarcodeGenerator {
  static final _random = Random.secure();

  static String generateEan13({Iterable<String> excluding = const []}) {
    final existing = excluding.toSet();

    for (var attempt = 0; attempt < 100; attempt++) {
      final digits = StringBuffer('2');
      for (var index = 1; index < 12; index++) {
        digits.write(_random.nextInt(10));
      }

      final firstTwelve = digits.toString();
      var weightedSum = 0;
      for (var index = 0; index < firstTwelve.length; index++) {
        weightedSum += int.parse(firstTwelve[index]) * (index.isEven ? 1 : 3);
      }
      final checkDigit = (10 - weightedSum % 10) % 10;
      final barcode = '$firstTwelve$checkDigit';
      if (!existing.contains(barcode)) return barcode;
    }

    throw StateError('No se pudo generar un código EAN-13 único.');
  }
}
