import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/data/hive_database.dart';
import '../../../../core/utils/app_currency.dart';
import '../../../../core/utils/product_categories.dart';
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

  Future<void> _showFilters({
    required int availableCount,
    required int lowStockCount,
    required int outOfStockCount,
    required int totalCount,
  }) async {
    final colors = Theme.of(context).colorScheme;
    var draftFilter = _filter;
    final selectedFilter = await showModalBottomSheet<_CatalogFilter>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: colors.surface,
      barrierColor: Colors.black54,
      elevation: 24,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        final options = [
          (_CatalogFilter.all, 'Todos los productos', totalCount),
          (_CatalogFilter.available, 'Disponibles', availableCount),
          (_CatalogFilter.lowStock, 'Stock bajo', lowStockCount),
          (_CatalogFilter.outOfStock, 'Agotados', outOfStockCount),
        ];
        return SafeArea(
          child: StatefulBuilder(
            builder: (context, setSheetState) => Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Filtrar productos',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Elige qué productos quieres ver en el catálogo.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  for (final (filter, label, count) in options)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Material(
                        color: draftFilter == filter
                            ? colors.primaryContainer
                            : colors.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(14),
                        child: ListTile(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          title: Text(
                            label,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('$count'),
                              const SizedBox(width: 12),
                              Icon(
                                draftFilter == filter
                                    ? Icons.radio_button_checked_rounded
                                    : Icons.radio_button_off_rounded,
                                color: draftFilter == filter
                                    ? colors.primary
                                    : colors.onSurfaceVariant,
                              ),
                            ],
                          ),
                          onTap: () =>
                              setSheetState(() => draftFilter = filter),
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => setSheetState(
                          () => draftFilter = _CatalogFilter.all,
                        ),
                        child: const Text('Restablecer'),
                      ),
                      const Spacer(),
                      OutlinedButton(
                        onPressed: () => Navigator.pop(sheetContext),
                        child: const Text('Cancelar'),
                      ),
                      const SizedBox(width: 10),
                      FilledButton(
                        onPressed: () =>
                            Navigator.pop(sheetContext, draftFilter),
                        child: const Text('Aplicar'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    if (selectedFilter != null && mounted) {
      setState(() => _filter = selectedFilter);
    }
  }

  Future<void> _scanProduct() async {
    final barcode = await context.push<String>('/scan-code');
    if (!mounted || barcode == null || barcode.isEmpty) return;
    final matches = context.read<ProductBloc>().state.products.where(
      (product) => product.barcode == barcode,
    );
    if (matches.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se encontró un producto con el código $barcode.'),
        ),
      );
      return;
    }

    final product = matches.first;
    final billingBloc = context.read<BillingBloc>();
    final currentItems = billingBloc.state.cartItems;
    if (product.stock <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No hay existencias disponibles de "${product.name}".'),
        ),
      );
      return;
    }
    if (currentItems.isNotEmpty &&
        currentItems.first.product.currencyCode != product.currencyCode) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No se pueden mezclar monedas distintas en una misma venta.',
          ),
        ),
      );
      return;
    }
    final currentQuantity = currentItems
        .where((item) => item.product.id == product.id)
        .fold<int>(0, (total, item) => total + item.quantity);
    if (currentQuantity >= product.stock) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay más existencias disponibles.')),
      );
      return;
    }
    billingBloc.add(AddProductToCartEvent(product));
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

          final categories = ProductCategories.load();
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
                          hintText: '¿Qué estás buscando?',
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
                    IconButton.filledTonal(
                      tooltip: 'Escanear producto',
                      onPressed: _scanProduct,
                      icon: const Icon(Icons.qr_code_scanner_rounded),
                    ),
                    const SizedBox(width: 4),
                    OutlinedButton.icon(
                      onPressed: () => _showFilters(
                        availableCount: availableCount,
                        lowStockCount: lowStockCount,
                        outOfStockCount:
                            productState.products.length - availableCount,
                        totalCount: productState.products.length,
                      ),
                      icon: const Icon(Icons.tune_rounded, size: 19),
                      label: Text(
                        _filter == _CatalogFilter.all
                            ? 'Filtros'
                            : 'Filtro (1)',
                      ),
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
                      label: 'Populares',
                      selected: _sort == _CatalogSort.popular,
                      onTap: () => setState(() => _sort = _CatalogSort.popular),
                    ),
                    _SortTab(
                      label: 'Recientes',
                      selected: _sort == _CatalogSort.latest,
                      onTap: () => setState(() => _sort = _CatalogSort.latest),
                    ),
                    _SortTab(
                      label: 'Más vendidos',
                      selected: _sort == _CatalogSort.bestSellers,
                      onTap: () =>
                          setState(() => _sort = _CatalogSort.bestSellers),
                    ),
                    _SortTab(
                      label: _priceAscending ? 'Precio ↑' : 'Precio ↓',
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
                  children: [
                    _CategoryButton(
                      label: 'Todas',
                      icon: Icons.grid_view_rounded,
                      selected: _category == 'Todas',
                      onTap: () => setState(() => _category = 'Todas'),
                    ),
                    ...categories.map(
                      (category) => _CategoryButton(
                        label: category.name,
                        icon: category.icon,
                        selected: _category == category.name,
                        onTap: () => setState(() => _category = category.name),
                      ),
                    ),
                  ],
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
                      'Toca la imagen para ver detalles',
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
                                      mainAxisExtent: 300,
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
              child: Material(
                color: Theme.of(context).colorScheme.surface,
                elevation: 12,
                borderRadius: BorderRadius.circular(18),
                child: FilledButton(
                  onPressed: () => context.push('/checkout'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 13,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.shopping_bag_outlined),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Revisar carrito · $quantity ${quantity == 1 ? 'producto' : 'productos'}',
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
                  child: Material(
                    color: colors.surfaceContainerHighest.withValues(
                      alpha: 0.55,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => _showProductDetails(context),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (product.imageData == null)
                            Icon(
                              Icons.inventory_2_outlined,
                              size: 52,
                              color: colors.onSurfaceVariant.withValues(
                                alpha: 0.55,
                              ),
                            )
                          else
                            Image.memory(
                              base64Decode(product.imageData!),
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => Icon(
                                Icons.broken_image_outlined,
                                size: 44,
                                color: colors.onSurfaceVariant,
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
                          Positioned(
                            right: 9,
                            bottom: 9,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: colors.surface.withValues(alpha: 0.92),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 9,
                                  vertical: 6,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.info_outline_rounded,
                                      size: 14,
                                      color: colors.primary,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Detalles',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                            color: colors.primary,
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
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
                        onPressed: available && quantity < product.stock
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

  Future<void> _showProductDetails(BuildContext context) async {
    final colors = Theme.of(context).colorScheme;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520, maxHeight: 680),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 230,
                child: product.imageData == null
                    ? ColoredBox(
                        color: colors.surfaceContainerHighest,
                        child: Icon(
                          Icons.inventory_2_outlined,
                          size: 64,
                          color: colors.onSurfaceVariant,
                        ),
                      )
                    : Image.memory(
                        base64Decode(product.imageData!),
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => ColoredBox(
                          color: colors.surfaceContainerHighest,
                          child: Icon(
                            Icons.broken_image_outlined,
                            size: 52,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(22, 18, 22, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (product.category.isNotEmpty)
                        Text(
                          product.category.toUpperCase(),
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(
                                color: colors.primary,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1,
                              ),
                        ),
                      const SizedBox(height: 5),
                      Text(
                        product.name,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        product.description.trim().isEmpty
                            ? 'No hay una descripción disponible para este producto.'
                            : product.description.trim(),
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          height: 1.5,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              AppCurrency.format(
                                product.price,
                                code: product.currencyCode,
                              ),
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(
                                    fontWeight: FontWeight.w900,
                                    color: colors.primary,
                                  ),
                            ),
                          ),
                          Text(
                            product.stock > 0
                                ? '${product.stock} disponibles'
                                : 'Agotado',
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(
                                  color: product.stock > 0
                                      ? colors.primary
                                      : colors.error,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ],
                      ),
                      if (product.barcode.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Código: ${product.barcode}',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colors.onSurfaceVariant),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        child: const Text('Cerrar'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: FilledButton.icon(
                        onPressed: product.stock <= 0
                            ? null
                            : () {
                                context.read<BillingBloc>().add(
                                  AddProductToCartEvent(product),
                                );
                                Navigator.pop(dialogContext);
                              },
                        icon: const Icon(Icons.add_shopping_cart_rounded),
                        label: const Text('Agregar al carrito'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
