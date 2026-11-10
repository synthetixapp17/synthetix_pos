import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:barcode_widget/barcode_widget.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/app_currency.dart';
import '../../../../core/utils/app_validators.dart';
import '../../../../core/utils/barcode_generator.dart';
import '../../../../core/utils/product_categories.dart';
import '../../domain/entities/product.dart';
import '../bloc/product_bloc.dart';
import '../widgets/product_variants_form.dart';

class AddProductPage extends StatefulWidget {
  const AddProductPage({super.key});

  @override
  State<AddProductPage> createState() => _AddProductPageState();
}

class _AddProductPageState extends State<AddProductPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _barcodeController = TextEditingController();
  final _priceController = TextEditingController();
  final _stockController = TextEditingController(text: '0');
  final _categoryController = TextEditingController();
  final String _currencyCode = AppCurrency.baseCode;
  String? _imageData;
  late List<String> _categories;
  bool _isPickingImage = false;
  bool _hasVariants = false;
  String _unitLabel = 'ud.';
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
    _barcodeController.dispose();
    _priceController.dispose();
    _stockController.dispose();
    _categoryController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    setState(() => _isPickingImage = true);
    try {
      final image = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 82,
        maxWidth: 1400,
      );
      if (image == null || !mounted) return;
      final bytes = await image.readAsBytes();
      setState(() => _imageData = base64Encode(bytes));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo cargar la imagen: $error')),
      );
    } finally {
      if (mounted) setState(() => _isPickingImage = false);
    }
  }

  Future<void> _scanBarcode() async {
    final result = await context.push<String>('/scan-code');
    if (result != null && result.isNotEmpty && mounted) {
      setState(() => _barcodeController.text = result);
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

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final variants = _hasVariants
        ? _variantsFormKey.currentState?.readVariants()
        : null;
    if (_hasVariants && variants == null) return;
    if (_imageData == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Agrega una imagen para poder guardar el producto.'),
        ),
      );
      return;
    }
    final barcode = _barcodeController.text.trim();
    final incomingBarcodeList = [
      barcode,
      ...?variants
          ?.map((variant) => variant.barcode)
          .where((value) => value.isNotEmpty),
    ];
    final incomingBarcodes = incomingBarcodeList.toSet();
    if (incomingBarcodes.length != incomingBarcodeList.length) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No repitas códigos de barras entre variaciones.'),
        ),
      );
      return;
    }
    final duplicate = context.read<ProductBloc>().state.products.any(
      (product) => {
        product.barcode,
        ...product.variants.map((variant) => variant.barcode),
      }.intersection(incomingBarcodes).isNotEmpty,
    );
    if (duplicate) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ya existe un producto con ese código QR o de barras.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    context.read<ProductBloc>().add(
      AddProduct(
        Product(
          id: const Uuid().v4(),
          name: _nameController.text.trim(),
          description: _descriptionController.text.trim(),
          barcode: barcode,
          price:
              variants?.first.price ??
              double.parse(_priceController.text.trim().replaceAll(',', '.')),
          stock:
              variants?.fold<double>(
                0,
                (total, variant) => total + variant.stock,
              ) ??
              double.parse(_stockController.text.trim().replaceAll(',', '.')),
          imageData: _imageData,
          currencyCode: _currencyCode,
          category: _categoryController.text.trim(),
          unitLabel: _unitLabel,
          variants: variants ?? const [],
        ),
      ),
    );
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Agregar producto')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: [
              _buildSectionIntro(
                context,
                icon: Icons.inventory_2_outlined,
                title: 'Información del producto',
                subtitle: 'Completa los datos para agregarlo al inventario.',
              ),
              const SizedBox(height: 18),
              _ImagePickerCard(
                imageData: _imageData,
                onPressed: _pickImage,
                loading: _isPickingImage,
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Nombre del producto',
                  hintText: 'Ej.: Café molido',
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
                  hintText: 'Presentación, características o detalles',
                  alignLabelWithHint: true,
                  prefixIcon: Icon(Icons.notes_outlined),
                ),
                validator: AppValidators.required(
                  'La descripción es obligatoria.',
                ),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: _categories.contains(_categoryController.text)
                    ? _categoryController.text
                    : '',
                decoration: const InputDecoration(
                  labelText: 'Categoría',
                  helperText: 'Selecciona una categoría del catálogo.',
                  prefixIcon: Icon(Icons.category_outlined),
                ),
                items: [
                  const DropdownMenuItem(
                    value: '',
                    child: Text('Sin categoría'),
                  ),
                  ..._categories.map(
                    (category) => DropdownMenuItem(
                      value: category,
                      child: Text(category),
                    ),
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
              _buildCodeField(),
              if (_barcodeController.text.trim().isNotEmpty) ...[
                const SizedBox(height: 16),
                _QrPreview(value: _barcodeController.text.trim()),
              ],
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
                  child: ProductVariantsForm(key: _variantsFormKey),
                ),
              ),
              if (!_hasVariants) ...[
                DropdownButtonFormField<String>(
                  initialValue: _unitLabel,
                  decoration: const InputDecoration(
                    labelText: 'Unidad de venta',
                    helperText:
                        'Usa kg o g para habilitar este producto en la balanza.',
                    prefixIcon: Icon(Icons.scale_outlined),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'ud.', child: Text('Unidad (ud.)')),
                    DropdownMenuItem(value: 'kg', child: Text('Kilogramo (kg)')),
                    DropdownMenuItem(value: 'g', child: Text('Gramo (g)')),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _unitLabel = value);
                  },
                ),
                const SizedBox(height: 14),
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
                          hintText: '0,00',
                          prefixIcon: Icon(Icons.payments_outlined),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Indica el precio.';
                          }
                          final normalized = value.trim().replaceAll(',', '.');
                          final amount = double.tryParse(normalized);
                          if (amount == null || amount < 0) {
                            return 'Indica un precio válido.';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Moneda de referencia',
                          prefixIcon: Icon(Icons.currency_exchange),
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
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Existencias iniciales ($_unitLabel)',
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
                onPressed: _submit,
                icon: const Icon(Icons.add_circle_outline),
                label: const Text('Guardar producto'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: AppTheme.onColor(AppTheme.primaryColor),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _generateBarcode() {
    final existingBarcodes = context
        .read<ProductBloc>()
        .state
        .products
        .map((product) => product.barcode)
        .toSet();
    try {
      final barcode = BarcodeGenerator.generateEan13(
        excluding: existingBarcodes,
      );
      setState(() => _barcodeController.text = barcode);
    } on StateError {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No se pudo generar un código único. Inténtalo nuevamente.',
          ),
        ),
      );
    }
  }

  Widget _buildCodeField() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      TextFormField(
        controller: _barcodeController,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          labelText: 'Código de barras',
          hintText: 'Genera, escribe o escanea el código',
          prefixIcon: const Icon(Icons.qr_code_2),
          suffixIcon: IconButton(
            tooltip: 'Escanear código',
            onPressed: _scanBarcode,
            icon: const Icon(Icons.qr_code_scanner),
          ),
        ),
        validator: AppValidators.required('El código es obligatorio.'),
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: _generateBarcode,
        icon: const Icon(Icons.auto_awesome_outlined, size: 18),
        label: const Text('Generar código automáticamente'),
      ),
    ],
  );

  Widget _buildSectionIntro(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
  }) => Row(
    children: [
      CircleAvatar(
        radius: 25,
        backgroundColor: Theme.of(
          context,
        ).colorScheme.primary.withValues(alpha: .1),
        child: Icon(icon, color: Theme.of(context).colorScheme.primary),
      ),
      const SizedBox(width: 14),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 3),
            Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    ],
  );
}

