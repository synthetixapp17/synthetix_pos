import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../domain/entities/quotation.dart';

class QuotationPdf {
  static Future<Uint8List> build({
    required QuotationRecord quotation,
    required String template,
    required int primaryColor,
    required int accentColor,
  }) async {
    final fontData = await rootBundle.load('assets/fonts/Roboto.ttf');
    final font = pw.Font.ttf(ByteData.sublistView(fontData));
    final document = pw.Document(
      theme: pw.ThemeData.withFont(base: font, bold: font),
    );
    final primary = _pdfColor(primaryColor);
    final accent = _pdfColor(accentColor);
    final isMinimal = template == 'Minimal';
    final isProfessional = template == 'Profesional';

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(42),
        build: (context) => [
          pw.Container(
            padding: const pw.EdgeInsets.all(22),
            decoration: pw.BoxDecoration(
              color: isMinimal || isProfessional ? PdfColors.white : primary,
              borderRadius: isProfessional
                  ? null
                  : pw.BorderRadius.circular(12),
              border: isMinimal
                  ? pw.Border.all(color: PdfColors.grey300)
                  : isProfessional
                  ? pw.Border(left: pw.BorderSide(color: accent, width: 5))
                  : null,
            ),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        quotation.shopName.isEmpty
                            ? 'MI TIENDA'
                            : quotation.shopName.toUpperCase(),
                        style: pw.TextStyle(
                          color: isMinimal || isProfessional
                              ? primary
                              : PdfColors.white,
                          fontSize: 20,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(height: 8),
                      pw.Text(
                        'COTIZACIÓN',
                        style: pw.TextStyle(
                          color: isMinimal || isProfessional
                              ? accent
                              : PdfColors.white,
                          fontSize: isProfessional ? 15 : 12,
                          fontWeight: pw.FontWeight.bold,
                          letterSpacing: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      quotation.id,
                      style: pw.TextStyle(
                        color: isMinimal || isProfessional
                            ? PdfColors.grey700
                            : PdfColors.white,
                        fontSize: 9,
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      _formatDate(quotation.createdAt),
                      style: pw.TextStyle(
                        color: isMinimal || isProfessional
                            ? PdfColors.grey700
                            : PdfColors.white,
                        fontSize: 9,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 22),
          if (quotation.customerName.isNotEmpty) ...[
            pw.Text(
              'Preparado para',
              style: pw.TextStyle(color: PdfColors.grey600, fontSize: 10),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              quotation.customerName,
              style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 18),
          ],
          pw.TableHelper.fromTextArray(
            headers: ['Producto', 'Cant.', 'Precio', 'Importe'],
            data: [
              for (final line in quotation.lines)
                [
                  line.productName,
                  '${line.quantity}',
                  _moneyWithReference(
                    line.unitPrice,
                    quotation.currencyCode,
                    quotation.exchangeRate,
                  ),
                  _moneyWithReference(
                    line.total,
                    quotation.currencyCode,
                    quotation.exchangeRate,
                  ),
                ],
            ],
            headerDecoration: pw.BoxDecoration(
              color: isMinimal ? _lighten(accent, 0.84) : accent,
            ),
            headerStyle: pw.TextStyle(
              color: isMinimal ? primary : PdfColors.white,
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
            ),
            cellStyle: const pw.TextStyle(fontSize: 9),
            cellPadding: const pw.EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 10,
            ),
            border: pw.TableBorder(
              horizontalInside: pw.BorderSide(color: PdfColors.grey300),
            ),
            columnWidths: {
              0: const pw.FlexColumnWidth(4),
              1: const pw.FlexColumnWidth(0.8),
              2: const pw.FlexColumnWidth(1.7),
              3: const pw.FlexColumnWidth(1.7),
            },
          ),
          pw.SizedBox(height: 18),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Container(
              width: 220,
              padding: const pw.EdgeInsets.all(14),
              decoration: pw.BoxDecoration(
                color: isMinimal
                    ? _lighten(accent, 0.9)
                    : isProfessional
                    ? primary
                    : _lighten(accent, 0.88),
                borderRadius: pw.BorderRadius.circular(8),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'TOTAL',
                    style: pw.TextStyle(
                      color: isProfessional ? PdfColors.white : primary,
                      fontSize: 11,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.Text(
                    _moneyWithReference(
                      quotation.total,
                      quotation.currencyCode,
                      quotation.exchangeRate,
                    ),
                    style: pw.TextStyle(
                      color: isProfessional ? PdfColors.white : primary,
                      fontSize: 13,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
          pw.SizedBox(height: 32),
          pw.Text(
            'Tasa aplicada: 1 USD = ${quotation.exchangeRate} ${quotation.currencyCode}',
            textAlign: pw.TextAlign.right,
            style: const pw.TextStyle(color: PdfColors.grey600, fontSize: 9),
          ),
          pw.SizedBox(height: 12),
          pw.Divider(color: PdfColors.grey300),
          pw.Text(
            'Documento de cotización. No representa una venta ni una factura.',
            textAlign: pw.TextAlign.center,
            style: const pw.TextStyle(color: PdfColors.grey600, fontSize: 9),
          ),
        ],
      ),
    );
    return document.save();
  }

  static PdfColor _pdfColor(int color) => PdfColor(
    ((color >> 16) & 0xFF) / 255,
    ((color >> 8) & 0xFF) / 255,
    (color & 0xFF) / 255,
  );

  static PdfColor _lighten(PdfColor color, double amount) => PdfColor(
    color.red + (1 - color.red) * amount,
    color.green + (1 - color.green) * amount,
    color.blue + (1 - color.blue) * amount,
  );

  static String _moneyWithReference(
    double amount,
    String code,
    double exchangeRate,
  ) =>
      '$code ${amount.toStringAsFixed(2)}\n'
      'Ref. USD ${(amount / exchangeRate).toStringAsFixed(2)}';

  static String _formatDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/${date.year}';
}
