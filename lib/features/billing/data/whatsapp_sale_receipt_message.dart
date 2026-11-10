import 'package:intl/intl.dart';

import '../../../core/utils/app_currency.dart';
import '../../reports/domain/entities/sale_record.dart';
import '../../shop/domain/entities/shop.dart';

String buildWhatsappSaleReceiptMessage({
  required SaleRecord sale,
  required Shop shop,
}) {
  final shopName = shop.name.trim().isEmpty ? 'MI TIENDA' : shop.name.trim();
  final message = StringBuffer()
    ..writeln('*$shopName*')
    ..writeln('*COMPROBANTE DE VENTA*')
    ..writeln('━━━━━━━━━━━━━━━━━━━━')
    ..writeln('Fecha: ${DateFormat('dd/MM/yyyy HH:mm').format(sale.soldAt)}')
    ..writeln()
    ..writeln('*PRODUCTOS*');

  for (final line in sale.lines) {
    message
      ..writeln(
        '• ${line.productName.trim()}'
        '${line.variationLabel.isEmpty ? '' : ' · ${line.variationLabel}'}',
      )
      ..writeln(
        '  ${line.displayQuantity}${line.unitLabel == 'ud.' ? '' : ' ${line.unitLabel}'} × '
        '${AppCurrency.format(line.unitPrice, code: sale.currencyCode)}',
      )
      ..writeln(
        '  Subtotal: ${AppCurrency.format(line.total, code: sale.currencyCode)}'
        ' (${AppCurrency.formatReference(line.total / sale.exchangeRate)})',
      );
  }

  message
    ..writeln()
    ..writeln('Forma de pago: ${sale.paymentMethod}')
    ..writeln('━━━━━━━━━━━━━━━━━━━━')
    ..writeln('*TOTAL A PAGAR*')
    ..writeln('*${AppCurrency.format(sale.total, code: sale.currencyCode)}*')
    ..write(AppCurrency.formatReference(sale.total / sale.exchangeRate));

  return message.toString().trimRight();
}
