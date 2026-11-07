import 'dart:convert';
import 'dart:typed_data';

import 'package:billing_app/core/utils/receipt_qr_image_decoder.dart';
import 'package:billing_app/core/utils/receipt_qr.dart';
import 'package:billing_app/core/utils/printer_helper.dart';
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

  test('thermal ticket QR stores the complete receipt payload', () {
    final payload = ReceiptQr.saleQrData('sale-123');
    final encoded = EscPos.qrCode(payload);
    final storeCommand = encoded.indexOf(0x50);
    final dataOffset = storeCommand + 2;
    final declaredLength =
        encoded[storeCommand - 3] | (encoded[storeCommand - 2] << 8);

    expect(
      encoded.sublist(dataOffset, dataOffset + payload.length),
      utf8.encode(payload),
    );
    expect(declaredLength, utf8.encode(payload).length + 3);
    expect(encoded, containsAllInOrder([0x31, 0x43, 0x05]));
    expect(encoded, containsAllInOrder([0x31, 0x45, 0x31]));
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

  test('finds and reads a receipt QR inside a larger image', () {
    const saleId = 'sale-embedded';
    final background = img.Image(width: 1200, height: 1600);
    img.fill(background, color: img.ColorRgb8(238, 238, 238));
    for (var y = 0; y < 900; y += 14) {
      img.drawLine(
        background,
        x1: 0,
        y1: y,
        x2: 1199,
        y2: y,
        color: img.ColorRgb8(210, 210, 210),
        thickness: 2,
      );
    }
    img.compositeImage(
      background,
      img.copyResize(_qrImage(data: ReceiptQr.saleQrData(saleId)), width: 300),
      dstX: 760,
      dstY: 1120,
    );

    final decoded = ReceiptQrImageDecoder.decode(
      Uint8List.fromList(img.encodePng(background)),
    );

    expect(ReceiptQr.saleIdFromData(decoded), saleId);
  });
}

img.Image _qrImage({String? data, bool inverted = false}) {
  const scale = 8;
  const quietZone = 4;
  final code = QrCode.fromData(
    data: data ?? (inverted ? 'sale-inverted' : 'sale-rotated'),
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
