import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/utils/app_currency.dart';
import '../../../product/domain/entities/product.dart';
import '../../../product/domain/entities/product_weight_unit.dart';
import '../../../product/presentation/bloc/product_bloc.dart';
import '../bloc/billing_bloc.dart';

class DigitalScalePage extends StatefulWidget {
  const DigitalScalePage({super.key});

  @override
  State<DigitalScalePage> createState() => _DigitalScalePageState();
}

class _DigitalScalePageState extends State<DigitalScalePage> {
  final _searchController = TextEditingController();
  String _search = '';
  String? _selectedProductKey;
  String _weightInput = '0';
  ProductWeightUnit _inputUnit = ProductWeightUnit.grams;
  bool _showKeypad = false;
  bool _awaitingAdd = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Product> _weightProducts(List<Product> products) {
    final result = <Product>[];
    for (final product in products) {
      if (product.variants.isEmpty) {
        if (isWeightUnitLabel(product.unitLabel)) result.add(product);
        continue;
      }
      for (final variant in product.variants) {
        if (isWeightUnitLabel(variant.unitLabel)) {
          result.add(product.forVariant(variant));
        }
      }
    }
    return result;
  }

  double get _enteredWeight =>
      double.tryParse(_weightInput.replaceAll(',', '.')) ?? 0;

  double _quantityFor(Product product) => convertWeight(
    amount: _enteredWeight,
    fromUnit: _inputUnit == ProductWeightUnit.grams ? 'g' : 'kg',
    toUnit: product.saleUnitLabel,
  );

  double _lineTotal(Product product) =>
      product.salePrice * _quantityFor(product);

  String _unitText(ProductWeightUnit unit) =>
      unit == ProductWeightUnit.grams ? 'g' : 'kg';

  void _appendKey(String key) {
    setState(() {
      if (key == 'delete') {
        _weightInput = _weightInput.length > 1
            ? _weightInput.substring(0, _weightInput.length - 1)
            : '0';
        return;
      }
      if (key == '.') {
        if (!_weightInput.contains('.')) _weightInput += '.';
        return;
      }
      _weightInput = _weightInput == '0' ? key : '$_weightInput$key';
    });
  }

  void _adjustByGrams(double grams) {
    final currentGrams = convertWeight(
      amount: _enteredWeight,
      fromUnit: _unitText(_inputUnit),
      toUnit: 'g',
    );
    final nextGrams = (currentGrams + grams)
        .clamp(0, double.infinity)
        .toDouble();
    final nextAmount = convertWeight(
      amount: nextGrams,
      fromUnit: 'g',
      toUnit: _unitText(_inputUnit),
    );
    setState(() {
      _weightInput = _formatWeightInput(nextAmount);
    });
  }

  String _formatWeightInput(double value) => value
      .toStringAsFixed(_inputUnit == ProductWeightUnit.kilograms ? 3 : 1)
      .replaceFirst(RegExp(r'\.?0+$'), '');

  void _changeInputUnit(ProductWeightUnit unit) {
    if (unit == _inputUnit) return;
    final converted = convertWeight(
      amount: _enteredWeight,
      fromUnit: _unitText(_inputUnit),
      toUnit: _unitText(unit),
    );
    setState(() {
      _inputUnit = unit;
      _weightInput = _formatWeightInput(converted);
    });
  }

