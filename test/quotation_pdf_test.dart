import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:billing_app/features/settings/data/quotation_pdf.dart';
import 'package:billing_app/features/settings/domain/entities/quotation.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('generates a readable quotation PDF with line totals', () async {
    final quotation = QuotationRecord(
      id: 'TEST-001',
      createdAt: DateTime(2026, 10, 31),
      customerName: 'José Núñez',
      shopName: 'Café Bogotá',
      currencyCode: 'USD',
      lines: const [
        QuotationLine(
          productName: 'Café molido',
          barcode: '123456',
          quantity: 2,
          unitPrice: 12.5,
        ),
      ],
    );

    final bytes = await QuotationPdf.build(
      quotation: quotation,
      template: 'Clásica',
      primaryColor: 0xFF2E7D6F,
      accentColor: 0xFF00BFA5,
    );
    final minimalBytes = await QuotationPdf.build(
      quotation: quotation,
      template: 'Minimal',
      primaryColor: 0xFF2E7D6F,
      accentColor: 0xFF00BFA5,
    );
    final professionalBytes = await QuotationPdf.build(
      quotation: quotation,
      template: 'Profesional',
      primaryColor: 0xFF2E7D6F,
      accentColor: 0xFF00BFA5,
    );

    expect(latin1.decode(bytes.take(5).toList()), '%PDF-');
    expect(bytes, isNot(equals(minimalBytes)));
    expect(bytes, isNot(equals(professionalBytes)));
    expect(minimalBytes, isNot(equals(professionalBytes)));
    expect(quotation.total, 25);
  });
}
