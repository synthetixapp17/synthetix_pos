import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/data/hive_database.dart';
import '../../../../core/utils/app_currency.dart';
import '../../../billing/presentation/bloc/billing_bloc.dart';
import '../../../product/domain/entities/product.dart';
import '../../../product/presentation/bloc/product_bloc.dart';
import '../../../reports/data/models/sale_model.dart';

enum _CatalogFilter { all, available, lowStock, outOfStock }

enum _CatalogSort { popular, latest, bestSellers, price }

class ProductCatalogPage extends StatefulWidget {
  const ProductCatalogPage({super.key});

  @override
  State<ProductCatalogPage> createState() => _ProductCatalogPageState();
}

class _ProductCatalogPageState extends State<ProductCatalogPage> {
  final _searchController = TextEditingController();
  String _query = '';
  String _category = 'Todas';
  _CatalogFilter _filter = _CatalogFilter.all;
  _CatalogSort _sort = _CatalogSort.popular;
  bool _priceAscending = true;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  IconData _categoryIcon(String category) {
    final normalized = category.toLowerCase();
    if (normalized == 'todas') return Icons.grid_view_rounded;
    if (normalized.contains('zapato') || normalized.contains('shoe')) {
      return Icons.directions_walk_rounded;
    }
    if (normalized.contains('reloj') || normalized.contains('watch')) {
      return Icons.watch_rounded;
    }
    if (normalized.contains('bolso') || normalized.contains('bag')) {
      return Icons.backpack_rounded;
    }
    if (normalized.contains('belleza') ||
        normalized.contains('beauty') ||
        normalized.contains('cosm')) {
      return Icons.brush_outlined;
    }
    if (normalized.contains('ropa') ||
        normalized.contains('clothing') ||
        normalized.contains('vest')) {
      return Icons.checkroom_rounded;
    }
    if (normalized.contains('comida') ||
        normalized.contains('food') ||
        normalized.contains('alimento')) {
      return Icons.restaurant_rounded;
    }
    return Icons.category_outlined;
  }

