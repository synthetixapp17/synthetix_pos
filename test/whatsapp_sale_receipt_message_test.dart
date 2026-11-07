import 'dart:io';

import 'package:billing_app/core/data/hive_database.dart';
import 'package:billing_app/features/billing/data/whatsapp_sale_receipt_message.dart';
import 'package:billing_app/features/reports/domain/entities/sale_record.dart';
import 'package:billing_app/features/shop/domain/entities/shop.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('whatsapp-receipt-test-');
    Hive.init(directory.path);
    await Hive.openBox(HiveDatabase.settingsBoxName);
  });

  tearDown(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  test(
    'builds a professional receipt message without folio or exchange rate',
    () {
      final sale = SaleRecord(
        id: 'private-sale-folio-123',
        soldAt: DateTime(2026, 11, 7, 10, 15),
        total: 200,
        exchangeRate: 40,
        currencyCode: 'VES',
        paymentMethod: 'Tarjeta',
        lines: const [
          SaleLine(
            productId: 'coffee',
            productName: 'Café',
            quantity: 2,
            unitPrice: 100,
          ),
        ],
      );

      final message = buildWhatsappSaleReceiptMessage(
        sale: sale,
        shop: const Shop(name: 'Café Central'),
      );

      expect(message, contains('*Café Central*'));
      expect(message, contains('*COMPROBANTE DE VENTA*'));
      expect(message, contains('Fecha: 07/11/2026 10:15'));
      expect(message, contains('• Café'));
      expect(message, contains('2 × Bs. 100,00'));
      expect(message, contains('Subtotal: Bs. 200,00 (Ref. \$ 5,00)'));
      expect(message, contains('Forma de pago: Tarjeta'));
      expect(message, contains('*TOTAL A PAGAR*\n*Bs. 200,00*\nRef. \$ 5,00'));
      expect(message, isNot(contains(sale.id)));
      expect(message, isNot(contains('Tasa')));
      expect(message, isNot(contains('40')));
    },
  );
}
