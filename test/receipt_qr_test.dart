import 'package:billing_app/core/utils/receipt_qr.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('builds a GitHub Pages lookup link for a sale ID', () {
    expect(
      ReceiptQr.saleUrl('sale-123'),
      'https://synthetixapp17.github.io/synthetix_pos/'
      '#/reports?saleId=sale-123',
    );
  });

  test('encodes sale IDs as a query parameter', () {
    expect(
      Uri.parse(ReceiptQr.saleUrl('sale/123?')),
      Uri.parse(
        'https://synthetixapp17.github.io/synthetix_pos/'
        '#/reports?saleId=sale%2F123%3F',
      ),
    );
  });
}
