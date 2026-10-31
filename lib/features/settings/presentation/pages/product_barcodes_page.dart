import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

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
  bool _printing = false;

  Future<void> _printLabels(List<Product> products) async {
    final printable = products
        .where((product) => product.barcode.trim().isNotEmpty)
        .toList();
    if (printable.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay productos con código de barras.')),
      );
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
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${printable.length} etiquetas enviadas a imprimir.'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            printedCount == 0
                ? 'No se pudieron imprimir los códigos: $error'
                : 'Se imprimieron $printedCount de ${printable.length} etiquetas. Error: $error',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Códigos de barras'),
      actions: [
        BlocBuilder<ProductBloc, ProductState>(
          builder: (context, state) => IconButton(
            tooltip: 'Imprimir todas las etiquetas',
            onPressed: _printing ? null : () => _printLabels(state.products),
            icon: _printing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.print_outlined),
          ),
        ),
      ],
    ),
    body: BlocBuilder<ProductBloc, ProductState>(
      builder: (context, state) {
        if (state.status == ProductStatus.loading && state.products.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        if (state.products.isEmpty) {
          return const Center(child: Text('Aún no hay productos registrados.'));
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(
                      Icons.qr_code_2,
                      size: 32,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        'Consulta los códigos de tu catálogo e imprime las etiquetas en la impresora térmica configurada.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            for (final product in state.products)
              Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.primaryContainer,
                    child: Icon(
                      Icons.qr_code_scanner,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                  title: Text(
                    product.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    product.barcode.isEmpty
                        ? 'Este producto no tiene código asignado'
                        : product.barcode,
                    style: TextStyle(
                      fontFamily: product.barcode.isEmpty ? null : 'monospace',
                    ),
                  ),
                  trailing: IconButton(
                    tooltip: 'Imprimir etiqueta',
                    onPressed: _printing || product.barcode.isEmpty
                        ? null
                        : () => _printLabels([product]),
                    icon: const Icon(Icons.print_outlined),
                  ),
                ),
              ),
          ],
        );
      },
    ),
  );
}
