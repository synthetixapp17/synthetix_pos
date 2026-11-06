import 'package:billing_app/core/utils/receipt_qr.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