class _ImagePickerCard extends StatelessWidget {
  final String? imageData;
  final VoidCallback onPressed;
  final bool loading;

  const _ImagePickerCard({
    required this.imageData,
    required this.onPressed,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    final image = imageData;
    return InkWell(
      onTap: loading ? null : onPressed,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        height: 190,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Theme.of(context).dividerColor),
          image: image == null
              ? null
              : DecorationImage(
                  image: MemoryImage(base64Decode(image)),
                  fit: BoxFit.cover,
                ),
        ),
        child: image == null
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (loading)
                      const CircularProgressIndicator()
                    else
                      Icon(
                        Icons.add_photo_alternate_outlined,
                        size: 42,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    const SizedBox(height: 10),
                    Text(
                      loading
                          ? 'Cargando imagen…'
                          : 'Agregar imagen del producto',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Selecciona una imagen de tu galería',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              )
            : Align(
                alignment: Alignment.bottomRight,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: FilledButton.tonalIcon(
                    onPressed: onPressed,
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Cambiar imagen'),
                  ),
                ),
              ),
      ),
    );
  }
}

class _QrPreview extends StatelessWidget {
  final String value;
  const _QrPreview({required this.value});

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          SizedBox(
            width: 140,
            height: 72,
            child: BarcodeWidget(
              barcode: Barcode.code128(),
              data: value,
              drawText: false,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Código listo',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(value, maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 3),
                Text(
                  'El código se usará para identificar el producto.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
