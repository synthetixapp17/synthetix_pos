import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../reports/domain/entities/sale_record.dart';

Future<void> generarContratoCredito(Map<String, dynamic> datos) async {
  final bytes = await buildCreditContractPdf(datos);
  final contractNumber = _contractNumber(datos['fechaEmision']);
  await Printing.layoutPdf(
    name: 'contrato-credito-$contractNumber.pdf',
    onLayout: (_) async => bytes,
  );
}

/// Builds the contract using `empresa`, `cliente`, `productos`,
/// `abonoInicial`, `numeroCuotas` and `diasPlazo` in [datos].
/// It reads only the provided map and local font asset; it does not access storage.
class CreditPdf {
  static Future<Uint8List> build({
    required SaleRecord sale,
    required String shopName,
    required String customerName,
    required String customerPhone,
    required String customerEmail,
    required String customerAddress,
    required double initialPayment,
    int numberOfInstallments = 1,
    int daysBetweenPayments = 30,
    String customerIdentity = '',
    String shopAddress = '',
    String shopPhone = '',
    String shopTaxId = '',
    String representativeName = '',
    String representativeTitle = 'Representante legal',
    String terms = '',
    String? logoData,
  }) => buildCreditContractPdf({
    'empresa': {
      'nombre': shopName,
      'direccion': shopAddress,
      'telefono': shopPhone,
      'rif': shopTaxId,
      'logoBase64': logoData,
    },
    'cliente': {
      'nombre': customerName,
      'cedulaRif': customerIdentity,
      'telefono': customerPhone,
      'direccion': customerAddress,
      'correo': customerEmail,
    },
    'productos': [
      for (final line in sale.lines)
        {
          'cantidad': line.quantity,
          'descripcion': line.productName,
          'precioUnitario': line.unitPrice,
        },
    ],
    'totalVenta': sale.total,
    'abonoInicial': initialPayment,
    'numeroCuotas': numberOfInstallments,
    'diasPlazo': daysBetweenPayments,
    'fechaEmision': sale.soldAt,
    'moneda': sale.currencyCode,
    'representanteNombre': representativeName,
    'representanteCargo': representativeTitle,
    'condiciones': terms,
  });
}