  void _addToSale(Product product) {
    if (_awaitingAdd) return;
    final amount = _enteredWeight;
    if (!amount.isFinite || amount <= 0) {
      _showMessage('Ingresa un peso mayor que cero.');
      return;
    }
    final quantity = _quantityFor(product);
    if (quantity > product.availableStock + 0.000001) {
      _showMessage(
        'Existencia insuficiente. Disponible: '
        '${product.availableStock} ${product.saleUnitLabel}.',
      );
      return;
    }
    final cartCurrency = context
        .read<BillingBloc>()
        .state
        .cartItems
        .firstOrNull
        ?.product
        .currencyCode;
    if (cartCurrency != null && cartCurrency != product.currencyCode) {
      _showMessage(
        'Finaliza la venta actual antes de agregar productos en otra moneda.',
      );
      return;
    }
    _awaitingAdd = true;
    context.read<BillingBloc>().add(
      AddProductToCartEvent(product, quantity: quantity),
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    AppCurrencyScope.of(context);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        title: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: const Color(0xFFE7F7EF),
                borderRadius: BorderRadius.circular(13),
              ),
              child: const Icon(Icons.scale_rounded, color: Color(0xFF138A55)),
            ),
            const SizedBox(width: 12),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Balanza digital'),
                Text(
                  'Pesaje manual · teclado táctil',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Abrir punto de venta',
            onPressed: () => context.push('/new-sale'),
            icon: const Icon(Icons.point_of_sale_outlined),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: BlocListener<BillingBloc, BillingState>(
        listenWhen: (previous, current) =>
            previous.error != current.error ||
            previous.cartItems != current.cartItems,
        listener: (context, state) {
          if (state.error != null) {
            _awaitingAdd = false;
            _showMessage(state.error!);
          } else if (_awaitingAdd) {
            _awaitingAdd = false;
            setState(() {
              _weightInput = '0';
              _showKeypad = false;
            });
          }
        },
        child: BlocBuilder<ProductBloc, ProductState>(
          builder: (context, state) {
            if (state.status == ProductStatus.loading &&
                state.products.isEmpty) {
              return const Center(child: CircularProgressIndicator());
            }
            if (state.status == ProductStatus.error && state.products.isEmpty) {
              return Center(
                child: Text(
                  state.message ?? 'No se pudieron cargar productos.',
                ),
              );
            }
            final products = _weightProducts(state.products);
            final filteredProducts = products
                .where(
                  (product) =>
                      product.name.toLowerCase().contains(_search) ||
                      product.variationLabel.toLowerCase().contains(_search),
                )
                .toList();
            final selected =
                filteredProducts
                    .where((product) => product.cartKey == _selectedProductKey)
                    .firstOrNull ??
                filteredProducts.firstOrNull;
            final isWide = MediaQuery.sizeOf(context).width >= 980;
            if (products.isEmpty) {
              return _EmptyScale(onAddProduct: () => context.push('/products'));
            }
            return LayoutBuilder(
              builder: (context, constraints) {
                final content = isWide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            width: 330,
                            child: _buildProductPicker(
                              context,
                              filteredProducts,
                              selected,
                              vertical: true,
                            ),
                          ),
                          const SizedBox(width: 20),
                          Expanded(
                            child: SingleChildScrollView(
                              child: _buildScalePanel(context, selected),
                            ),
                          ),
                        ],
                      )
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
                        children: [
                          _buildProductPicker(
                            context,
                            filteredProducts,
                            selected,
                            vertical: false,
                          ),
                          const SizedBox(height: 18),
                          if (selected != null)
                            _buildScalePanel(context, selected),
                        ],
                      );
                return Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1320),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        isWide ? 24 : 0,
                        isWide ? 20 : 0,
                        isWide ? 24 : 0,
                        isWide ? 20 : 0,
                      ),
                      child: content,
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
      bottomNavigationBar: BlocBuilder<BillingBloc, BillingState>(
        builder: (context, state) => _SaleSummary(
          totalUsd: state.totalAmount,
          onCheckout: state.cartItems.isEmpty
              ? null
              : () => context.push('/checkout'),
        ),
      ),
      backgroundColor: const Color(0xFFF4F7F9),
    );
  }

  Widget _buildProductPicker(
    BuildContext context,
    List<Product> products,
    Product? selected, {
    required bool vertical,
  }) {
    final colors = Theme.of(context).colorScheme;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Artículos por peso',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        Text(
          'Selecciona un artículo para calcular su importe.',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _searchController,
          onChanged: (value) =>
              setState(() => _search = value.trim().toLowerCase()),
          decoration: InputDecoration(
            hintText: 'Buscar artículo',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: _search.isEmpty
                ? null
                : IconButton(
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _search = '');
                    },
                    icon: const Icon(Icons.close_rounded),
                  ),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (products.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Text('No hay artículos que coincidan con la búsqueda.'),
          )
        else if (vertical)
          Expanded(
            child: ListView.separated(
              itemCount: products.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) => _ProductChoice(
                product: products[index],
                selected: products[index].cartKey == selected?.cartKey,
                onTap: () => setState(
                  () => _selectedProductKey = products[index].cartKey,
                ),
              ),
            ),
          )
        else
          SizedBox(
            height: 122,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: products.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, index) => SizedBox(
                width: 248,
                child: _ProductChoice(
                  product: products[index],
                  selected: products[index].cartKey == selected?.cartKey,
                  onTap: () => setState(
                    () => _selectedProductKey = products[index].cartKey,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
    return vertical
        ? Container(
            padding: const EdgeInsets.all(18),
            decoration: _cardDecoration(),
            child: content,
          )
        : content;
  }

  Widget _buildScalePanel(BuildContext context, Product? product) {
    if (product == null) {
      return const Center(child: Text('Selecciona un artículo por peso.'));
    }
    final colors = Theme.of(context).colorScheme;
    final currencyCode = AppCurrencyScope.of(context);
    final rate = AppCurrency.rateFor(currencyCode);
    final amount = _enteredWeight;
    final inputUnit = _unitText(_inputUnit);
    final price = _lineTotal(product);
    final pricePerKg =
        weightUnitForLabel(product.saleUnitLabel) == ProductWeightUnit.grams
        ? product.salePrice * 1000
        : product.salePrice;
    final canAdd =
        amount > 0 &&
        _quantityFor(product) <= product.availableStock + 0.000001;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _ProductImage(product: product),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (product.variationLabel.isNotEmpty)
                      Text(
                        product.variationLabel,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    const SizedBox(height: 5),
                    Text(
                      '${AppCurrency.format(product.salePrice, code: product.currencyCode)} / ${product.saleUnitLabel}',
                      style: const TextStyle(
                        color: Color(0xFF138A55),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      '${AppCurrency.format(pricePerKg, code: product.currencyCode)} / kg',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              _StockBadge(
                stock: product.availableStock,
                unit: product.saleUnitLabel,
              ),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFF101A22),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 9,
                      height: 9,
                      decoration: const BoxDecoration(
                        color: Color(0xFF4BE29A),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'PESAJE MANUAL',
                      style: TextStyle(
                        color: Color(0xFFC9D4DC),
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.1,
                        fontSize: 11,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: _showKeypad
                          ? 'Ocultar teclado'
                          : 'Mostrar teclado táctil',
                      onPressed: () =>
                          setState(() => _showKeypad = !_showKeypad),
                      color: Colors.white,
                      icon: Icon(
                        _showKeypad
                            ? Icons.keyboard_hide_rounded
                            : Icons.dialpad_rounded,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          _weightInput,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 58,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -1.5,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 9),
                    Text(
                      inputUnit,
                      style: const TextStyle(
                        color: Color(0xFF9FB0BC),
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SegmentedButton<ProductWeightUnit>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: ProductWeightUnit.kilograms,
                      label: Text('Kilogramos (kg)'),
                    ),
                    ButtonSegment(
                      value: ProductWeightUnit.grams,
                      label: Text('Gramos (g)'),
                    ),
                  ],
                  selected: {_inputUnit},
                  onSelectionChanged: (selection) =>
                      _changeInputUnit(selection.first),
                  style: SegmentedButton.styleFrom(
                    foregroundColor: Colors.white,
                    selectedForegroundColor: const Color(0xFF101A22),
                    selectedBackgroundColor: Colors.white,
                    side: const BorderSide(color: Color(0xFF34444F)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 9,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              _QuickWeightButton(
                label: '−250 g',
                onPressed: () => _adjustByGrams(-250),
              ),
              _QuickWeightButton(
                label: 'Tara (0)',
                icon: Icons.restart_alt_rounded,
                onPressed: () => setState(() => _weightInput = '0'),
              ),
              _QuickWeightButton(
                label: '+250 g',
                onPressed: () => _adjustByGrams(250),
              ),
              _QuickWeightButton(
                label: '+500 g',
                onPressed: () => _adjustByGrams(500),
              ),
            ],
          ),
          if (_showKeypad) ...[
            const SizedBox(height: 14),
            _WeightKeypad(onKey: _appendKey),
          ],
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF3F7F5),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE1ECE6)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Total a cobrar',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${_formatWeightAmount(_quantityFor(product))} ${product.saleUnitLabel} × ${AppCurrency.format(product.salePrice, code: product.currencyCode)}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      AppCurrency.format(price, code: product.currencyCode),
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: const Color(0xFF138A55),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (currencyCode != product.currencyCode)
                      Text(
                        AppCurrency.format(price * rate, code: currencyCode),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: canAdd && !_awaitingAdd
                ? () => _addToSale(product)
                : null,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              backgroundColor: const Color(0xFF138A55),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
            ),
            icon: const Icon(Icons.add_shopping_cart_rounded),
            label: const Text(
              'Agregar peso a la venta',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductChoice extends StatelessWidget {
  final Product product;
  final bool selected;
  final VoidCallback onTap;

  const _ProductChoice({
    required this.product,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: selected ? const Color(0xFFECF8F1) : Colors.white,
      borderRadius: BorderRadius.circular(15),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: selected ? const Color(0xFF138A55) : colors.outlineVariant,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Row(
            children: [
              _ProductImage(product: product, size: 48),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      product.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    if (product.variationLabel.isNotEmpty)
                      Text(
                        product.variationLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    const SizedBox(height: 3),
                    Text(
                      '${AppCurrency.format(product.salePrice, code: product.currencyCode)} / ${product.saleUnitLabel}',
                      style: const TextStyle(
                        color: Color(0xFF138A55),
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                const Icon(Icons.check_circle, color: Color(0xFF138A55)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProductImage extends StatelessWidget {
  final Product product;
  final double size;

  const _ProductImage({required this.product, this.size = 62});

  @override
  Widget build(BuildContext context) {
    final imageData = product.imageData;
    if (imageData == null) return _placeholder();
    late final Uint8List imageBytes;
    try {
      imageBytes = base64Decode(imageData);
    } on FormatException {
      return _placeholder();
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFFEAF2EE),
        borderRadius: BorderRadius.circular(13),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(13),
        child: Image.memory(
          imageBytes,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) =>
              const Icon(Icons.inventory_2_outlined, color: Color(0xFF138A55)),
        ),
      ),
    );
  }

  Widget _placeholder() => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: const Color(0xFFEAF2EE),
      borderRadius: BorderRadius.circular(13),
    ),
    child: const Icon(Icons.inventory_2_outlined, color: Color(0xFF138A55)),
  );
}

class _StockBadge extends StatelessWidget {
  final double stock;
  final String unit;

  const _StockBadge({required this.stock, required this.unit});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: const Color(0xFFF1F4F5),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        const Text(
          'DISPONIBLE',
          style: TextStyle(fontSize: 9, letterSpacing: .6),
        ),
        Text(
          '${_formatWeightAmount(stock)} $unit',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
        ),
      ],
    ),
  );
}

class _QuickWeightButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  final IconData? icon;

  const _QuickWeightButton({
    required this.label,
    required this.onPressed,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final style = OutlinedButton.styleFrom(
      foregroundColor: const Color(0xFF344750),
      side: const BorderSide(color: Color(0xFFDCE4E7)),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
    return icon == null
        ? OutlinedButton(onPressed: onPressed, style: style, child: Text(label))
        : OutlinedButton.icon(
            onPressed: onPressed,
            icon: Icon(icon, size: 17),
            label: Text(label),
            style: style,
          );
  }
}

class _WeightKeypad extends StatelessWidget {
  final ValueChanged<String> onKey;

  const _WeightKeypad({required this.onKey});

  @override
  Widget build(BuildContext context) {
    const keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '.', '0'];
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 2.2,
      children: [
        for (final key in keys) _KeyButton(label: key, onTap: () => onKey(key)),
        _KeyButton(
          icon: Icons.backspace_outlined,
          onTap: () => onKey('delete'),
        ),
      ],
    );
  }
}

class _KeyButton extends StatelessWidget {
  final String? label;
  final IconData? icon;
  final VoidCallback onTap;

  const _KeyButton({this.label, this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) => OutlinedButton(
    onPressed: onTap,
    style: OutlinedButton.styleFrom(
      backgroundColor: Colors.white,
      foregroundColor: const Color(0xFF17242C),
      side: const BorderSide(color: Color(0xFFE0E7EA)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
    ),
    child: icon == null
        ? Text(
            label!,
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
          )
        : Icon(icon),
  );
}

class _SaleSummary extends StatelessWidget {
  final double totalUsd;
  final VoidCallback? onCheckout;

  const _SaleSummary({required this.totalUsd, required this.onCheckout});

  @override
  Widget build(BuildContext context) {
    final currencyCode = AppCurrencyScope.of(context);
    final rate = AppCurrency.rateFor(currencyCode);
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Colors.grey.shade200)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .05),
              blurRadius: 16,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Row(
          children: [
            const Icon(Icons.shopping_bag_outlined, color: Color(0xFF138A55)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Total de la venta',
                    style: TextStyle(fontSize: 12, color: Color(0xFF687880)),
                  ),
                  Text(
                    '${AppCurrency.format(totalUsd, code: AppCurrency.baseCode)}'
                    '${currencyCode == AppCurrency.baseCode ? '' : ' · ${AppCurrency.format(totalUsd * rate, code: currencyCode)}'}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
            FilledButton(
              onPressed: onCheckout,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF138A55),
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 14,
                ),
              ),
              child: const Text('Cobrar'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyScale extends StatelessWidget {
  final VoidCallback onAddProduct;

  const _EmptyScale({required this.onAddProduct});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 430),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: const Color(0xFFE7F7EF),
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Icon(
                Icons.scale_rounded,
                size: 38,
                color: Color(0xFF138A55),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Todavía no hay artículos por peso',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            const Text(
              'Crea o edita un producto y configura su unidad de venta como kg o g. '
              'También puedes asignar esas unidades a las variaciones.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onAddProduct,
              icon: const Icon(Icons.add),
              label: const Text('Ir a productos'),
            ),
          ],
        ),
      ),
    ),
  );
}

BoxDecoration _cardDecoration() => BoxDecoration(
  color: Colors.white,
  borderRadius: BorderRadius.circular(20),
  border: Border.all(color: const Color(0xFFE6ECEE)),
  boxShadow: [
    BoxShadow(
      color: Colors.black.withValues(alpha: .035),
      blurRadius: 18,
      offset: const Offset(0, 6),
    ),
  ],
);

String _formatWeightAmount(double value) => value == value.roundToDouble()
    ? value.toStringAsFixed(0)
    : value
          .toStringAsFixed(3)
          .replaceFirst(RegExp(r'0+$'), '')
          .replaceFirst(RegExp(r'\.$'), '');
