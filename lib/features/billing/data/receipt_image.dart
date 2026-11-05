import 'dart:convert';

import 'package:barcode_widget/barcode_widget.dart' show Barcode;
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../core/utils/app_currency.dart';
import '../../reports/domain/entities/sale_record.dart';

class ReceiptImage {
  static const _navy = PdfColor(0.08, 0.16, 0.29);
  static const _blue = PdfColor(0.13, 0.36, 0.72);
  static const _muted = PdfColor(0.40, 0.45, 0.53);
  static const _light = PdfColor(0.94, 0.96, 0.98);

  static Future<Uint8List> build({
    required SaleRecord sale,
    required String shopName,
    required String address,
    required String shopPhone,
    required String rif,
    required String qrData,
    required String? logoData,
    required String footer,
    required bool showAddress,
    required bool showPhone,
    required bool showRif,
    required bool showInvoiceQr,
    required bool showDate,
    required bool showBarcode,
    required bool showUnitPrices,
  }) async {
    final fontData = await rootBundle.load('assets/fonts/Roboto.ttf');
    final font = pw.Font.ttf(ByteData.sublistView(fontData));
    final document = pw.Document(
      theme: pw.ThemeData.withFont(base: font, bold: font),
    );
    final logo = logoData == null || logoData.isEmpty
        ? null
        : pw.MemoryImage(base64Decode(logoData));
    final pageHeight =
        540 + sale.lines.length * 68.0 + (showInvoiceQr ? 130 : 0);
    document.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(420, pageHeight, marginAll: 0),
        build: (context) => pw.Container(
          color: PdfColors.white,
          padding: const pw.EdgeInsets.fromLTRB(30, 28, 30, 24),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              if (logo != null) ...[
                pw.Center(
                  child: pw.Image(logo, height: 62, fit: pw.BoxFit.contain),
                ),
                pw.SizedBox(height: 12),
              ],
              pw.Text(
                shopName.isEmpty ? 'MI TIENDA' : shopName.toUpperCase(),
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                  color: _navy,
                  fontSize: 20,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 5),
              pw.Text(
                'COMPROBANTE DE COMPRA',
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                  color: _blue,
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                  letterSpacing: 1.4,
                ),
              ),
              if (showAddress && address.trim().isNotEmpty) ...[
                pw.SizedBox(height: 8),
                pw.Text(
                  address,
                  textAlign: pw.TextAlign.center,
                  style: const pw.TextStyle(color: _muted, fontSize: 9),
                ),
              ],
              if (showPhone && shopPhone.trim().isNotEmpty)
                pw.Text(
                  shopPhone,
                  textAlign: pw.TextAlign.center,
                  style: const pw.TextStyle(color: _muted, fontSize: 9),
                ),
              if (showRif && rif.trim().isNotEmpty)
                pw.Text(
                  'RIF: ${rif.trim()}',
                  textAlign: pw.TextAlign.center,
                  style: const pw.TextStyle(color: _muted, fontSize: 9),
                ),
              pw.SizedBox(height: 18),
              pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  color: _light,
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('Folio: ${_shortId(sale.id)}'),
                    if (showDate) ...[
                      pw.SizedBox(height: 4),
                      pw.Text(_formatDate(sale.soldAt)),
                    ],
                    if (sale.customerName?.trim().isNotEmpty ?? false) ...[
                      pw.SizedBox(height: 4),
                      pw.Text('Cliente: ${sale.customerName}'),
                    ],
                    pw.SizedBox(height: 4),
                    pw.Text('Forma de pago: ${sale.paymentMethod}'),
                  ],
                ),
              ),
              pw.SizedBox(height: 18),
              pw.Row(
                children: [
                  pw.Expanded(
                    child: pw.Text(
                      'PRODUCTO',
                      style: pw.TextStyle(
                        color: _muted,
                        fontSize: 9,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ),
                  pw.SizedBox(
                    width: 100,
                    child: pw.Text(
                      'IMPORTE',
                      textAlign: pw.TextAlign.right,
                      style: pw.TextStyle(
                        color: _muted,
                        fontSize: 9,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 6),
              pw.Divider(color: PdfColors.grey300),
              for (final line in sale.lines) ...[
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 7),
                  child: pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Expanded(
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(
                              line.productName,
                              style: pw.TextStyle(
                                color: _navy,
                                fontSize: 10,
                                fontWeight: pw.FontWeight.bold,
                              ),
                            ),
                            pw.SizedBox(height: 3),
                            pw.Text(
                              showUnitPrices
                                  ? '${line.quantity} × ${_money(line.unitPrice, sale.currencyCode)}'
                                  : '${line.quantity} unidades',
                              style: const pw.TextStyle(
                                color: _muted,
                                fontSize: 9,
                              ),
                            ),
                            if (showBarcode && line.barcode.isNotEmpty) ...[
                              pw.SizedBox(height: 3),
                              pw.Text(
                                'Código: ${line.barcode}',
                                style: const pw.TextStyle(
                                  color: _muted,
                                  fontSize: 8,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      pw.SizedBox(width: 12),
                      pw.SizedBox(
                        width: 100,
                        child: pw.Text(
                          _money(line.total, sale.currencyCode),
                          textAlign: pw.TextAlign.right,
                          style: pw.TextStyle(
                            color: _navy,
                            fontSize: 10,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                pw.Divider(color: PdfColors.grey200),
              ],
              pw.SizedBox(height: 10),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'TOTAL',
                    style: pw.TextStyle(
                      color: _navy,
                      fontSize: 13,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.Text(
                    _money(sale.total, sale.currencyCode),
                    style: pw.TextStyle(
                      color: _blue,
                      fontSize: 16,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ],
              ),
              if (sale.paymentMethod.toLowerCase() == 'efectivo' &&
                  sale.amountTendered > 0) ...[
                pw.SizedBox(height: 12),
                _amountRow(
                  'Efectivo recibido',
                  _money(sale.amountTendered, sale.currencyCode),
                ),
                pw.SizedBox(height: 5),
                _amountRow(
                  'Vuelto',
                  _money(sale.changeAmount, sale.currencyCode),
                  emphasize: true,
                ),
              ],
              if (footer.trim().isNotEmpty) ...[
                pw.SizedBox(height: 22),
                pw.Divider(color: PdfColors.grey300),
                pw.SizedBox(height: 10),
                pw.Text(
                  footer,
                  textAlign: pw.TextAlign.center,
                  style: const pw.TextStyle(color: _muted, fontSize: 9),
                ),
              ],
              if (showInvoiceQr) ...[
                pw.SizedBox(height: 14),
                pw.Center(
                  child: pw.BarcodeWidget(
                    barcode: Barcode.qrCode(),
                    data: qrData,
                    width: 92,
                    height: 92,
                    drawText: false,
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  'Escanea para consultar esta venta',
                  textAlign: pw.TextAlign.center,
                  style: const pw.TextStyle(color: _muted, fontSize: 8),
                ),
              ],
              pw.SizedBox(height: 12),
              pw.Text(
                'Gracias por su compra',
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                  color: _blue,
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final page = await Printing.raster(await document.save(), dpi: 180).first;
    return page.toPng();
  }

  static pw.Widget _amountRow(
    String label,
    String value, {
    bool emphasize = false,
  }) => pw.Row(
    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
    children: [
      pw.Text(
        label,
        style: pw.TextStyle(
          color: emphasize ? _navy : _muted,
          fontSize: 10,
          fontWeight: emphasize ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
      pw.Text(
        value,
        style: pw.TextStyle(
          color: emphasize ? _blue : _navy,
          fontSize: 10,
          fontWeight: pw.FontWeight.bold,
        ),
      ),
    ],
  );

  static String _money(double amount, String code) =>
      AppCurrency.format(amount, code: code);

  static String _shortId(String id) =>
      id.substring(0, id.length > 8 ? 8 : id.length);

  static String _formatDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/${date.year} '
      '${date.hour.toString().padLeft(2, '0')}:'
      '${date.minute.toString().padLeft(2, '0')}';
}
