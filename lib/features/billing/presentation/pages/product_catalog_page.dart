import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/data/hive_database.dart';
import '../../../../core/utils/app_currency.dart';
import '../../../billing/presentation/bloc/billing_bloc.dart';
import '../../../product/domain/entities/product.dart';
import '../../../product/presentation/bloc/product_bloc.dart';

enum _CatalogFilter { all, available, lowStock, outOfStock }

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

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    AppCurrencyScope.of(context);
    final threshold =
        HiveDatabase.settingsBox.get('low_stock_threshold', defaultValue: 5)
            as int;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Catálogo de productos'),
        actions: [
          BlocBuilder<BillingBloc, BillingState>(
            builder: (context, state) {
              final itemCount = state.cartItems.fold<int>(
                0,
                (total, item) => total + item.quantity,
              );
              return Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Text(
                      '$itemCount en carrito',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
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
              }).toList()..sort(
                (first, second) => first.name.toLowerCase().compareTo(
                  second.name.toLowerCase(),
                ),
              );

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
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: TextField(
                  controller: _searchController,
                  onChanged: (value) => setState(() => _query = value),
                  decoration: InputDecoration(
                    hintText: 'Buscar producto, categoría o código',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Limpiar búsqueda',
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _query = '');
                            },
                            icon: const Icon(Icons.close),
                          ),
                    filled: true,
                    fillColor: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest
                        .withValues(alpha: 0.45),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              SizedBox(
                height: 48,
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  scrollDirection: Axis.horizontal,
                  children: [
                    _FilterChip(
                      label: 'Todos ${productState.products.length}',
                      selected: _filter == _CatalogFilter.all,
                      onSelected: () =>
                          setState(() => _filter = _CatalogFilter.all),
                    ),
                    _FilterChip(
                      label: 'Disponibles $availableCount',
                      selected: _filter == _CatalogFilter.available,
                      onSelected: () =>
                          setState(() => _filter = _CatalogFilter.available),
                    ),
                    _FilterChip(
                      label: 'Stock bajo $lowStockCount',
                      selected: _filter == _CatalogFilter.lowStock,
                      onSelected: () =>
                          setState(() => _filter = _CatalogFilter.lowStock),
                    ),
                    _FilterChip(
                      label:
                          'Agotados ${productState.products.length - availableCount}',
                      selected: _filter == _CatalogFilter.outOfStock,
                      onSelected: () =>
                          setState(() => _filter = _CatalogFilter.outOfStock),
                    ),
                  ],
                ),
              ),
              if (categories.isNotEmpty)
                SizedBox(
                  height: 46,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                    scrollDirection: Axis.horizontal,
                    children: ['Todas', ...categories].map((category) {
                      final selected = _category == category;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(category),
                          selected: selected,
                          onSelected: (_) =>
                              setState(() => _category = category),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
                child: Row(
                  children: [
                    Text(
                      '${visibleProducts.length} productos',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const Spacer(),
                    const Icon(Icons.touch_app_outlined, size: 16),
                    const SizedBox(width: 5),
                    Text(
                      'Toca Agregar para vender',
                      style: Theme.of(context).textTheme.labelSmall,
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
                          final columns = constraints.maxWidth >= 1000
                              ? 4
                              : constraints.maxWidth >= 680
                              ? 3
                              : constraints.maxWidth >= 420
                              ? 2
                              : 1;
                          return GridView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: columns,
                                  crossAxisSpacing: 12,
                                  mainAxisSpacing: 12,
                                  mainAxisExtent: 198,
                                ),
                            itemCount: visibleProducts.length,
                            itemBuilder: (context, index) =>
                                _CatalogProductCard(
                                  product: visibleProducts[index],
                                  threshold: threshold,
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

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onSelected;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(),
    ),
  );
}

class _CatalogProductCard extends StatelessWidget {
  final Product product;
  final int threshold;

  const _CatalogProductCard({required this.product, required this.threshold});

  @override
  Widget build(BuildContext context) {
    final available = product.stock > 0;
    final stockColor = !available
        ? Theme.of(context).colorScheme.error
        : product.stock < threshold
        ? const Color(0xFFE59B36)
        : const Color(0xFF1E9B72);

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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(
              color: Theme.of(context).dividerColor.withValues(alpha: 0.65),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SizedBox(
                        width: 52,
                        height: 52,
                        child: product.imageData == null
                            ? ColoredBox(
                                color: Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerHighest,
                                child: Icon(
                                  Icons.inventory_2_outlined,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              )
                            : Image.memory(
                                base64Decode(product.imageData!),
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) =>
                                    const Icon(Icons.broken_image_outlined),
                              ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        product.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.circle, size: 8, color: stockColor),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        available ? '${product.stock} disponibles' : 'Agotado',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: stockColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (product.category.isNotEmpty)
                      Flexible(
                        child: Text(
                          product.category,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ),
                  ],
                ),
                const Spacer(),
                if (quantity > 0)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        AppCurrency.format(
                          product.price,
                          code: product.currencyCode,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          IconButton.filledTonal(
                            visualDensity: VisualDensity.compact,
                            tooltip: 'Quitar una unidad',
                            onPressed: () => context.read<BillingBloc>().add(
                              UpdateQuantityEvent(product.id, quantity - 1),
                            ),
                            icon: const Icon(Icons.remove, size: 18),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Text(
                              '$quantity',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
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
                      ),
                    ],
                  )
                else
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          AppCurrency.format(
                            product.price,
                            code: product.currencyCode,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: available
                            ? () => context.read<BillingBloc>().add(
                                AddProductToCartEvent(product),
                              )
                            : null,
                        icon: const Icon(Icons.add_shopping_cart, size: 18),
                        label: const Text('Agregar'),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
