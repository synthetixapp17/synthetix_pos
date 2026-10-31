import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../bloc/product_bloc.dart';
import '../../domain/entities/product.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/data/hive_database.dart';
import '../../../../core/utils/app_currency.dart';

class ProductListPage extends StatefulWidget {
  final int? lowStockThreshold;

  const ProductListPage({super.key, this.lowStockThreshold});

  bool get showsLowStock => lowStockThreshold != null;

  @override
  State<ProductListPage> createState() => _ProductListPageState();
}

enum _InventoryFilter { all, healthy, lowStock, outOfStock }

class _ProductListPageState extends State<ProductListPage> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedCategory = 'Todas';
  _InventoryFilter _inventoryFilter = _InventoryFilter.all;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _scanQR(List<Product> products) async {
    final barcode = await context.push<String>('/scan-code');
    if (barcode != null && barcode.isNotEmpty) {
      final matchedProduct = products
          .where((p) => p.barcode == barcode)
          .firstOrNull;
      if (matchedProduct != null) {
        _searchController.text = matchedProduct.name;
      } else {
        _searchController.text =
            barcode; // If not found, just put barcode in search
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    AppCurrencyScope.of(context);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.chevron_left,
            size: 28,
            color: Theme.of(context).primaryColor,
          ),
          onPressed: () => context.pop(),
        ),
        title: Text(
          widget.showsLowStock ? 'Productos con stock bajo' : 'Productos',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: BlocBuilder<ProductBloc, ProductState>(
              builder: (context, state) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _searchController,
                            textCapitalization: TextCapitalization.words,
                            decoration: InputDecoration(
                              hintText: widget.showsLowStock
                                  ? 'Buscar en stock bajo'
                                  : 'Buscar por nombre o código',
                              prefixIcon: Icon(
                                Icons.search,
                                color: Colors.grey[400],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Container(
                          decoration: BoxDecoration(
                            color: AppTheme.primaryColor.withValues(
                              alpha: 0.05,
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: IconButton(
                            icon: Icon(
                              Icons.qr_code_scanner,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            onPressed: () => _scanQR(state.products),
                            padding: const EdgeInsets.all(15),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Pulsa el icono para escanear un código',
                      style: TextStyle(fontSize: 12, color: Color(0xFF4C669A)),
                    ),
                  ],
                );
              },
            ),
          ),

          if (!widget.showsLowStock)
            BlocBuilder<ProductBloc, ProductState>(
              builder: (context, state) {
                if (state.products.isEmpty) return const SizedBox.shrink();
                final threshold =
                    HiveDatabase.settingsBox.get(
                          'low_stock_threshold',
                          defaultValue: 5,
                        )
                        as int;
                final available = state.products
                    .where((product) => product.stock >= threshold)
                    .length;
                final lowStock = state.products
                    .where(
                      (product) =>
                          product.stock > 0 && product.stock < threshold,
                    )
                    .length;
                final outOfStock = state.products
                    .where((product) => product.stock <= 0)
                    .length;
                final units = state.products.fold<int>(
                  0,
                  (total, product) => total + product.stock,
                );
                final categories = state.products
                    .map((product) => product.category.trim())
                    .where((category) => category.isNotEmpty)
                    .toSet()
                    .toList()
                  ..sort();
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final width = (constraints.maxWidth - 12) / 2;
                          return Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              _InventoryMetric(
                                width: width,
                                label: 'Referencias',
                                value: '${state.products.length}',
                                icon: Icons.inventory_2_outlined,
                                color: const Color(0xFF3977D5),
                              ),
                              _InventoryMetric(
                                width: width,
                                label: 'Unidades disponibles',
                                value: '$units',
                                icon: Icons.stacked_bar_chart_rounded,
                                color: const Color(0xFF1E9B72),
                              ),
                              _InventoryMetric(
                                width: width,
                                label: 'Stock bajo',
                                value: '$lowStock',
                                icon: Icons.warning_amber_rounded,
                                color: const Color(0xFFE59B36),
                              ),
                              _InventoryMetric(
                                width: width,
                                label: 'Agotados',
                                value: '$outOfStock',
                                icon: Icons.remove_shopping_cart_outlined,
                                color: const Color(0xFFC94B52),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                    if (categories.isNotEmpty)
                      SizedBox(
                        height: 46,
                        child: ListView(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          scrollDirection: Axis.horizontal,
                          children: ['Todas', ...categories]
                              .map(
                                (category) => Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: ChoiceChip(
                                    label: Text(category),
                                    selected: _selectedCategory == category,
                                    onSelected: (_) => setState(
                                      () => _selectedCategory = category,
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ),
                    SizedBox(
                      height: 46,
                      child: ListView(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        scrollDirection: Axis.horizontal,
                        children: [
                          _InventoryFilterChip(
                            label: 'Todos',
                            selected:
                                _inventoryFilter == _InventoryFilter.all,
                            onSelected: () => setState(
                              () => _inventoryFilter = _InventoryFilter.all,
                            ),
                          ),
                          _InventoryFilterChip(
                            label: 'Disponibles $available',
                            selected:
                                _inventoryFilter == _InventoryFilter.healthy,
                            onSelected: () => setState(
                              () => _inventoryFilter =
                                  _InventoryFilter.healthy,
                            ),
                          ),
                          _InventoryFilterChip(
                            label: 'Stock bajo $lowStock',
                            selected:
                                _inventoryFilter == _InventoryFilter.lowStock,
                            onSelected: () => setState(
                              () => _inventoryFilter =
                                  _InventoryFilter.lowStock,
                            ),
                          ),
                          _InventoryFilterChip(
                            label: 'Agotados $outOfStock',
                            selected: _inventoryFilter ==
                                _InventoryFilter.outOfStock,
                            onSelected: () => setState(
                              () => _inventoryFilter =
                                  _InventoryFilter.outOfStock,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),

          Expanded(
            child: BlocConsumer<ProductBloc, ProductState>(
              listener: (context, state) {
                if (state.status == ProductStatus.success &&
                    state.message != null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(state.message!),
                      backgroundColor: Colors.green,
                    ),
                  );
                } else if (state.status == ProductStatus.error &&
                    state.message != null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(state.message!),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              },
              builder: (context, state) {
                if (state.status == ProductStatus.loading &&
                    state.products.isEmpty) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (state.products.isEmpty) {
                  if (state.status == ProductStatus.error) {
                    return Center(child: Text('Error: ${state.message}'));
                  }
                  return const Center(
                    child: Text('Aún no hay productos. Agrega el primero.'),
                  );
                }

                final lowStockThreshold = widget.lowStockThreshold;
                final inventoryThreshold =
                    HiveDatabase.settingsBox.get(
                          'low_stock_threshold',
                          defaultValue: 5,
                        )
                        as int;
                final filteredProducts = state.products
                    .where(
                      (product) =>
                          (lowStockThreshold == null ||
                              product.stock < lowStockThreshold) &&
                          (widget.showsLowStock ||
                              switch (_inventoryFilter) {
                                _InventoryFilter.all => true,
                                _InventoryFilter.healthy =>
                                  product.stock >= inventoryThreshold,
                                _InventoryFilter.lowStock =>
                                  product.stock > 0 &&
                                      product.stock < inventoryThreshold,
                                _InventoryFilter.outOfStock =>
                                  product.stock <= 0,
                              }) &&
                          (_selectedCategory == 'Todas' ||
                              product.category == _selectedCategory) &&
                          (product.name.toLowerCase().contains(_searchQuery) ||
                              product.barcode.toLowerCase().contains(
                                _searchQuery,
                              ) ||
                              product.category.toLowerCase().contains(
                                _searchQuery,
                              )),
                    )
                    .toList();

                if (filteredProducts.isEmpty) {
                  return Center(
                    child: Text(
                      widget.showsLowStock
                          ? 'No hay productos con stock por debajo de ${widget.lowStockThreshold} unidades.'
                          : 'No hay productos que coincidan con la búsqueda.',
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.only(
                    left: 16,
                    right: 16,
                    top: 8,
                    bottom: 100,
                  ),
                  itemCount: filteredProducts.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final product = filteredProducts[index];
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            _ProductThumbnail(imageData: product.imageData),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    product.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15,
                                    ),
                                  ),
                                  if (product.category.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primaryContainer,
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        product.category,
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall
                                            ?.copyWith(
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.onPrimaryContainer,
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                                    ),
                                  ],
                                  if (product.description.isNotEmpty) ...[
                                    const SizedBox(height: 3),
                                    Text(
                                      product.description,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodySmall,
                                    ),
                                  ],
                                  const SizedBox(height: 6),
                                  Text(
                                    AppCurrency.formatConfigured(product.price),
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                    ),
                                  ),
                                  Text(
                                    'Existencias: ${product.stock} · Código: ${product.barcode}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.labelSmall,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 6),
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: 'Editar producto',
                                  icon: const Icon(Icons.edit_outlined),
                                  onPressed: () => context.push(
                                    '/products/edit/${product.id}',
                                    extra: product,
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Eliminar producto',
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    color: Colors.red,
                                  ),
                                  onPressed: () =>
                                      _confirmDelete(context, product),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/products/add'),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
        shape: const CircleBorder(),
        child: const Icon(Icons.add, size: 32),
      ),
    );
  }

  void _confirmDelete(BuildContext context, Product product) {
    showDialog(
      context: context,
      builder: (innerContext) {
        return AlertDialog(
          title: const Text('Eliminar producto'),
          content: Text('¿Deseas eliminar ${product.name}?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(innerContext),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () {
                context.read<ProductBloc>().add(DeleteProduct(product.id));
                Navigator.pop(innerContext);
              },
              child: const Text(
                'Eliminar',
                style: TextStyle(color: Colors.red),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _InventoryMetric extends StatelessWidget {
  final double width;
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _InventoryMetric({
    required this.width,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 20, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InventoryFilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onSelected;

  const _InventoryFilterChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onSelected(),
      ),
    );
  }
}

class _ProductThumbnail extends StatelessWidget {
  final String? imageData;
  const _ProductThumbnail({required this.imageData});

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(12),
    child: SizedBox(
      width: 76,
      height: 82,
      child: imageData == null
          ? ColoredBox(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Icon(
                Icons.inventory_2_outlined,
                color: Theme.of(context).colorScheme.primary,
              ),
            )
          : Image.memory(base64Decode(imageData!), fit: BoxFit.cover),
    ),
  );
}
