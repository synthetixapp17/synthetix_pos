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

enum _ProductSort { name, priceAscending, priceDescending, stockAscending }

class _ProductListPageState extends State<ProductListPage> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedCategory = 'Todas';
  _InventoryFilter _inventoryFilter = _InventoryFilter.all;
  _ProductSort _productSort = _ProductSort.name;

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

  String get _sortLabel => switch (_productSort) {
    _ProductSort.name => 'Nombre',
    _ProductSort.priceAscending => 'Menor precio',
    _ProductSort.priceDescending => 'Mayor precio',
    _ProductSort.stockAscending => 'Menor stock',
  };

  @override
  Widget build(BuildContext context) {
    AppCurrencyScope.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1280),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                  child: Row(
                    children: [
                      if (MediaQuery.sizeOf(context).width < 800) ...[
                        IconButton(
                          tooltip: 'Volver',
                          onPressed: () => context.pop(),
                          icon: const Icon(Icons.arrow_back),
                        ),
                        const SizedBox(width: 4),
                      ],
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.showsLowStock ? 'Stock bajo' : 'Productos',
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              widget.showsLowStock
                                  ? 'Revisa los productos que necesitan reposición.'
                                  : 'Administra tu catálogo e inventario.',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      if (!widget.showsLowStock) const SizedBox(width: 12),
                      if (!widget.showsLowStock &&
                          MediaQuery.sizeOf(context).width < 500)
                        IconButton.filled(
                          tooltip: 'Agregar producto',
                          onPressed: () => context.push('/products/add'),
                          icon: const Icon(Icons.add),
                        ),
                      if (!widget.showsLowStock &&
                          MediaQuery.sizeOf(context).width >= 500)
                        FilledButton.icon(
                          onPressed: () => context.push('/products/add'),
                          icon: const Icon(Icons.add, size: 19),
                          label: const Text('Agregar producto'),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
                  child: BlocBuilder<ProductBloc, ProductState>(
                    builder: (context, state) {
                      return Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Theme.of(context).colorScheme.outlineVariant,
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _searchController,
                                textCapitalization: TextCapitalization.words,
                                decoration: InputDecoration(
                                  hintText: widget.showsLowStock
                                      ? 'Buscar en stock bajo'
                                      : 'Buscar por nombre, código o categoría',
                                  prefixIcon: const Icon(Icons.search),
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  filled: false,
                                  suffixIcon: _searchQuery.isEmpty
                                      ? null
                                      : IconButton(
                                          tooltip: 'Limpiar búsqueda',
                                          onPressed: () =>
                                              _searchController.clear(),
                                          icon: const Icon(Icons.close),
                                        ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Tooltip(
                              message: 'Escanear código de barras',
                              child: IconButton.filledTonal(
                                onPressed: () => _scanQR(state.products),
                                icon: const Icon(Icons.qr_code_scanner),
                                style: IconButton.styleFrom(
                                  minimumSize: const Size(48, 48),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),

                if (!widget.showsLowStock)
                  BlocBuilder<ProductBloc, ProductState>(
                    builder: (context, state) {
                      if (state.products.isEmpty) {
                        return const SizedBox.shrink();
                      }
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
                      final categories =
                          state.products
                              .map((product) => product.category.trim())
                              .where((category) => category.isNotEmpty)
                              .toSet()
                              .toList()
                            ..sort();
                      return Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(24, 16, 24, 4),
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                final columns = constraints.maxWidth >= 900
                                    ? 4
                                    : 2;
                                final cardWidth =
                                    (constraints.maxWidth -
                                        (columns - 1) * 14) /
                                    columns;
                                final metrics = [
                                  (
                                    'Productos',
                                    '${state.products.length}',
                                    Icons.inventory_2_outlined,
                                    const Color(0xFF3977D5),
                                  ),
                                  (
                                    'Unidades en inventario',
                                    '$units',
                                    Icons.stacked_bar_chart_rounded,
                                    const Color(0xFF1E9B72),
                                  ),
                                  (
                                    'Stock bajo',
                                    '$lowStock',
                                    Icons.warning_amber_rounded,
                                    const Color(0xFFE59B36),
                                  ),
                                  (
                                    'Agotados',
                                    '$outOfStock',
                                    Icons.remove_shopping_cart_outlined,
                                    const Color(0xFFC94B52),
                                  ),
                                ];
                                return Wrap(
                                  spacing: 14,
                                  runSpacing: 14,
                                  children: metrics
                                      .map(
                                        (metric) => _InventoryMetric(
                                          width: cardWidth,
                                          label: metric.$1,
                                          value: metric.$2,
                                          icon: metric.$3,
                                          color: metric.$4,
                                        ),
                                      )
                                      .toList(),
                                );
                              },
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(24, 14, 24, 14),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.surface,
                                border: Border.all(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.outlineVariant,
                                ),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        'Filtrar productos',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleSmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                      const Spacer(),
                                      if (categories.isNotEmpty)
                                        SizedBox(
                                          width: 150,
                                          child: DropdownButtonHideUnderline(
                                            child: DropdownButton<String>(
                                              isExpanded: true,
                                              value:
                                                  [
                                                    'Todas',
                                                    ...categories,
                                                  ].contains(_selectedCategory)
                                                  ? _selectedCategory
                                                  : 'Todas',
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              icon: const Icon(
                                                Icons.keyboard_arrow_down,
                                              ),
                                              items: ['Todas', ...categories]
                                                  .map(
                                                    (category) =>
                                                        DropdownMenuItem(
                                                          value: category,
                                                          child: Text(
                                                            category,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                          ),
                                                        ),
                                                  )
                                                  .toList(),
                                              onChanged: (category) {
                                                if (category != null) {
                                                  setState(
                                                    () => _selectedCategory =
                                                        category,
                                                  );
                                                }
                                              },
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Wrap(
                                    spacing: 10,
                                    runSpacing: 8,
                                    children: [
                                      _InventoryFilterChip(
                                        label:
                                            'Todos · ${state.products.length}',
                                        selected:
                                            _inventoryFilter ==
                                            _InventoryFilter.all,
                                        onSelected: () => setState(
                                          () => _inventoryFilter =
                                              _InventoryFilter.all,
                                        ),
                                      ),
                                      _InventoryFilterChip(
                                        label: 'Disponibles · $available',
                                        selected:
                                            _inventoryFilter ==
                                            _InventoryFilter.healthy,
                                        onSelected: () => setState(
                                          () => _inventoryFilter =
                                              _InventoryFilter.healthy,
                                        ),
                                      ),
                                      _InventoryFilterChip(
                                        label: 'Stock bajo · $lowStock',
                                        selected:
                                            _inventoryFilter ==
                                            _InventoryFilter.lowStock,
                                        onSelected: () => setState(
                                          () => _inventoryFilter =
                                              _InventoryFilter.lowStock,
                                        ),
                                      ),
                                      _InventoryFilterChip(
                                        label: 'Agotados · $outOfStock',
                                        selected:
                                            _inventoryFilter ==
                                            _InventoryFilter.outOfStock,
                                        onSelected: () => setState(
                                          () => _inventoryFilter =
                                              _InventoryFilter.outOfStock,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
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
                          child: Text(
                            'Aún no hay productos. Agrega el primero.',
                          ),
                        );
                      }

                      final lowStockThreshold = widget.lowStockThreshold;
                      final inventoryThreshold =
                          HiveDatabase.settingsBox.get(
                                'low_stock_threshold',
                                defaultValue: 5,
                              )
                              as int;
                      final stockWarningThreshold =
                          widget.lowStockThreshold ?? inventoryThreshold;
                      final availableCategories = state.products
                          .map((product) => product.category.trim())
                          .where((category) => category.isNotEmpty)
                          .toSet();
                      final activeCategory =
                          availableCategories.contains(_selectedCategory)
                          ? _selectedCategory
                          : 'Todas';
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
                                (activeCategory == 'Todas' ||
                                    product.category == activeCategory) &&
                                (product.name.toLowerCase().contains(
                                      _searchQuery,
                                    ) ||
                                    product.barcode.toLowerCase().contains(
                                      _searchQuery,
                                    ) ||
                                    product.category.toLowerCase().contains(
                                      _searchQuery,
                                    ) ||
                                    product.description.toLowerCase().contains(
                                      _searchQuery,
                                    )),
                          )
                          .toList();
                      filteredProducts.sort((first, second) {
                        return switch (_productSort) {
                          _ProductSort.name =>
                            first.name.toLowerCase().compareTo(
                              second.name.toLowerCase(),
                            ),
                          _ProductSort.priceAscending => first.price.compareTo(
                            second.price,
                          ),
                          _ProductSort.priceDescending =>
                            second.price.compareTo(first.price),
                          _ProductSort.stockAscending => first.stock.compareTo(
                            second.stock,
                          ),
                        };
                      });

                      if (filteredProducts.isEmpty) {
                        return Center(
                          child: Text(
                            widget.showsLowStock
                                ? 'No hay productos con stock por debajo de ${widget.lowStockThreshold} unidades.'
                                : 'No hay productos que coincidan con la búsqueda.',
                          ),
                        );
                      }

                      return Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(28, 8, 28, 10),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Catálogo',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleLarge
                                            ?.copyWith(
                                              fontWeight: FontWeight.w800,
                                            ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${filteredProducts.length} productos encontrados',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.onSurfaceVariant,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                                PopupMenuButton<_ProductSort>(
                                  tooltip: 'Ordenar productos',
                                  onSelected: (sort) =>
                                      setState(() => _productSort = sort),
                                  itemBuilder: (context) => [
                                    _sortMenuItem(
                                      _ProductSort.name,
                                      'Nombre A-Z',
                                    ),
                                    _sortMenuItem(
                                      _ProductSort.priceAscending,
                                      'Precio: menor a mayor',
                                    ),
                                    _sortMenuItem(
                                      _ProductSort.priceDescending,
                                      'Precio: mayor a menor',
                                    ),
                                    _sortMenuItem(
                                      _ProductSort.stockAscending,
                                      'Existencias: menor a mayor',
                                    ),
                                  ],
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 9,
                                    ),
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.outlineVariant,
                                      ),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.sort, size: 18),
                                        const SizedBox(width: 6),
                                        Text(
                                          _sortLabel,
                                          style: Theme.of(
                                            context,
                                          ).textTheme.labelLarge,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: ListView.separated(
                              padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
                              itemCount: filteredProducts.length,
                              separatorBuilder: (context, index) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (context, index) {
                                final product = filteredProducts[index];
                                final productDetails = [
                                  if (product.category.isNotEmpty)
                                    product.category,
                                  if (product.barcode.isNotEmpty)
                                    'Código ${product.barcode}',
                                ].join(' · ');
                                final stockColor = product.stock <= 0
                                    ? const Color(0xFFC94B52)
                                    : product.stock < stockWarningThreshold
                                    ? const Color(0xFFE59B36)
                                    : const Color(0xFF1E9B72);
                                final stockLabel = product.stock <= 0
                                    ? 'Agotado'
                                    : product.stock < stockWarningThreshold
                                    ? 'Stock bajo · ${product.stock}'
                                    : '${product.stock} en stock';
                                return Card(
                                  elevation: 0,
                                  margin: EdgeInsets.zero,
                                  shape: RoundedRectangleBorder(
                                    side: BorderSide(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.outlineVariant,
                                    ),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                    child: Row(
                                      children: [
                                        _ProductThumbnail(
                                          imageData: product.imageData,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                product.name,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .titleSmall
                                                    ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                              ),
                                              const SizedBox(height: 3),
                                              Text(
                                                productDetails.isEmpty
                                                    ? 'Sin categoría ni código'
                                                    : productDetails,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodySmall
                                                    ?.copyWith(
                                                      color: Theme.of(context)
                                                          .colorScheme
                                                          .onSurfaceVariant,
                                                    ),
                                              ),
                                              const SizedBox(height: 8),
                                              Wrap(
                                                spacing: 10,
                                                runSpacing: 4,
                                                crossAxisAlignment:
                                                    WrapCrossAlignment.center,
                                                children: [
                                                  Text(
                                                    AppCurrency.formatConfigured(
                                                      product.price,
                                                    ),
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .titleSmall
                                                        ?.copyWith(
                                                          fontWeight:
                                                              FontWeight.w800,
                                                          color: Theme.of(
                                                            context,
                                                          ).colorScheme.primary,
                                                        ),
                                                  ),
                                                  Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 8,
                                                          vertical: 3,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      color: stockColor
                                                          .withValues(
                                                            alpha: .1,
                                                          ),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            20,
                                                          ),
                                                    ),
                                                    child: Text(
                                                      stockLabel,
                                                      style: Theme.of(context)
                                                          .textTheme
                                                          .labelSmall
                                                          ?.copyWith(
                                                            color: stockColor,
                                                            fontWeight:
                                                                FontWeight.w700,
                                                          ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                        PopupMenuButton<String>(
                                          tooltip: 'Acciones del producto',
                                          onSelected: (action) {
                                            if (action == 'edit') {
                                              context.push(
                                                '/products/edit/${product.id}',
                                                extra: product,
                                              );
                                            } else {
                                              _confirmDelete(context, product);
                                            }
                                          },
                                          itemBuilder: (context) => const [
                                            PopupMenuItem(
                                              value: 'edit',
                                              child: ListTile(
                                                leading: Icon(
                                                  Icons.edit_outlined,
                                                ),
                                                title: Text('Editar'),
                                                contentPadding: EdgeInsets.zero,
                                              ),
                                            ),
                                            PopupMenuItem(
                                              value: 'delete',
                                              child: ListTile(
                                                leading: Icon(
                                                  Icons.delete_outline,
                                                  color: Colors.red,
                                                ),
                                                title: Text('Eliminar'),
                                                contentPadding: EdgeInsets.zero,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  PopupMenuItem<_ProductSort> _sortMenuItem(_ProductSort sort, String label) {
    return PopupMenuItem(
      value: sort,
      child: Row(
        children: [
          SizedBox(
            width: 24,
            child: _productSort == sort
                ? Icon(Icons.check, size: 18, color: AppTheme.primaryColor)
                : null,
          ),
          Text(label),
        ],
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
    final theme = Theme.of(context);
    return Container(
      width: width,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 21, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
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
      width: 60,
      height: 60,
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