  Future<void> _showFilters({
    required int availableCount,
    required int lowStockCount,
    required int outOfStockCount,
    required int totalCount,
  }) async {
    final selectedFilter = await showModalBottomSheet<_CatalogFilter>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final options = [
          (_CatalogFilter.all, 'Todos los productos', totalCount),
          (_CatalogFilter.available, 'Disponibles', availableCount),
          (_CatalogFilter.lowStock, 'Stock bajo', lowStockCount),
          (_CatalogFilter.outOfStock, 'Agotados', outOfStockCount),
        ];
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
                  child: Text(
                    'Filtrar productos',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                for (final (filter, label, count) in options)
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                    title: Text(label),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('$count'),
                        const SizedBox(width: 12),
                        if (_filter == filter)
                          Icon(
                            Icons.check_circle_rounded,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                      ],
                    ),
                    onTap: () => Navigator.pop(context, filter),
                  ),
              ],
            ),
          ),
        );
      },
    );
    if (selectedFilter != null && mounted) {
      setState(() => _filter = selectedFilter);
    }
  }

  @override
  Widget build(BuildContext context) {
    AppCurrencyScope.of(context);
    final threshold =
        HiveDatabase.settingsBox.get('low_stock_threshold', defaultValue: 5)
            as int;
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: BlocBuilder<ProductBloc, ProductState>(
        builder: (context, productState) {
          if (productState.status == ProductStatus.loading &&
              productState.products.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          if (productState.products.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.inventory_2_outlined,
                      size: 56,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      productState.status == ProductStatus.error
                          ? 'No se pudo cargar el catálogo'
                          : 'Aún no hay productos',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      productState.message ??
                          'Agrega productos al inventario para venderlos desde aquí.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      onPressed: () => context.push('/products/add'),
                      icon: const Icon(Icons.add),
                      label: const Text('Crear producto'),
                    ),
                  ],
                ),
              ),
            );
          }

          final categories =
              productState.products
                  .map((product) => product.category.trim())
                  .where((category) => category.isNotEmpty)
                  .toSet()
                  .toList()
                ..sort();
          final allTimeSales = <String, int>{};
          final recentSales = <String, int>{};
          final lastSoldAt = <String, DateTime>{};
          final recentSalesStart = DateTime.now().subtract(
            const Duration(days: 30),
          );
          for (final sale in HiveDatabase.salesBox.values) {
            for (final line in decodeSaleLines(sale.linesJson)) {
              allTimeSales.update(
                line.productId,
                (quantity) => quantity + line.quantity,
                ifAbsent: () => line.quantity,
              );
              if (!sale.soldAt.isBefore(recentSalesStart)) {
                recentSales.update(
                  line.productId,
                  (quantity) => quantity + line.quantity,
                  ifAbsent: () => line.quantity,
                );
              }
              final lastSale = lastSoldAt[line.productId];
              if (lastSale == null || sale.soldAt.isAfter(lastSale)) {
                lastSoldAt[line.productId] = sale.soldAt;
              }
            }
          }
          final visibleProducts =
              productState.products.where((product) {
                final query = _query.trim().toLowerCase();
                final matchesSearch =
                    query.isEmpty ||
                    product.name.toLowerCase().contains(query) ||
                    product.barcode.toLowerCase().contains(query) ||
                    product.category.toLowerCase().contains(query);
                final matchesCategory =
                    _category == 'Todas' || product.category == _category;
                final matchesFilter = switch (_filter) {
                  _CatalogFilter.all => true,
                  _CatalogFilter.available => product.stock > 0,
                  _CatalogFilter.lowStock =>
                    product.stock > 0 && product.stock < threshold,
                  _CatalogFilter.outOfStock => product.stock <= 0,
                };
                return matchesSearch && matchesCategory && matchesFilter;
              }).toList()..sort((first, second) {
                final salesComparison = switch (_sort) {
                  _CatalogSort.popular =>
                    (allTimeSales[second.id] ?? 0).compareTo(
                      allTimeSales[first.id] ?? 0,
                    ),
                  _CatalogSort.latest =>
                    (lastSoldAt[second.id]?.millisecondsSinceEpoch ?? 0)
                        .compareTo(
                          lastSoldAt[first.id]?.millisecondsSinceEpoch ?? 0,
                        ),
                  _CatalogSort.bestSellers =>
                    (recentSales[second.id] ?? 0).compareTo(
                      recentSales[first.id] ?? 0,
                    ),
                  _CatalogSort.price =>
                    _priceAscending
                        ? first.price.compareTo(second.price)
                        : second.price.compareTo(first.price),
                };
                if (salesComparison != 0) return salesComparison;
                return first.name.toLowerCase().compareTo(
                  second.name.toLowerCase(),
                );
              });

          final availableCount = productState.products
              .where((product) => product.stock > 0)
              .length;
          final lowStockCount = productState.products
              .where(
                (product) => product.stock > 0 && product.stock < threshold,
              )
              .length;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        onChanged: (value) => setState(() => _query = value),
                        decoration: InputDecoration(
                          hintText: 'What are you looking for?',
                          prefixIcon: const Icon(Icons.search_rounded),
                          suffixIcon: _query.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: 'Limpiar búsqueda',
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() => _query = '');
                                  },
                                  icon: const Icon(Icons.close_rounded),
                                ),
                          filled: true,
                          fillColor: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest
                              .withValues(alpha: 0.45),
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 16,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton.icon(
                      onPressed: () => _showFilters(
                        availableCount: availableCount,
                        lowStockCount: lowStockCount,
                        outOfStockCount:
                            productState.products.length - availableCount,
                        totalCount: productState.products.length,
                      ),
                      icon: const Icon(Icons.tune_rounded, size: 19),
                      label: const Text('Filter'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Theme.of(context).colorScheme.primary,
                        side: BorderSide(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 16,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 54,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    _SortTab(
                      label: 'Popular',
                      selected: _sort == _CatalogSort.popular,
                      onTap: () => setState(() => _sort = _CatalogSort.popular),
                    ),
                    _SortTab(
                      label: 'Latest',
                      selected: _sort == _CatalogSort.latest,
                      onTap: () => setState(() => _sort = _CatalogSort.latest),
                    ),
                    _SortTab(
                      label: 'Best Sellers',
                      selected: _sort == _CatalogSort.bestSellers,
                      onTap: () =>
                          setState(() => _sort = _CatalogSort.bestSellers),
                    ),
                    _SortTab(
                      label: _priceAscending ? 'Price ↑' : 'Price ↓',
                      selected: _sort == _CatalogSort.price,
                      onTap: () => setState(() {
                        if (_sort == _CatalogSort.price) {
                          _priceAscending = !_priceAscending;
                        }
                        _sort = _CatalogSort.price;
                      }),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 100,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  children: ['Todas', ...categories].map((category) {
                    return _CategoryButton(
                      label: category,
                      icon: _categoryIcon(category),
                      selected: _category == category,
                      onTap: () => setState(() => _category = category),
                    );
                  }).toList(),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 8),
                child: Row(
                  children: [
                    Text(
                      '${visibleProducts.length} productos',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      'Toca un producto para agregarlo',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: visibleProducts.isEmpty
                    ? const Center(
                        child: Text('No hay productos con estos filtros.'),
                      )
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          final gridWidth = constraints.maxWidth
                              .clamp(0.0, 1060.0)
                              .toDouble();
                          return Center(
                            child: SizedBox(
                              width: gridWidth,
                              child: GridView.builder(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  4,
                                  16,
                                  20,
                                ),
                                gridDelegate:
                                    const SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: 2,
                                      crossAxisSpacing: 14,
                                      mainAxisSpacing: 14,
                                      mainAxisExtent: 342,
                                    ),
                                itemCount: visibleProducts.length,
                                itemBuilder: (context, index) =>
                                    _CatalogProductCard(
                                      product: visibleProducts[index],
                                      threshold: threshold,
                                      soldCount:
                                          allTimeSales[visibleProducts[index]
                                              .id] ??
                                          0,
                                    ),
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
      bottomNavigationBar: BlocBuilder<BillingBloc, BillingState>(
        builder: (context, state) {
          if (state.cartItems.isEmpty) return const SizedBox.shrink();
          final quantity = state.cartItems.fold<int>(
            0,
            (total, item) => total + item.quantity,
          );
          return SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: FilledButton(
                onPressed: () => context.push('/checkout'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 15),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.shopping_bag_outlined),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Revisar venta · $quantity ${quantity == 1 ? 'producto' : 'productos'}',
                      ),
                    ),
                    Text(
                      AppCurrency.formatConfigured(state.totalAmount),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SortTab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SortTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 26),
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 11),
              child: Text(
                label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: selected ? colors.primary : colors.onSurfaceVariant,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ),
            Container(
              height: 2,
              width: label.length * 7.0,
              decoration: BoxDecoration(
                color: selected ? colors.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _CategoryButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      width: 76,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Column(
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: selected
                    ? colors.primary.withValues(alpha: 0.12)
                    : colors.surfaceContainerHighest.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(18),
                border: selected
                    ? Border.all(color: colors.primary, width: 1.2)
                    : null,
              ),
              child: Icon(
                icon,
                color: selected ? colors.primary : colors.onSurfaceVariant,
                size: 23,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: selected ? colors.primary : colors.onSurfaceVariant,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CatalogProductCard extends StatelessWidget {
  final Product product;
  final int threshold;
  final int soldCount;

  const _CatalogProductCard({
    required this.product,
    required this.threshold,
    required this.soldCount,
  });

  @override
  Widget build(BuildContext context) {
    final available = product.stock > 0;
    final colors = Theme.of(context).colorScheme;
    final stockColor = !available
        ? colors.error
        : product.stock < threshold
        ? colors.tertiary
        : colors.primary;

    return BlocBuilder<BillingBloc, BillingState>(
      builder: (context, state) {
        final matchingItems = state.cartItems.where(
          (item) => item.product.id == product.id,
        );
        final quantity = matchingItems.isEmpty
            ? 0
            : matchingItems.first.quantity;
        return Card(
          clipBehavior: Clip.antiAlias,
          elevation: 0,
          color: colors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: colors.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerHighest.withValues(
                        alpha: 0.55,
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: product.imageData == null
                              ? Icon(
                                  Icons.inventory_2_outlined,
                                  size: 52,
                                  color: colors.onSurfaceVariant.withValues(
                                    alpha: 0.55,
                                  ),
                                )
                              : Image.memory(
                                  base64Decode(product.imageData!),
                                  fit: BoxFit.contain,
                                  errorBuilder: (_, _, _) => Icon(
                                    Icons.broken_image_outlined,
                                    size: 44,
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                        ),
                        if (!available)
                          Positioned(
                            top: 10,
                            left: 10,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 9,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: colors.error,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                'Agotado',
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(
                                      color: colors.onError,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  product.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  AppCurrency.format(product.price, code: product.currencyCode),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: colors.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(
                      Icons.star_outline_rounded,
                      size: 17,
                      color: Color(0xFFF4B400),
                    ),
                    const SizedBox(width: 3),
                    Expanded(
                      child: Text(
                        soldCount == 0
                            ? 'Sin valoración · Sin ventas'
                            : 'Sin valoración · $soldCount vendidos',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: colors.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      available ? '${product.stock} disponibles' : '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: stockColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (quantity > 0)
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'En venta: $quantity',
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      IconButton.filledTonal(
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Quitar una unidad',
                        onPressed: () => context.read<BillingBloc>().add(
                          UpdateQuantityEvent(product.id, quantity - 1),
                        ),
                        icon: const Icon(Icons.remove, size: 18),
                      ),
                      const SizedBox(width: 6),
                      IconButton.filledTonal(
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Agregar una unidad',
                        onPressed: available
                            ? () => context.read<BillingBloc>().add(
                                AddProductToCartEvent(product),
                              )
                            : null,
                        icon: const Icon(Icons.add, size: 18),
                      ),
                    ],
                  )
                else
                  SizedBox(
                    width: double.infinity,
                    height: 38,
                    child: FilledButton(
                      onPressed: available
                          ? () => context.read<BillingBloc>().add(
                              AddProductToCartEvent(product),
                            )
                          : null,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        visualDensity: VisualDensity.compact,
                      ),
                      child: const Text('Agregar al carrito'),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
