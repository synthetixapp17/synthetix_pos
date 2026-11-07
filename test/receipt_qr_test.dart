import 'dart:typed_data';

import 'package:billing_app/core/utils/receipt_qr_image_decoder.dart';
import 'package:billing_app/core/utils/receipt_qr.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:qr/qr.dart';

void main() {
  test('receipt QR contains only an encoded sale ID, not a public URL', () {
    final qrData = ReceiptQr.saleQrData('sale-123');

    expect(qrData, 'synthetix-sale:sale-123');
    expect(qrData, isNot(contains('http')));
    expect(qrData, isNot(contains('saleId')));
    expect(ReceiptQr.saleIdFromData(qrData), 'sale-123');
  });

  test('receipt QR encodes and decodes special characters in the sale ID', () {
    final qrData = ReceiptQr.saleQrData('sale/123?');

    expect(ReceiptQr.saleIdFromData(qrData), 'sale/123?');
  });

  test('reads sale IDs from legacy receipt URLs', () {
    expect(
      ReceiptQr.saleIdFromData(
        'https://synthetixapp17.github.io/synthetix_pos/'
        '#/reports?saleId=sale-123',
      ),
      'sale-123',
    );
  });

  test('does not interpret the private notice as a sale ID', () {
    expect(ReceiptQr.saleIdFromData(ReceiptQr.privateReceiptData), isNull);
  });

  test('reports when an image contains no readable QR code', () {
    final image = img.Image(width: 16, height: 16);
    final bytes = Uint8List.fromList(img.encodePng(image));

    expect(
      () => ReceiptQrImageDecoder.decode(bytes),
      throwsA(isA<FormatException>()),
    );
  });

  test('reads QR codes from rotated images', () {
    for (final angle in [90, 180, 270]) {
      final rotated = img.copyRotate(_qrImage(), angle: angle);
      final bytes = Uint8List.fromList(img.encodePng(rotated));

      expect(ReceiptQrImageDecoder.decode(bytes), 'sale-rotated');
    }
  });

  test('reads QR codes with inverted colors', () {
    final bytes = Uint8List.fromList(img.encodePng(_qrImage(inverted: true)));

    expect(ReceiptQrImageDecoder.decode(bytes), 'sale-inverted');
  });
}

img.Image _qrImage({bool inverted = false}) {
  const scale = 8;
  const quietZone = 4;
  final code = QrCode.fromData(
    data: inverted ? 'sale-inverted' : 'sale-rotated',
    errorCorrectLevel: QrErrorCorrectLevel.M,
  );
  final qrImage = QrImage(code);
  final size = (qrImage.moduleCount + quietZone * 2) * scale;
  final image = img.Image(width: size, height: size, numChannels: 3);

  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final row = y ~/ scale - quietZone;
      final column = x ~/ scale - quietZone;
      final isDark =
          row >= 0 &&
          row < qrImage.moduleCount &&
          column >= 0 &&
          column < qrImage.moduleCount &&
          qrImage.isDark(row, column);
      final darkPixel = isDark != inverted;
      final color = darkPixel ? 0 : 255;
      image.setPixelRgb(x, y, color, color, color);
    }
  }
  return image;
}
