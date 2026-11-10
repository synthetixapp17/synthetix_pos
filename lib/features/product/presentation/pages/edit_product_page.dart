import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';

import '../../../../core/utils/app_currency.dart';
import '../../../../core/utils/app_validators.dart';
import '../../../../core/utils/product_categories.dart';
import '../../domain/entities/product.dart';
import '../bloc/product_bloc.dart';
import '../widgets/product_variants_form.dart';

class EditProductPage extends StatefulWidget {
  final Product product;
  const EditProductPage({super.key, required this.product});

  @override
  State<EditProductPage> createState() => _EditProductPageState();
}

class _EditProductPageState extends State<EditProductPage> {
  final _formKey = GlobalKey<FormState>();
  late final _nameController = TextEditingController(text: widget.product.name);
  late final _descriptionController = TextEditingController(
    text: widget.product.description,
  );
  late final _priceController = TextEditingController(
    text: widget.product.price.toStringAsFixed(2),
  );
  late final _stockController = TextEditingController(
    text: widget.product.stock.toString(),
  );
  late final _categoryController = TextEditingController(
    text: widget.product.category,
  );
  final String _currencyCode = AppCurrency.baseCode;
  late String? _imageData = widget.product.imageData;
  late List<String> _categories;
  late bool _hasVariants = widget.product.hasVariants;
  final _variantsFormKey = GlobalKey<ProductVariantsFormState>();

  @override
  void initState() {
    super.initState();
    _categories = ProductCategories.load()
        .map((category) => category.name)
        .toList();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    _stockController.dispose();
    _categoryController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final image = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 82,
        maxWidth: 1400,
      );
      if (image != null && mounted) {
        final bytes = await image.readAsBytes();
        if (mounted) setState(() => _imageData = base64Encode(bytes));
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo cargar la imagen: $error')),
      );
    }
  }

  Future<void> _manageCategories() async {
    await context.push('/settings/categories');
    if (mounted) {
      setState(() {
        _categories = ProductCategories.load()
            .map((category) => category.name)
            .toList();
      });
    }
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final variants = _hasVariants
        ? _variantsFormKey.currentState?.readVariants()
        : null;
    if (_hasVariants && variants == null) return;
    final barcodes = [
      widget.product.barcode,
      ...?variants
          ?.map((variant) => variant.barcode)
          .where((barcode) => barcode.isNotEmpty),
    ];
    if (barcodes.toSet().length != barcodes.length ||
        context.read<ProductBloc>().state.products.any(
          (product) =>
              product.id != widget.product.id &&
              {
                product.barcode,
                ...product.variants.map((variant) => variant.barcode),
              }.intersection(barcodes.toSet()).isNotEmpty,
        )) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Los códigos de barras deben ser únicos.'),
        ),
      );
      return;
    }
    final amount =
        variants?.first.price ??
        double.parse(_priceController.text.trim().replaceAll(',', '.'));
    context.read<ProductBloc>().add(
      UpdateProduct(
        Product(
          id: widget.product.id,
          name: _nameController.text.trim(),
          description: _descriptionController.text.trim(),
          barcode: widget.product.barcode,
          price: amount,
          stock:
              variants?.fold<double>(
                0,
                (total, variant) => total + variant.stock,
              ) ??
              double.parse(_stockController.text.trim().replaceAll(',', '.')),
          imageData: _imageData,
          currencyCode: _currencyCode,
          category: _categoryController.text.trim(),
          variants: variants ?? const [],
        ),
      ),
    );
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final currentCategory = _categoryController.text.trim();
    return Scaffold(
      appBar: AppBar(title: const Text('Editar producto')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            Text(
              'Datos del producto',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _ProductImage(imageData: _imageData, onPressed: _pickImage),
            const SizedBox(height: 18),
            TextFormField(
              controller: _nameController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Nombre del producto',
                prefixIcon: Icon(Icons.label_outline),
              ),
              validator: AppValidators.required('El nombre es obligatorio.'),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _descriptionController,
              minLines: 2,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Descripción',
                alignLabelWithHint: true,
                prefixIcon: Icon(Icons.notes_outlined),
              ),
              validator: AppValidators.required(
                'La descripción es obligatoria.',
              ),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: _categories.contains(currentCategory)
                  ? currentCategory
                  : '',
              decoration: const InputDecoration(
                labelText: 'Categoría',
                helperText: 'Selecciona una categoría del catálogo.',
                prefixIcon: Icon(Icons.category_outlined),
              ),
              items: [
                const DropdownMenuItem(value: '', child: Text('Sin categoría')),
                ..._categories.map(
                  (category) =>
                      DropdownMenuItem(value: category, child: Text(category)),
                ),
              ],
              onChanged: (value) =>
                  setState(() => _categoryController.text = value ?? ''),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _manageCategories,
                icon: const Icon(Icons.settings_outlined, size: 18),
                label: const Text('Administrar categorías'),
              ),
            ),
            const SizedBox(height: 14),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    SizedBox(
                      width: 64,
                      height: 64,
                      child: PrettyQrView.data(data: widget.product.barcode),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Código QR o de barras',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Text(widget.product.barcode),
                          const SizedBox(height: 3),
                          const Text('El código no se puede modificar.'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Este producto tiene variaciones'),
              subtitle: const Text('Tallas, colores o presentaciones/pesos'),
              value: _hasVariants,
              onChanged: (value) => setState(() => _hasVariants = value),
            ),
            Visibility(
              visible: _hasVariants,
              maintainState: true,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: ProductVariantsForm(
                  key: _variantsFormKey,
                  initialVariants: widget.product.variants,
                ),
              ),
            ),
            if (!_hasVariants) ...[
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _priceController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Precio',
                        prefixIcon: Icon(Icons.payments_outlined),
                      ),
                      validator: (value) {
                        final amount = double.tryParse(
                          (value ?? '').trim().replaceAll(',', '.'),
                        );
                        return amount == null || amount < 0
                            ? 'Indica un precio válido.'
                            : null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Moneda de referencia',
                      ),
                      child: Text(
                        '${AppCurrency.symbolFor(AppCurrency.baseCode)} '
                        '${AppCurrency.baseCode}',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _stockController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Existencias',
                  prefixIcon: Icon(Icons.warehouse_outlined),
                ),
                validator: (value) {
                  final stock = double.tryParse(
                    (value ?? '').trim().replaceAll(',', '.'),
                  );
                  return stock == null || !stock.isFinite || stock < 0
                      ? 'Indica una cantidad válida.'
                      : null;
                },
              ),
            ],
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save_outlined),
              label: const Text('Guardar cambios'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductImage extends StatelessWidget {
  final String? imageData;
  final VoidCallback onPressed;
  const _ProductImage({required this.imageData, required this.onPressed});

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: onPressed,
    icon: imageData == null
        ? const Icon(Icons.add_photo_alternate_outlined)
        : ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.memory(
              base64Decode(imageData!),
              width: 48,
              height: 48,
              fit: BoxFit.cover,
            ),
          ),
    label: Text(imageData == null ? 'Agregar imagen' : 'Cambiar imagen'),
    style: OutlinedButton.styleFrom(
      padding: const EdgeInsets.symmetric(vertical: 14),
      alignment: Alignment.centerLeft,
    ),
  );
}