Future<Uint8List> buildCreditContractPdf(Map<String, dynamic> datos) async {
  final company = _requiredMap(datos, 'empresa');
  final customer = _requiredMap(datos, 'cliente');
  final products = _requiredProducts(datos);
  final issuedAt = _readDate(datos['fechaEmision']) ?? DateTime.now();
  final contractNumber = _text(datos['numeroContrato']).trim().isNotEmpty
      ? _text(datos['numeroContrato'])
      : _contractNumber(issuedAt);
  final currencyCode = _text(datos['moneda'], fallback: 'USD');
  final total = _number(
    datos['totalVenta'],
    fallback: _productsTotal(products),
  );
  final initialPayment = _number(datos['abonoInicial'], fallback: 0);
  final installments = _integer(datos['numeroCuotas']);
  final daysBetweenPayments = _integer(datos['diasPlazo']);

  if (total <= 0) {
    throw ArgumentError.value(total, 'totalVenta', 'Debe ser mayor que cero.');
  }
  if (initialPayment < 0 || initialPayment > total) {
    throw ArgumentError.value(
      initialPayment,
      'abonoInicial',
      'Debe estar entre cero y el total de la venta.',
    );
  }
  if (installments < 1) {
    throw ArgumentError.value(
      installments,
      'numeroCuotas',
      'Debe ser al menos una cuota.',
    );
  }
  if (daysBetweenPayments < 0) {
    throw ArgumentError.value(
      daysBetweenPayments,
      'diasPlazo',
      'No puede ser negativo.',
    );
  }

  final financedAmount = total - initialPayment;
  final installmentAmount = financedAmount / installments;
  final firstPaymentDate = issuedAt.add(Duration(days: daysBetweenPayments));
  final finalDueDate = issuedAt.add(
    Duration(days: daysBetweenPayments * installments),
  );
  final money = NumberFormat('#,##0.00', 'es');
  String formatMoney(num amount) =>
      '${_currencySymbol(currencyCode)} ${money.format(amount)}';
  final date = DateFormat('dd/MM/yyyy', 'es');
  final dateTime = DateFormat('dd/MM/yyyy HH:mm', 'es');
  final fontData = await rootBundle.load('assets/fonts/Roboto.ttf');
  final font = pw.Font.ttf(ByteData.sublistView(fontData));
  final document = pw.Document(
    theme: pw.ThemeData.withFont(base: font, bold: font),
  );
  final logo = _readLogo(company['logoBytes'] ?? company['logoBase64']);
  final terms = _text(
    datos['condiciones'],
    fallback:
        'El cliente se compromete a pagar la cuota N° [ ] antes del día [ ] '
        'de cada mes. En caso de mora, se aplicará un recargo del [ ]% '
        'conforme a las condiciones acordadas entre las partes. '
        'Las partes declaran haber leído y aceptado las condiciones de esta venta.',
  );
  final companyName = _text(company['nombre'], fallback: 'MI EMPRESA');
  final customerName = _text(customer['nombre'], fallback: 'Cliente');
  final footerAddress = _text(company['direccion']);
  final footerPhone = _text(company['telefono']);
  final pageFormat = _text(datos['tamanoPapel']).toLowerCase() == 'carta'
      ? PdfPageFormat.letter
      : PdfPageFormat.a4;

  document.addPage(
    pw.MultiPage(
      pageFormat: pageFormat,
      margin: const pw.EdgeInsets.fromLTRB(38, 34, 38, 42),
      footer: (context) => pw.Column(
        children: [
          pw.Divider(color: PdfColors.grey300),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Expanded(
                child: pw.Text(
                  [
                    if (footerAddress.isNotEmpty) footerAddress,
                    if (footerPhone.isNotEmpty) footerPhone,
                    'Gracias por su confianza.',
                  ].join('  ·  '),
                  style: const pw.TextStyle(
                    color: PdfColors.grey700,
                    fontSize: 8,
                  ),
                ),
              ),
              pw.Text(
                '${context.pageNumber} / ${context.pagesCount}',
                style: const pw.TextStyle(
                  color: PdfColors.grey700,
                  fontSize: 8,
                ),
              ),
            ],
          ),
        ],
      ),
      build: (context) => [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.SizedBox(
              width: 116,
              child: logo == null
                  ? pw.Container(
                      height: 54,
                      alignment: pw.Alignment.centerLeft,
                      child: pw.Text(
                        companyName,
                        maxLines: 2,
                        style: pw.TextStyle(
                          color: PdfColor.fromHex('#174B3B'),
                          fontSize: 13,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    )
                  : pw.Container(
                      height: 58,
                      alignment: pw.Alignment.centerLeft,
                      child: pw.Image(logo, fit: pw.BoxFit.contain),
                    ),
            ),
            pw.Expanded(
              child: pw.Text(
                'CONTRATO DE VENTA A CRÉDITO',
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                  color: PdfColor.fromHex('#12382D'),
                  fontSize: 15,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.SizedBox(
              width: 132,
              child: pw.Container(
                padding: const pw.EdgeInsets.all(8),
                decoration: pw.BoxDecoration(
                  color: PdfColor.fromHex('#F2F5F3'),
                  border: pw.Border.all(color: PdfColors.grey400),
                  borderRadius: pw.BorderRadius.circular(5),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'N° de Contrato',
                      style: const pw.TextStyle(fontSize: 8),
                    ),
                    pw.Text(
                      contractNumber,
                      style: pw.TextStyle(
                        fontSize: 10,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      'Fecha de emisión',
                      style: const pw.TextStyle(fontSize: 8),
                    ),
                    pw.Text(
                      dateTime.format(issuedAt),
                      style: pw.TextStyle(
                        fontSize: 9,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 16),
        _sectionTitle('DATOS DEL CLIENTE'),
        pw.SizedBox(height: 6),
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(12),
          decoration: pw.BoxDecoration(
            color: PdfColor.fromHex('#F3F4F6'),
            borderRadius: pw.BorderRadius.circular(7),
            border: pw.Border.all(color: PdfColors.grey300),
          ),
          child: pw.Column(
            children: [
              _infoRow(
                _infoCell('Nombre', customerName),
                _infoCell(
                  'Cédula / RIF',
                  _text(customer['cedulaRif'] ?? customer['identificacion']),
                ),
              ),
              pw.SizedBox(height: 9),
              _infoRow(
                _infoCell('Teléfono', _text(customer['telefono'])),
                _infoCell('Correo', _text(customer['correo'])),
              ),
              pw.SizedBox(height: 9),
              _infoRow(
                _infoCell('Dirección', _text(customer['direccion'])),
                _infoCell('Empresa / RIF', _text(company['rif'])),
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 16),
        _sectionTitle('DETALLE DE PRODUCTOS'),
        pw.SizedBox(height: 6),
        pw.TableHelper.fromTextArray(
          headers: const [
            'Cantidad',
            'Descripción',
            'Precio unitario',
            'Total',
          ],
          data: [
            for (final product in products)
              [
                '${product.quantity}',
                product.description,
                formatMoney(product.unitPrice),
                formatMoney(product.total),
              ],
          ],
          headerDecoration: pw.BoxDecoration(
            color: PdfColor.fromHex('#174B3B'),
          ),
          headerStyle: pw.TextStyle(
            color: PdfColors.white,
            fontSize: 8,
            fontWeight: pw.FontWeight.bold,
          ),
          cellStyle: const pw.TextStyle(fontSize: 8),
          cellPadding: const pw.EdgeInsets.symmetric(
            horizontal: 7,
            vertical: 8,
          ),
          border: pw.TableBorder(
            horizontalInside: pw.BorderSide(color: PdfColors.grey300),
            bottom: pw.BorderSide(color: PdfColors.grey400),
          ),
          columnWidths: {
            0: const pw.FlexColumnWidth(0.9),
            1: const pw.FlexColumnWidth(3.4),
            2: const pw.FlexColumnWidth(1.5),
            3: const pw.FlexColumnWidth(1.5),
          },
          cellAlignments: {
            0: pw.Alignment.center,
            1: pw.Alignment.centerLeft,
            2: pw.Alignment.centerRight,
            3: pw.Alignment.centerRight,
          },
        ),
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          decoration: pw.BoxDecoration(
            color: PdfColor.fromHex('#F2F5F3'),
            border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey400)),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.end,
            children: [
              pw.Text(
                'TOTAL DE LA VENTA',
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(width: 24),
              pw.Text(
                formatMoney(total),
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 16),
        _sectionTitle('RESUMEN DEL CRÉDITO'),
        pw.SizedBox(height: 6),
        pw.Container(
          padding: const pw.EdgeInsets.all(13),
          decoration: pw.BoxDecoration(
            color: PdfColor.fromHex('#F4F8F5'),
            borderRadius: pw.BorderRadius.circular(8),
            border: pw.Border.all(
              color: PdfColor.fromHex('#39765B'),
              width: 1.2,
            ),
          ),
          child: pw.Column(
            children: [
              _summaryRow(
                'Abono inicial',
                formatMoney(initialPayment),
                bold: true,
              ),
              _summaryRow('Monto financiado', formatMoney(financedAmount)),
              _summaryRow('Número de cuotas', '$installments'),
              _summaryRow(
                'Valor de cada cuota',
                formatMoney(installmentAmount),
              ),
              _summaryRow(
                'Fecha de primer pago',
                date.format(firstPaymentDate),
              ),
              _summaryRow(
                'Fecha de vencimiento final',
                date.format(finalDueDate),
                bold: true,
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 16),
        _sectionTitle('CLÁUSULAS Y CONDICIONES'),
        pw.SizedBox(height: 6),
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(12),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey400),
            borderRadius: pw.BorderRadius.circular(6),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                terms,
                style: const pw.TextStyle(fontSize: 9, lineSpacing: 3),
              ),
              pw.SizedBox(height: 12),
              for (var index = 0; index < 3; index++) ...[
                pw.Container(height: 1, color: PdfColors.grey400),
                pw.SizedBox(height: 13),
              ],
            ],
          ),
        ),
        pw.SizedBox(height: 28),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Expanded(
              child: _signatureBlock(
                title: 'FIRMA DEL CLIENTE',
                name: customerName,
                detail:
                    'Cédula / RIF: ${_text(customer['cedulaRif'] ?? customer['identificacion'], fallback: '________________')}',
              ),
            ),
            pw.SizedBox(width: 28),
            pw.Expanded(
              child: _signatureBlock(
                title: 'FIRMA DEL REPRESENTANTE LEGAL',
                name: _text(
                  datos['representanteNombre'],
                  fallback: '____________________________',
                ),
                detail:
                    '${_text(datos['representanteCargo'], fallback: 'Cargo')}: $companyName',
              ),
            ),
          ],
        ),
      ],
    ),
  );

  return document.save();
}

pw.Widget _sectionTitle(String title) => pw.Text(
  title,
  style: pw.TextStyle(
    color: PdfColor.fromHex('#174B3B'),
    fontSize: 9,
    fontWeight: pw.FontWeight.bold,
    letterSpacing: 0.6,
  ),
);

pw.Widget _infoCell(String label, String value) => pw.Expanded(
  child: pw.RichText(
    text: pw.TextSpan(
      children: [
        pw.TextSpan(
          text: '$label: ',
          style: pw.TextStyle(
            color: PdfColors.grey700,
            fontSize: 8,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.TextSpan(
          text: value.isEmpty ? '—' : value,
          style: const pw.TextStyle(fontSize: 9),
        ),
      ],
    ),
  ),
);

pw.Widget _infoRow(pw.Widget left, pw.Widget right) => pw.Row(
  crossAxisAlignment: pw.CrossAxisAlignment.start,
  children: [left, pw.SizedBox(width: 16), right],
);

pw.Widget _summaryRow(String label, String value, {bool bold = false}) =>
    pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 4),
      child: pw.Row(
        children: [
          pw.Expanded(
            child: pw.Text(
              label,
              style: pw.TextStyle(
                fontSize: 9,
                fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
              ),
            ),
          ),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 9,
              fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
          ),
        ],
      ),
    );

pw.Widget _signatureBlock({
  required String title,
  required String name,
  required String detail,
}) => pw.Column(
  children: [
    pw.Container(height: 1, color: PdfColors.grey700),
    pw.SizedBox(height: 7),
    pw.Text(
      title,
      textAlign: pw.TextAlign.center,
      style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
    ),
    pw.SizedBox(height: 4),
    pw.Text(
      name,
      textAlign: pw.TextAlign.center,
      style: const pw.TextStyle(fontSize: 8),
    ),
    pw.Text(
      detail,
      textAlign: pw.TextAlign.center,
      style: const pw.TextStyle(fontSize: 8),
    ),
  ],
);

class _CreditProduct {
  final int quantity;
  final String description;
  final double unitPrice;

  const _CreditProduct({
    required this.quantity,
    required this.description,
    required this.unitPrice,
  });

  double get total => quantity * unitPrice;
}

Map<String, dynamic> _requiredMap(Map<String, dynamic> source, String key) {
  final value = source[key];
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return value.map((key, value) => MapEntry('$key', value));
  throw ArgumentError.value(value, key, 'Debe ser un mapa de datos.');
}

List<_CreditProduct> _requiredProducts(Map<String, dynamic> datos) {
  final source = datos['productos'];
  if (source is! List || source.isEmpty) {
    throw ArgumentError.value(
      source,
      'productos',
      'Debe contener al menos un producto.',
    );
  }
  return source.map((value) {
    if (value is! Map) {
      throw ArgumentError.value(
        value,
        'productos',
        'Cada producto debe ser un mapa.',
      );
    }
    final product = value.map((key, value) => MapEntry('$key', value));
    final quantity = _integer(product['cantidad']);
    final description = _text(product['descripcion']);
    final unitPrice = _number(product['precioUnitario']);
    if (quantity < 1 || description.isEmpty || unitPrice < 0) {
      throw ArgumentError.value(
        value,
        'productos',
        'Cada producto requiere cantidad, descripción y precio válidos.',
      );
    }
    return _CreditProduct(
      quantity: quantity,
      description: description,
      unitPrice: unitPrice,
    );
  }).toList();
}

double _productsTotal(List<_CreditProduct> products) =>
    products.fold(0, (total, product) => total + product.total);

String _text(Object? value, {String fallback = ''}) =>
    value?.toString().trim() ?? fallback;

double _number(Object? value, {double? fallback}) {
  if (value == null) {
    if (fallback != null) return fallback;
    throw ArgumentError.value(value, 'monto', 'Debe ser un número válido.');
  }
  if (value is num) return value.toDouble();
  if (value is String) {
    final normalized = value.trim().replaceAll(',', '.');
    if (normalized.isEmpty && fallback != null) return fallback;
    final parsed = double.tryParse(normalized);
    if (parsed != null) return parsed;
  }
  throw ArgumentError.value(value, 'monto', 'Debe ser un número válido.');
}

int _integer(Object? value) {
  if (value is int) return value;
  if (value is num && value == value.toInt()) return value.toInt();
  if (value is String) {
    final parsed = int.tryParse(value.trim());
    if (parsed != null) return parsed;
  }
  throw ArgumentError.value(value, 'entero', 'Debe ser un número entero.');
}

DateTime? _readDate(Object? value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  if (value is String) {
    final parsed = DateTime.tryParse(value);
    if (parsed != null) return parsed;
  }
  throw ArgumentError.value(value, 'fecha', 'Debe ser DateTime o ISO-8601.');
}

String _contractNumber(Object? dateValue) {
  final date = _readDate(dateValue) ?? DateTime.now();
  final timestamp =
      '${date.year.toString().padLeft(4, '0')}'
      '${date.month.toString().padLeft(2, '0')}'
      '${date.day.toString().padLeft(2, '0')}'
      '${date.hour.toString().padLeft(2, '0')}'
      '${date.minute.toString().padLeft(2, '0')}'
      '${date.second.toString().padLeft(2, '0')}'
      '${date.millisecond.toString().padLeft(3, '0')}';
  return 'CC-$timestamp';
}

pw.MemoryImage? _readLogo(Object? source) {
  if (source is Uint8List) return pw.MemoryImage(source);
  if (source is List<int>) return pw.MemoryImage(Uint8List.fromList(source));
  if (source is String && source.trim().isNotEmpty) {
    final encoded = source.startsWith('data:')
        ? source.substring(source.indexOf(',') + 1)
        : source;
    return pw.MemoryImage(base64Decode(encoded));
  }
  return null;
}

String _currencySymbol(String code) => switch (code.toUpperCase()) {
  'USD' || 'CAD' || 'AUD' || 'COP' || 'MXN' || 'ARS' || 'CLP' || 'DOP' => r'$',
  'EUR' => '€',
  'INR' => '₹',
  'VES' => 'Bs.',
  'PEN' => 'S/',
  'GBP' => '£',
  'BRL' => r'R$',
  'JPY' => '¥',
  'CHF' => 'CHF',
  _ => code,
};
