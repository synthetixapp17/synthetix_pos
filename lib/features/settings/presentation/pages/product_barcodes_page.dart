import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../../core/data/hive_database.dart';
import '../../../../core/utils/printer_helper.dart';
import '../../../product/domain/entities/product.dart';
import '../../../product/presentation/bloc/product_bloc.dart';

class ProductBarcodesPage extends StatefulWidget {
  const ProductBarcodesPage({super.key});

  @override
  State<ProductBarcodesPage> createState() => _ProductBarcodesPageState();
}

class _ProductBarcodesPageState extends State<ProductBarcodesPage> {
  final Set<String> _selectedProductIds = {};
  bool _printing = false;
  bool _downloading = false;

  List<Product> _withBarcodes(Iterable<Product> products) =>
      products.where((product) => product.barcode.trim().isNotEmpty).toList();

  List<Product> _selectedOrAll(
    List<Product> products, {
    bool respectSelection = true,
  }) {
    final withBarcodes = _withBarcodes(products);
    if (!respectSelection || _selectedProductIds.isEmpty) return withBarcodes;
    return withBarcodes
        .where((product) => _selectedProductIds.contains(product.id))
        .toList();
  }

  Future<void> _downloadLabels(
    List<Product> products, {
    bool respectSelection = true,
  }) async {
    final downloadable = _selectedOrAll(
      products,
      respectSelection: respectSelection,
    );
    if (downloadable.isEmpty) {
      _notify('Selecciona productos con código de barras para descargar.');
      return;
    }

    setState(() => _downloading = true);
    try {
      final document = pw.Document();
      document.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(28),
          build: (_) => [
            pw.Text(
              'Etiquetas de códigos de barras',
              style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 18),
            pw.Wrap(
              spacing: 14,
              runSpacing: 14,
              children: [
                for (final product in downloadable)
                  pw.Container(
                    width: 250,
                    padding: const pw.EdgeInsets.all(12),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.grey400),
                      borderRadius: pw.BorderRadius.circular(8),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        pw.Text(
                          product.name,
                          textAlign: pw.TextAlign.center,
                          maxLines: 1,
                          style: pw.TextStyle(
                            fontSize: 11,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        if (product.category.trim().isNotEmpty) ...[
                          pw.SizedBox(height: 3),
                          pw.Text(
                            product.category,
                            style: const pw.TextStyle(
                              fontSize: 9,
                              color: PdfColors.grey700,
                            ),
                          ),
                        ],
                        pw.SizedBox(height: 10),
                        pw.BarcodeWidget(
                          barcode: Barcode.code128(),
                          data: product.barcode,
                          width: 220,
                          height: 66,
                          drawText: false,
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          product.barcode,
                          style: const pw.TextStyle(
                            fontSize: 9,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
      );
      final bytes = await document.save();
      final shared = await Printing.sharePdf(
        bytes: bytes,
        filename: 'etiquetas-codigos-de-barras.pdf',
      );
      if (mounted && !shared) {
        _notify(
          'El PDF se generó, pero no se pudo abrir la opción de descarga.',
        );
      }
    } catch (error) {
      _notify('No se pudieron generar las etiquetas PDF: $error');
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  Future<void> _printLabels(
    List<Product> products, {
    bool respectSelection = true,
  }) async {
    final printable = _selectedOrAll(
      products,
      respectSelection: respectSelection,
    );
    if (printable.isEmpty) {
      _notify('Selecciona productos con código de barras para imprimir.');
      return;
    }

    setState(() => _printing = true);
    var printedCount = 0;
    try {
      final printer = PrinterHelper();
      if (!await printer.checkConnection()) {
        final savedMac = HiveDatabase.settingsBox.get('printer_mac');
        if (savedMac is! String || savedMac.isEmpty) {
          throw const PrinterException(
            'No hay una impresora guardada. Configúrala en Ajustes de impresora.',
          );
        }
        if (!await printer.connect(savedMac)) {
          throw const PrinterException(
            'No se pudo conectar con la impresora guardada.',
          );
        }
      }

      for (final product in printable) {
        await printer.printBarcodeLabel(
          productName: product.name,
          barcode: product.barcode,
        );
        printedCount++;
      }
      if (mounted) _notify('$printedCount etiquetas enviadas a imprimir.');
    } catch (error) {
      if (mounted) {
        _notify(
          printedCount == 0
              ? 'No se pudieron imprimir los códigos: $error'
              : 'Se imprimieron $printedCount de ${printable.length} etiquetas. Error: $error',
        );
      }
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  void _notify(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surface,
        centerTitle: false,
        title: const Text(
          'Códigos de barras',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          BlocBuilder<ProductBloc, ProductState>(
            builder: (context, state) {
              final hasBarcodes = _withBarcodes(state.products).isNotEmpty;
              return Padding(
                padding: const EdgeInsets.only(right: 12),
                child: TextButton.icon(
                  onPressed: _downloading || !hasBarcodes
                      ? null
                      : () => _downloadLabels(
                          state.products,
                          respectSelection: false,
                        ),
                  icon: _downloading
                      ? const SizedBox(
                          width: 17,
                          height: 17,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.picture_as_pdf_outlined, size: 19),
                  label: const Text('Descargar todos'),
                  style: TextButton.styleFrom(foregroundColor: colors.primary),
                ),
              );
            },
          ),
        ],
      ),
      body: BlocBuilder<ProductBloc, ProductState>(
        builder: (context, state) {
          if (state.status == ProductStatus.loading && state.products.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state.products.isEmpty) {
            return const Center(
              child: Text('Aún no hay productos registrados.'),
            );
          }
          return LayoutBuilder(
            builder: (context, constraints) {
              final maxWidth = constraints.maxWidth
                  .clamp(0.0, 1100.0)
                  .toDouble();
              return Center(
                child: SizedBox(
                  width: maxWidth,
                  child: ListView(
                    padding: const EdgeInsets.all(18),
                    children: [
                      Card(
                        elevation: 0,
                        color: colors.surface,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(color: colors.outlineVariant),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Icon(
                                Icons.qr_code_2_rounded,
                                size: 32,
                                color: colors.primary,
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Text(
                                  'Selecciona productos para descargar sus etiquetas en PDF o imprimirlas en la impresora térmica.',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ),
                              IconButton(
                                tooltip:
                                    _selectedProductIds.length ==
                                        _withBarcodes(state.products).length
                                    ? 'Quitar selección'
                                    : 'Seleccionar todos',
                                onPressed: () => setState(() {
                                  final ids = _withBarcodes(
                                    state.products,
                                  ).map((product) => product.id);
                                  if (_selectedProductIds.length ==
                                      ids.length) {
                                    _selectedProductIds.clear();
                                  } else {
                                    _selectedProductIds
                                      ..clear()
                                      ..addAll(ids);
                                  }
                                }),
                                icon: Icon(
                                  _selectedProductIds.isNotEmpty
                                      ? Icons.deselect_rounded
                                      : Icons.select_all_rounded,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (_selectedProductIds.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${_selectedProductIds.length} seleccionados',
                                style: Theme.of(context).textTheme.labelLarge
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                            ),
                            TextButton.icon(
                              onPressed: _downloading
                                  ? null
                                  : () => _downloadLabels(state.products),
                              icon: const Icon(Icons.download_outlined),
                              label: const Text('PDF'),
                            ),
                            TextButton.icon(
                              onPressed: _printing
                                  ? null
                                  : () => _printLabels(state.products),
                              icon: const Icon(Icons.print_outlined),
                              label: const Text('Imprimir'),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 8),
                      if (_withBarcodes(state.products).isEmpty)
                        const Card(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                              'Ningún producto tiene un código de barras asignado.',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      else
                        for (final product in _withBarcodes(state.products))
                          _BarcodeProductCard(
                            product: product,
                            selected: _selectedProductIds.contains(product.id),
                            onSelected: (selected) => setState(() {
                              if (selected) {
                                _selectedProductIds.add(product.id);
                              } else {
                                _selectedProductIds.remove(product.id);
                              }
                            }),
                            onDownload: () => _downloadLabels([
                              product,
                            ], respectSelection: false),
                            onPrint: () => _printLabels([
                              product,
                            ], respectSelection: false),
                            busy: _printing || _downloading,
                          ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _BarcodeProductCard extends StatelessWidget {
  final Product product;
  final bool selected;
  final ValueChanged<bool> onSelected;
  final VoidCallback onDownload;
  final VoidCallback onPrint;
  final bool busy;

  const _BarcodeProductCard({
    required this.product,
    required this.selected,
    required this.onSelected,
    required this.onDownload,
    required this.onPrint,
    required this.busy,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
        child: Column(
          children: [
            Row(
              children: [
                Checkbox(
                  value: selected,
                  onChanged: (value) {
                    if (value != null) onSelected(value);
                  },
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      if (product.category.trim().isNotEmpty)
                        Text(
                          product.category,
                          style: TextStyle(
                            color: colors.onSurfaceVariant,
                            fontSize: 13,
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Descargar PDF',
                  onPressed: busy ? null : onDownload,
                  icon: const Icon(Icons.download_outlined),
                ),
                IconButton(
                  tooltip: 'Imprimir etiqueta',
                  onPressed: busy ? null : onPrint,
                  icon: const Icon(Icons.print_outlined),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF8F9FA),
                borderRadius: BorderRadius.circular(12),
              ),
              child: BarcodeWidget(
                barcode: Barcode.code128(),
                data: product.barcode,
                width: double.infinity,
                height: 68,
                drawText: false,
                backgroundColor: const Color(0xFFF8F9FA),
                errorBuilder: (context, error) => SizedBox(
                  height: 68,
                  child: Center(
                    child: Text(
                      'Código no válido: $error',
                      style: TextStyle(color: colors.error),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 7),
            SelectableText(
              product.barcode.split('').join(' '),
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                letterSpacing: 1.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
