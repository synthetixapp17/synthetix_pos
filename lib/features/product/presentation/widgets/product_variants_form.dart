import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../domain/entities/product.dart';

const _attributeTypes = [
  'Color',
  'Talla',
  'Peso',
  'Material',
  'Presentación',
  'Sabor',
  'Personalizado',
];

const _attributeOptions = <String, List<String>>{
  'Color': [
    'Negro',
    'Blanco',
    'Rojo',
    'Azul',
    'Verde',
    'Amarillo',
    'Gris',
    'Marrón',
    'Rosado',
    'Morado',
    'Naranja',
    'Transparente',
    'Multicolor',
  ],
  'Talla': [
    'Única',
    'XS',
    'S',
    'M',
    'L',
    'XL',
    'XXL',
    'XXXL',
    '28',
    '30',
    '32',
    '34',
    '36',
    '38',
    '40',
    '42',
  ],
  'Peso': [
    '50 g',
    '100 g',
    '250 g',
    '500 g',
    '750 g',
    '1 kg',
    '2 kg',
    '5 kg',
    '10 kg',
  ],
  'Material': [
    'Algodón',
    'Poliéster',
    'Cuero',
    'Acero inoxidable',
    'Plástico',
    'Madera',
    'Vidrio',
  ],
  'Presentación': [
    'Individual',
    'Paquete',
    'Caja',
    'Botella',
    'Bolsa',
    'Frasco',
  ],
  'Sabor': ['Natural', 'Chocolate', 'Vainilla', 'Fresa', 'Limón', 'Picante'],
};

const _unitOptions = [
  'ud.',
  'kg',
  'g',
  'lb',
  'oz',
  'l',
  'ml',
  'paquete',
  'caja',
];

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
      final attributes = row.readAttributes();
      final price = double.tryParse(row.price.text.trim().replaceAll(',', '.'));
      final stock = double.tryParse(row.stock.text.trim().replaceAll(',', '.'));
      if (attributes.isEmpty ||
          attributes.length != row.attributes.length ||
          price == null ||
          !price.isFinite ||
          price < 0 ||
          stock == null ||
          !stock.isFinite ||
          stock < 0 ||
          row.unitLabel.trim().isEmpty) {
        setState(
          () => _error =
              'Completa los atributos, precio, existencias y unidad de cada variación.',
        );
        return null;
      }
      if (attributes.keys.map((key) => key.toLowerCase()).toSet().length !=
          attributes.length) {
        setState(
          () => _error = 'Cada variación debe tener atributos distintos.',
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
          unitLabel: row.unitLabel,
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

  void _addAttribute(_VariantFields row, String type) {
    final label = type == 'Personalizado' ? 'Atributo' : type;
    final alreadyAdded = row.attributes.any((attribute) {
      final current = attribute.type == 'Personalizado'
          ? attribute.customName.text.trim()
          : attribute.type;
      return current.toLowerCase() == label.toLowerCase();
    });
    if (alreadyAdded) {
      setState(() => _error = 'Ese atributo ya está agregado a la variación.');
      return;
    }
    setState(() {
      final options = _attributeOptions[type] ?? const <String>[];
      row.attributes.add(
        _VariantAttribute(
          type: type,
          value: options.isEmpty ? '' : options.first,
        ),
      );
      _error = null;
    });
  }

  void _removeAttribute(_VariantFields row, int index) {
    setState(() => row.attributes.removeAt(index).dispose());
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
    elevation: 0,
    color: const Color(0xFFF8FAFC),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
      side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
    ),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF1FC),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.tune_rounded, color: Color(0xFF2768D7)),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Variantes del producto',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Combina color, talla, peso y más. Cada combinación conserva su precio y stock.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          for (var index = 0; index < _rows.length; index++)
            _buildVariantCard(context, index),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _addVariant,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Agregar combinación'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _buildVariantCard(BuildContext context, int index) {
    final row = _rows[index];
    final colors = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F4FA),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(
                    color: Color(0xFF2768D7),
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  'Combinación ${index + 1}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              if (_rows.length > 1)
                IconButton(
                  tooltip: 'Eliminar combinación',
                  onPressed: () => _removeVariant(index),
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
            ],
          ),
          if (row.attributes.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (
              var attributeIndex = 0;
              attributeIndex < row.attributes.length;
              attributeIndex++
            )
              _buildAttributeRow(context, row, attributeIndex),
          ] else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Text(
                'Agrega al menos un atributo para identificar esta combinación.',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: PopupMenuButton<String>(
              onSelected: (type) => _addAttribute(row, type),
              itemBuilder: (context) => [
                for (final type in _attributeTypes)
                  PopupMenuItem(value: type, child: Text(type)),
              ],
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.add_circle_outline_rounded,
                      size: 18,
                      color: Color(0xFF2768D7),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Agregar atributo',
                      style: TextStyle(
                        color: colors.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const Divider(height: 20),
          Wrap(
            spacing: 9,
            runSpacing: 10,
            children: [
              _NumericField(
                controller: row.price,
                label: 'Precio',
                icon: Icons.payments_outlined,
              ),
              _NumericField(
                controller: row.stock,
                label: 'Existencias',
                icon: Icons.inventory_2_outlined,
              ),
              LayoutBuilder(
                builder: (context, constraints) =>
                    SizedBox(
                      width: constraints.maxWidth < 280
                          ? constraints.maxWidth
                          : 280,
                      child: DropdownButtonFormField<String>(
                  initialValue: row.unitLabel.trim().isEmpty
                      ? 'ud.'
                      : row.unitLabel,
                  decoration: const InputDecoration(
                    labelText: 'Unidad',
                    prefixIcon: Icon(Icons.straighten_rounded, size: 19),
                    isDense: true,
                  ),
                  items: [
                    if (!_unitOptions.contains(row.unitLabel))
                      DropdownMenuItem(
                        value: row.unitLabel,
                        child: Text(
                          row.unitLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    for (final unit in _unitOptions)
                      DropdownMenuItem(
                        value: unit,
                        child: Text(
                          unit,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => row.unitLabel = value);
                    }
                  },
                      ),
                    ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: row.barcode,
            decoration: const InputDecoration(
              labelText: 'Código de barras (opcional)',
              prefixIcon: Icon(Icons.qr_code_2_rounded, size: 20),
              isDense: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttributeRow(
    BuildContext context,
    _VariantFields row,
    int index,
  ) {
    final attribute = row.attributes[index];
    final values = _attributeOptions[attribute.type] ?? const <String>[];
    final isCustom = attribute.type == 'Personalizado';
    final usesCustomValue =
        attribute.customValue || !values.contains(attribute.value.text);
    final nameField = isCustom
        ? TextField(
            controller: attribute.customName,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Atributo',
              hintText: 'Ej.: Colección',
              isDense: true,
            ),
          )
        : DropdownButtonFormField<String>(
            initialValue: attribute.type,
            decoration: const InputDecoration(labelText: 'Tipo', isDense: true),
            items: [
              for (final type in _attributeTypes)
                DropdownMenuItem(value: type, child: Text(type)),
            ],
            onChanged: (type) {
              if (type != null) {
                setState(() {
                  attribute.type = type;
                  final options = _attributeOptions[type] ?? const <String>[];
                  attribute.customValue =
                      type == 'Personalizado' || options.isEmpty;
                  attribute.value.text = options.isEmpty ? '' : options.first;
                });
              }
            },
          );
    final valueField = isCustom || usesCustomValue
        ? TextField(
            controller: attribute.value,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: isCustom ? 'Valor' : 'Valor personalizado',
              hintText: 'Escribe el valor',
              isDense: true,
            ),
            onChanged: (_) {
              if (!attribute.customValue) {
                setState(() => attribute.customValue = true);
              }
            },
          )
        : DropdownButtonFormField<String>(
            initialValue: attribute.value.text,
            decoration: const InputDecoration(
              labelText: 'Valor',
              isDense: true,
            ),
            items: [
              for (final value in values)
                DropdownMenuItem(value: value, child: Text(value)),
              const DropdownMenuItem(value: '__custom__', child: Text('Otro…')),
            ],
            onChanged: (value) {
              setState(() {
                if (value == '__custom__') {
                  attribute.customValue = true;
                  attribute.value.clear();
                } else if (value != null) {
                  attribute.customValue = false;
                  attribute.value.text = value;
                }
              });
            },
          );
    final removeButton = IconButton(
      tooltip: 'Quitar atributo',
      onPressed: () => _removeAttribute(row, index),
      visualDensity: VisualDensity.compact,
      icon: const Icon(Icons.close_rounded, size: 19),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 900) {
            return Column(
              children: [
                nameField,
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: valueField),
                    removeButton,
                  ],
                ),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 4, child: nameField),
              const SizedBox(width: 8),
              Expanded(flex: 5, child: valueField),
              removeButton,
            ],
          );
        },
      ),
    );
  }
}

class _NumericField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;

  const _NumericField({
    required this.controller,
    required this.label,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => SizedBox(
      width: constraints.maxWidth < 280 ? constraints.maxWidth : 280,
      child: TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, size: 19),
          isDense: true,
        ),
      ),
    ),
  );
}

