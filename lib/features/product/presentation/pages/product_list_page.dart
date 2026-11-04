import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/data/hive_database.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/app_currency.dart';
import '../../domain/entities/product.dart';
import '../bloc/product_bloc.dart';

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
      setState(() => _searchQuery = _searchController.text.toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _scanQR(List<Product> products) async {
    final barcode = await context.push<String>('/scan-code');
    if (barcode == null || barcode.isEmpty || !mounted) return;
    final product = products
        .where((item) => item.barcode == barcode)
        .firstOrNull;
    _searchController.text = product?.name ?? barcode;
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
    final theme = Theme.of(context);
    final pageWidth = MediaQuery.sizeOf(context).width;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1280),
            child: BlocConsumer<ProductBloc, ProductState>(
              listener: (context, state) {
                if ((state.status == ProductStatus.success ||
                        state.status == ProductStatus.error) &&
                    state.message != null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(state.message!),
                      backgroundColor: state.status == ProductStatus.success
                          ? Colors.green
                          : Colors.red,
                    ),
                  );
                }
              },
              builder: (context, state) {
                final inventoryThreshold =
                    HiveDatabase.settingsBox.get(
                          'low_stock_threshold',
                          defaultValue: 5,
                        )
                        as int;
                final stockThreshold =
                    widget.lowStockThreshold ?? inventoryThreshold;
                final products = state.products;
                final categories =
                    products
                        .map((product) => product.category.trim())
                        .where((category) => category.isNotEmpty)
                        .toSet()
                        .toList()
                      ..sort();
                final selectedCategory = categories.contains(_selectedCategory)
                    ? _selectedCategory
                    : 'Todas';
                final filteredProducts = products.where((product) {
                  final matchesStock = widget.lowStockThreshold != null
                      ? product.stock < widget.lowStockThreshold!
                      : switch (_inventoryFilter) {
                          _InventoryFilter.all => true,
                          _InventoryFilter.healthy =>
                            product.stock >= inventoryThreshold,
                          _InventoryFilter.lowStock =>
                            product.stock > 0 &&
                                product.stock < inventoryThreshold,
                          _InventoryFilter.outOfStock => product.stock <= 0,
                        };
                  final queryMatches =
                      product.name.toLowerCase().contains(_searchQuery) ||
                      product.barcode.toLowerCase().contains(_searchQuery) ||
                      product.category.toLowerCase().contains(_searchQuery) ||
                      product.description.toLowerCase().contains(_searchQuery);
                  return matchesStock &&
                      (selectedCategory == 'Todas' ||
                          product.category == selectedCategory) &&
                      queryMatches;
                }).toList()..sort(_compareProducts);

                final slivers = <Widget>[
                  SliverToBoxAdapter(
                    child: _buildPageHeader(context, pageWidth),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
                      child: _buildSearch(context, products),
                    ),
                  ),
                ];

                if (!widget.showsLowStock && products.isNotEmpty) {
                  slivers.add(
                    SliverToBoxAdapter(
                      child: _buildInventoryOverview(
                        context,
                        products,
                        categories,
                        inventoryThreshold,
                      ),
                    ),
                  );
                }

                if (state.status == ProductStatus.loading && products.isEmpty) {
                  slivers.add(
                    const SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  );
                } else if (products.isEmpty) {
                  slivers.add(
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _EmptyProducts(
                        hasError: state.status == ProductStatus.error,
                        message: state.message,
                        onAdd: widget.showsLowStock
                            ? null
                            : () => context.push('/products/add'),
                      ),
                    ),
                  );
                } else if (filteredProducts.isEmpty) {
                  slivers.add(
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            widget.showsLowStock
                                ? 'No hay productos con stock por debajo de ${widget.lowStockThreshold} unidades.'
                                : 'No hay productos que coincidan con los filtros.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                } else {
                  slivers.addAll([
                    SliverToBoxAdapter(
                      child: _buildCatalogHeader(
                        context,
                        filteredProducts.length,
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) => Padding(
                            padding: EdgeInsets.only(
                              bottom: index == filteredProducts.length - 1
                                  ? 0
                                  : 10,
                            ),
                            child: _ProductCard(
                              product: filteredProducts[index],
                              stockThreshold: stockThreshold,
                              onEdit: () => context.push(
                                '/products/edit/${filteredProducts[index].id}',
                                extra: filteredProducts[index],
                              ),
                              onDelete: () => _confirmDelete(
                                context,
                                filteredProducts[index],
                              ),
                            ),
                          ),
                          childCount: filteredProducts.length,
                        ),
                      ),
                    ),
                  ]);
                }

                return CustomScrollView(slivers: slivers);
              },
            ),
          ),
        ),
      ),
    );
  }

  int _compareProducts(Product first, Product second) => switch (_productSort) {
    _ProductSort.name => first.name.toLowerCase().compareTo(
      second.name.toLowerCase(),
    ),
    _ProductSort.priceAscending => first.price.compareTo(second.price),
    _ProductSort.priceDescending => second.price.compareTo(first.price),
    _ProductSort.stockAscending => first.stock.compareTo(second.stock),
  };

  Widget _buildPageHeader(BuildContext context, double pageWidth) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(pageWidth < 600 ? 12 : 28, 20, 24, 16),
      child: Row(
        children: [
          if (pageWidth < 800) ...[
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
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.showsLowStock
                      ? 'Revisa los productos que necesitan reposición.'
                      : 'Administra tu catálogo e inventario.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (!widget.showsLowStock && pageWidth < 500)
            IconButton.filled(
              tooltip: 'Agregar producto',
              onPressed: () => context.push('/products/add'),
              icon: const Icon(Icons.add),
            )
          else if (!widget.showsLowStock)
            FilledButton.icon(
              onPressed: () => context.push('/products/add'),
              icon: const Icon(Icons.add, size: 19),
              label: const Text('Agregar producto'),
            ),
        ],
      ),
    );
  }

  Widget _buildSearch(BuildContext context, List<Product> products) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
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
                        onPressed: _searchController.clear,
                        icon: const Icon(Icons.close),
                      ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Tooltip(
            message: 'Escanear código de barras',
            child: IconButton.filledTonal(
              onPressed: () => _scanQR(products),
              icon: const Icon(Icons.qr_code_scanner),
              style: IconButton.styleFrom(
                minimumSize: const Size(48, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(11),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInventoryOverview(
    BuildContext context,
    List<Product> products,
    List<String> categories,
    int threshold,
  ) {
    final lowStock = products
        .where((product) => product.stock > 0 && product.stock < threshold)
        .length;
    final outOfStock = products.where((product) => product.stock <= 0).length;
    final available = products
        .where((product) => product.stock >= threshold)
        .length;
    final units = products.fold<int>(
      0,
      (total, product) => total + product.stock,
    );
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              const spacing = 12.0;
              final columns = constraints.maxWidth < 560 ? 2 : 4;
              final width =
                  (constraints.maxWidth - spacing * (columns - 1)) / columns;
              final metrics = [
                (
                  'Productos',
                  '${products.length}',
                  Icons.inventory_2_outlined,
                  const Color(0xFF3977D5),
                ),
                (
                  'Unidades',
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
                spacing: spacing,
                runSpacing: spacing,
                children: [
                  for (final metric in metrics)
                    _InventoryMetric(
                      width: width,
                      label: metric.$1,
                      value: metric.$2,
                      icon: metric.$3,
                      color: metric.$4,
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border.all(color: theme.colorScheme.outlineVariant),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Filtrar catálogo',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    if (categories.isNotEmpty) ...[
                      const Icon(Icons.category_outlined, size: 18),
                      const SizedBox(width: 6),
                      SizedBox(
                        width: 140,
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
                            borderRadius: BorderRadius.circular(12),
                            items: ['Todas', ...categories]
                                .map(
                                  (category) => DropdownMenuItem(
                                    value: category,
                                    child: Text(
                                      category,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (category) {
                              if (category != null) {
                                setState(() => _selectedCategory = category);
                              }
                            },
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    _InventoryFilterChip(
                      label: 'Todos · ${products.length}',
                      selected: _inventoryFilter == _InventoryFilter.all,
                      onSelected: () => setState(
                        () => _inventoryFilter = _InventoryFilter.all,
                      ),
                    ),
                    _InventoryFilterChip(
                      label: 'Disponibles · $available',
                      selected: _inventoryFilter == _InventoryFilter.healthy,
                      onSelected: () => setState(
                        () => _inventoryFilter = _InventoryFilter.healthy,
                      ),
                    ),
                    _InventoryFilterChip(
                      label: 'Stock bajo · $lowStock',
                      selected: _inventoryFilter == _InventoryFilter.lowStock,
                      onSelected: () => setState(
                        () => _inventoryFilter = _InventoryFilter.lowStock,
                      ),
                    ),
                    _InventoryFilterChip(
                      label: 'Agotados · $outOfStock',
                      selected: _inventoryFilter == _InventoryFilter.outOfStock,
                      onSelected: () => setState(
                        () => _inventoryFilter = _InventoryFilter.outOfStock,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCatalogHeader(BuildContext context, int count) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 12, 24, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Catálogo',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$count ${count == 1 ? 'producto' : 'productos'}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          PopupMenuButton<_ProductSort>(
            tooltip: 'Ordenar productos',
            onSelected: (sort) => setState(() => _productSort = sort),
            itemBuilder: (context) => [
              _sortMenuItem(_ProductSort.name, 'Nombre A-Z'),
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
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                border: Border.all(color: theme.colorScheme.outlineVariant),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.sort, size: 18),
                  const SizedBox(width: 6),
                  Text(_sortLabel, style: theme.textTheme.labelLarge),
                ],
              ),
            ),
          ),
        ],
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
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Eliminar producto'),
        content: Text('¿Deseas eliminar ${product.name}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () {
              context.read<ProductBloc>().add(DeleteProduct(product.id));
              Navigator.pop(dialogContext);
            },
            child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

class _EmptyProducts extends StatelessWidget {
  final bool hasError;
  final String? message;
  final VoidCallback? onAdd;

  const _EmptyProducts({
    required this.hasError,
    required this.message,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hasError ? Icons.error_outline : Icons.inventory_2_outlined,
              size: 44,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              hasError
                  ? 'No se pudieron cargar los productos'
                  : 'Catálogo vacío',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              hasError
                  ? message ?? 'Inténtalo de nuevo.'
                  : 'Agrega el primer producto para empezar a administrar tu inventario.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            if (onAdd != null) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add),
                label: const Text('Agregar producto'),
              ),
            ],
          ],
        ),
      ),
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
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .1),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, size: 19, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
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
  Widget build(BuildContext context) => ChoiceChip(
    label: Text(label),
    selected: selected,
    onSelected: (_) => onSelected(),
  );
}

class _ProductCard extends StatelessWidget {
  final Product product;
  final int stockThreshold;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ProductCard({
    required this.product,
    required this.stockThreshold,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stockColor = product.stock <= 0
        ? const Color(0xFFC94B52)
        : product.stock < stockThreshold
        ? const Color(0xFFE59B36)
        : const Color(0xFF1E9B72);
    final stockLabel = product.stock <= 0
        ? 'Agotado'
        : product.stock < stockThreshold
        ? 'Stock bajo · ${product.stock}'
        : '${product.stock} en stock';
    final details = [
      if (product.category.isNotEmpty) product.category,
      if (product.barcode.isNotEmpty) 'Código ${product.barcode}',
    ].join(' · ');

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            _ProductThumbnail(imageData: product.imageData),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    product.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    details.isEmpty ? 'Sin categoría ni código' : details,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 10,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        AppCurrency.formatConfigured(product.price),
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: stockColor.withValues(alpha: .1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          stockLabel,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: stockColor,
                            fontWeight: FontWeight.w700,
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
              onSelected: (action) => action == 'edit' ? onEdit() : onDelete(),
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: 'edit',
                  child: ListTile(
                    leading: Icon(Icons.edit_outlined),
                    title: Text('Editar'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: ListTile(
                    leading: Icon(Icons.delete_outline, color: Colors.red),
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
  }
}

class _ProductThumbnail extends StatelessWidget {
  final String? imageData;

  const _ProductThumbnail({required this.imageData});

  @override
  Widget build(BuildContext context) {
    final image = imageData;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 60,
        height: 60,
        child: image == null || image.isEmpty
            ? ColoredBox(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Icon(
                  Icons.inventory_2_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
              )
            : Image.memory(
                base64Decode(image),
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => ColoredBox(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: const Icon(Icons.broken_image_outlined),
                ),
              ),
      ),
    );
  }
}
