import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../domain/entities/product.dart';

class ProductVariantsForm extends StatefulWidget {
  final List<ProductVariant> initialVariants;

  const ProductVariantsForm({super.key, this.initialVariants = const []});

  @override
  State<ProductVariantsForm> createState() => ProductVariantsFormState();
}

class ProductVariantsFormState extends State<ProductVariantsForm> {
  late final List<_VariantFields> _rows = [
    for (final variant in widget.initialVariants)
      _VariantFields.fromVariant(variant),
    if (widget.initialVariants.isEmpty) _VariantFields(),
  ];
  String? _error;

  List<ProductVariant>? readVariants() {
    final variants = <ProductVariant>[];
    for (final row in _rows) {
      final attributes = _parseAttributes(row.attributes.text);
      final price = double.tryParse(row.price.text.trim().replaceAll(',', '.'));
      final stock = double.tryParse(row.stock.text.trim().replaceAll(',', '.'));
      if (attributes.isEmpty ||
          price == null ||
          !price.isFinite ||
          price < 0 ||
          stock == null ||
          !stock.isFinite ||
          stock < 0 ||
          row.unit.text.trim().isEmpty) {
        setState(
          () => _error =
              'Completa los atributos, precio, existencias y unidad de cada variación.',
        );
        return null;
      }
      variants.add(
        ProductVariant(
          id: row.id,
          attributes: attributes,
          price: price,
          stock: stock,
          barcode: row.barcode.text.trim(),
          unitLabel: row.unit.text.trim(),
        ),
      );
    }
    if (variants.isEmpty) {
      setState(() => _error = 'Agrega al menos una variación.');
      return null;
    }
    final barcodes = variants
        .map((variant) => variant.barcode)
        .where((barcode) => barcode.isNotEmpty)
        .toList();
    if (barcodes.toSet().length != barcodes.length) {
      setState(() => _error = 'No repitas el código en varias variaciones.');
      return null;
    }
    setState(() => _error = null);
    return variants;
  }

  Map<String, String> _parseAttributes(String value) {
    final attributes = <String, String>{};
    for (final item in value.split(RegExp(r'[,;]'))) {
      final separator = item.contains(':') ? ':' : '=';
      final pair = item.split(separator);
      if (pair.length != 2) continue;
      final name = pair.first.trim();
      final option = pair.last.trim();
      if (name.isNotEmpty && option.isNotEmpty) attributes[name] = option;
    }
    return attributes;
  }

  void _addVariant() => setState(() {
    _rows.add(_VariantFields());
    _error = null;
  });

  void _removeVariant(int index) {
    setState(() {
      _rows.removeAt(index).dispose();
      _error = null;
    });
  }

  @override
  void dispose() {
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Variaciones e inventario',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            'Define cada combinación, por ejemplo Talla:M, Color:Negro. '
            'El stock puede ser fraccionario para ventas por peso.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          for (var index = 0; index < _rows.length; index++)
            _buildVariantRow(context, index),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _addVariant,
              icon: const Icon(Icons.add),
              label: const Text('Agregar variación'),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _buildVariantRow(BuildContext context, int index) {
    final fields = _rows[index];
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Variación ${index + 1}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              if (_rows.length > 1)
                IconButton(
                  tooltip: 'Eliminar variación',
                  onPressed: () => _removeVariant(index),
                  icon: const Icon(Icons.delete_outline),
                ),
            ],
          ),
          TextField(
            controller: fields.attributes,
            decoration: const InputDecoration(
              labelText: 'Atributos',
              hintText: 'Talla: M, Color: Negro',
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: fields.price,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: 'Precio'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: fields.stock,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: 'Existencias'),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 84,
                child: TextField(
                  controller: fields.unit,
                  decoration: const InputDecoration(labelText: 'Unidad'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: fields.barcode,
            decoration: const InputDecoration(
              labelText: 'Código de barras de la variación (opcional)',
            ),
          ),
          const Divider(height: 24),
        ],
      ),
    );
  }
}

class _VariantFields {
  late final String id;
  final TextEditingController attributes = TextEditingController();
  final TextEditingController price = TextEditingController();
  final TextEditingController stock = TextEditingController(text: '0');
  final TextEditingController barcode = TextEditingController();
  final TextEditingController unit = TextEditingController(text: 'ud.');

  _VariantFields() : id = const Uuid().v4();

  _VariantFields.fromVariant(ProductVariant variant) : id = variant.id {
    attributes.text = variant.attributes.entries
        .map((entry) => '${entry.key}: ${entry.value}')
        .join(', ');
    price.text = variant.price.toString();
    stock.text = variant.stock.toString();
    barcode.text = variant.barcode;
    unit.text = variant.unitLabel;
  }

  void dispose() {
    attributes.dispose();
    price.dispose();
    stock.dispose();
    barcode.dispose();
    unit.dispose();
  }
}