class _VariantFields {
  final String id;
  final List<_VariantAttribute> attributes = [];
  final TextEditingController price = TextEditingController();
  final TextEditingController stock = TextEditingController(text: '0');
  final TextEditingController barcode = TextEditingController();
  String unitLabel = 'ud.';

  _VariantFields() : id = const Uuid().v4();

  _VariantFields.fromVariant(ProductVariant variant) : id = variant.id {
    for (final entry in variant.attributes.entries) {
      final type = _attributeTypes.contains(entry.key)
          ? entry.key
          : 'Personalizado';
      attributes.add(
        _VariantAttribute(
          type: type,
          value: entry.value,
          customName: type == 'Personalizado' ? entry.key : '',
        ),
      );
    }
    price.text = variant.price.toString();
    stock.text = variant.stock.toString();
    barcode.text = variant.barcode;
    unitLabel = variant.unitLabel;
  }

  Map<String, String> readAttributes() {
    final result = <String, String>{};
    for (final attribute in attributes) {
      final name = attribute.type == 'Personalizado'
          ? attribute.customName.text.trim()
          : attribute.type;
      final value = attribute.value.text.trim();
      if (name.isNotEmpty && value.isNotEmpty) result[name] = value;
    }
    return result;
  }

  void dispose() {
    for (final attribute in attributes) {
      attribute.dispose();
    }
    price.dispose();
    stock.dispose();
    barcode.dispose();
  }
}

class _VariantAttribute {
  String type;
  bool customValue;
  final TextEditingController value;
  final TextEditingController customName;

  _VariantAttribute({
    required this.type,
    String value = '',
    String customName = '',
  }) : value = TextEditingController(text: value),
       customName = TextEditingController(text: customName),
       customValue = false {
    final options = _attributeOptions[type] ?? const <String>[];
    if (type == 'Personalizado') {
      customValue = true;
    } else if (options.isNotEmpty && value.isEmpty) {
      this.value.text = options.first;
    } else if (!options.contains(value)) {
      customValue = true;
    }
  }

  void dispose() {
    value.dispose();
    customName.dispose();
  }
}
