import 'package:billing_app/core/utils/receipt_qr.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('receipt QR contains a private notice instead of a public URL', () {
    expect(ReceiptQr.privateReceiptData, contains('Comprobante privado'));
    expect(ReceiptQr.privateReceiptData, contains('solo está disponible'));
    expect(ReceiptQr.privateReceiptData, isNot(contains('http')));
    expect(ReceiptQr.privateReceiptData, isNot(contains('saleId')));
  });
}
