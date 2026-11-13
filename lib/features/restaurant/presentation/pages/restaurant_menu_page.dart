import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/utils/app_currency.dart';
import '../../../../core/data/models/app_settings.dart';
import '../../data/restaurant_menu_repository.dart';
import '../../domain/entities/restaurant_menu.dart';

class RestaurantMenuPage extends StatefulWidget {
  const RestaurantMenuPage({super.key});

  @override
  State<RestaurantMenuPage> createState() => _RestaurantMenuPageState();
}

class _RestaurantMenuPageState extends State<RestaurantMenuPage> {
  final _repository = RestaurantMenuRepository();
  final _searchController = TextEditingController();
  RestaurantMenuState _menu = const RestaurantMenuState();
  String? _selectedCategoryId;
  String _query = '';
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final menu = _repository.load();
      if (!mounted) return;
      setState(() {
        _menu = menu;
        _error = null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudo cargar el menú: $error';
        _loading = false;
      });
    }
  }

  Future<bool> _save(RestaurantMenuState next) async {
    try {
      await _repository.save(next);
      if (!mounted) return false;
      setState(() {
        _menu = next;
        _error = null;
      });
      return true;
    } catch (error) {
      _message('No se pudo guardar el menú: $error');
      return false;
    }
  }

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _editCategory([RestaurantMenuCategory? category]) async {
    final result = await showDialog<RestaurantMenuCategory>(
      context: context,
      builder: (context) => _CategoryEditorDialog(category: category),
    );
    if (result == null || !mounted) return;
    final categories = [
      for (final item in _menu.categories)
        if (item.id == result.id) result else item,
      if (category == null) result,
    ];
    await _save(
      RestaurantMenuState(categories: categories, products: _menu.products),
    );
  }

  Future<void> _deleteCategory(RestaurantMenuCategory category) async {
    if (_menu.products.any((product) => product.categoryId == category.id)) {
      _message('Mueve o elimina sus productos antes de borrar esta categoría.');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar categoría'),
        content: Text('¿Deseas eliminar "${category.name}" del menú?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final categories = _menu.categories
        .where((item) => item.id != category.id)
        .toList();
    await _save(
      RestaurantMenuState(categories: categories, products: _menu.products),
    );
    if (_selectedCategoryId == category.id) {
      setState(() => _selectedCategoryId = null);
    }
  }

  Future<void> _editProduct([RestaurantMenuProduct? product]) async {
    if (_menu.categories.isEmpty) {
      _message('Crea primero una categoría para organizar tus productos.');
      return;
    }
    final result = await showDialog<RestaurantMenuProduct>(
      context: context,
      builder: (context) => _MenuProductEditorDialog(
        categories: _menu.categories,
        product: product,
      ),
    );
    if (result == null || !mounted) return;
    final products = [
      for (final item in _menu.products)
        if (item.id == result.id) result else item,
      if (product == null) result,
    ];
    await _save(
      RestaurantMenuState(categories: _menu.categories, products: products),
    );
  }

  Future<void> _deleteProduct(RestaurantMenuProduct product) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar producto'),
        content: Text(
          'Se eliminará "${product.name}" del menú del restaurante.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Conservar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final products = _menu.products
        .where((item) => item.id != product.id)
        .toList();
    await _save(
      RestaurantMenuState(categories: _menu.categories, products: products),
    );
  }

  Future<void> _toggleAvailability(RestaurantMenuProduct product) async {
    final updated = product.copyWith(isAvailable: !product.isAvailable);
    final products = [
      for (final item in _menu.products)
        if (item.id == product.id) updated else item,
    ];
    await _save(
      RestaurantMenuState(categories: _menu.categories, products: products),
    );
  }

  String _categoryName(String id) {
    for (final category in _menu.categories) {
      if (category.id == id) return category.name;
    }
    return 'Sin categoría';
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final visibleProducts =
        _menu.products.where((product) {
          final matchesCategory =
              _selectedCategoryId == null ||
              product.categoryId == _selectedCategoryId;
          final category = _categoryName(product.categoryId);
          final matchesQuery =
              _query.isEmpty ||
              product.name.toLowerCase().contains(_query.toLowerCase()) ||
              product.description.toLowerCase().contains(
                _query.toLowerCase(),
              ) ||
              category.toLowerCase().contains(_query.toLowerCase());
          return matchesCategory && matchesQuery;
        }).toList()..sort(
          (first, second) =>
              first.name.toLowerCase().compareTo(second.name.toLowerCase()),
        );
    final availableCount = _menu.products
        .where((product) => product.isAvailable)
        .length;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: const Text('Menú del restaurante'),
        actions: [
          IconButton(
            tooltip: 'Actualizar menú',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loading ? null : () => _editProduct(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Nuevo producto'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline_rounded, size: 40),
                    const SizedBox(height: 12),
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _load,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Reintentar'),
                    ),
                  ],
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
                children: [
                  _MenuHero(
                    productCount: _menu.products.length,
                    categoryCount: _menu.categories.length,
                    availableCount: availableCount,
                    onCreateProduct: () => _editProduct(),
                    onCreateCategory: () => _editCategory(),
                  ),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Categorías',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _editCategory(),
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('Nueva categoría'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 9,
                    runSpacing: 9,
                    children: [
                      _CategoryFilterChip(
                        label: 'Todo el menú',
                        count: _menu.products.length,
                        selected: _selectedCategoryId == null,
                        onTap: () => setState(() => _selectedCategoryId = null),
                      ),
                      for (final category in _menu.categories)
                        _CategoryFilterChip(
                          label: category.name,
                          count: _menu.products
                              .where((item) => item.categoryId == category.id)
                              .length,
                          selected: _selectedCategoryId == category.id,
                          onTap: () =>
                              setState(() => _selectedCategoryId = category.id),
                          onEdit: () => _editCategory(category),
                          onDelete: () => _deleteCategory(category),
                        ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Productos del menú',
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'Catálogo independiente del inventario general.',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: colors.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      if (MediaQuery.sizeOf(context).width > 540)
                        SizedBox(width: 250, child: _searchField()),
                    ],
                  ),
                  if (MediaQuery.sizeOf(context).width <= 540) ...[
                    const SizedBox(height: 14),
                    _searchField(),
                  ],
                  const SizedBox(height: 14),
                  if (visibleProducts.isEmpty)
                    _EmptyMenu(
                      hasProducts: _menu.products.isNotEmpty,
                      hasCategories: _menu.categories.isNotEmpty,
                      onCreateProduct: () => _editProduct(),
                      onCreateCategory: () => _editCategory(),
                    )
                  else
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final columns = constraints.maxWidth >= 1000
                            ? 3
                            : constraints.maxWidth >= 640
                            ? 2
                            : 1;
                        final cardWidth =
                            (constraints.maxWidth - 14 * (columns - 1)) /
                            columns;
                        return Wrap(
                          spacing: 14,
                          runSpacing: 14,
                          children: [
                            for (final product in visibleProducts)
                              SizedBox(
                                width: cardWidth,
                                child: _MenuProductCard(
                                  product: product,
                                  category: _categoryName(product.categoryId),
                                  onEdit: () => _editProduct(product),
                                  onDelete: () => _deleteProduct(product),
                                  onToggle: () => _toggleAvailability(product),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                ],
              ),
            ),
    );
  }

  Widget _searchField() => TextField(
    controller: _searchController,
    onChanged: (value) => setState(() => _query = value.trim()),
    decoration: InputDecoration(
      hintText: 'Buscar producto o categoría',
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
      fillColor: Theme.of(context).colorScheme.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
    ),
  );
}

class _MenuHero extends StatelessWidget {
  final int productCount;
  final int categoryCount;
  final int availableCount;
  final VoidCallback onCreateProduct;
  final VoidCallback onCreateCategory;

  const _MenuHero({
    required this.productCount,
    required this.categoryCount,
    required this.availableCount,
    required this.onCreateProduct,
    required this.onCreateCategory,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colors.primary, colors.primary.withValues(alpha: .78)],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: colors.primary.withValues(alpha: .17),
            blurRadius: 22,
            offset: const Offset(0, 9),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 680;
          final introduction = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'CARTA Y OFERTA GASTRONÓMICA',
                style: TextStyle(
                  color: colors.onPrimary.withValues(alpha: .72),
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.3,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Diseña tu menú',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: colors.onPrimary,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                'Organiza categorías, define precios y controla qué platos están disponibles.',
                style: TextStyle(
                  color: colors.onPrimary.withValues(alpha: .82),
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton.icon(
                    onPressed: onCreateProduct,
                    style: FilledButton.styleFrom(
                      backgroundColor: colors.onPrimary,
                      foregroundColor: colors.primary,
                    ),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Crear producto'),
                  ),
                  OutlinedButton.icon(
                    onPressed: onCreateCategory,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: colors.onPrimary,
                      side: BorderSide(
                        color: colors.onPrimary.withValues(alpha: .5),
                      ),
                    ),
                    icon: const Icon(Icons.category_outlined),
                    label: const Text('Nueva categoría'),
                  ),
                ],
              ),
            ],
          );
          final summary = Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _MenuStat(label: 'PRODUCTOS', value: '$productCount'),
              _MenuStat(label: 'CATEGORÍAS', value: '$categoryCount'),
              _MenuStat(label: 'DISPONIBLES', value: '$availableCount'),
            ],
          );
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [introduction, const SizedBox(height: 20), summary],
            );
          }
          return Row(
            children: [
              Expanded(flex: 6, child: introduction),
              const SizedBox(width: 22),
              Expanded(flex: 5, child: summary),
            ],
          );
        },
      ),
    );
  }
}

class _MenuStat extends StatelessWidget {
  final String label;
  final String value;

  const _MenuStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final onPrimary = Theme.of(context).colorScheme.onPrimary;
    return Container(
      width: 122,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: onPrimary.withValues(alpha: .13),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: onPrimary.withValues(alpha: .14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: onPrimary.withValues(alpha: .72),
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: .5,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            value,
            style: TextStyle(
              color: onPrimary,
              fontSize: 21,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryFilterChip extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const _CategoryFilterChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
    this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: selected ? colors.primaryContainer : colors.surface,
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: Container(
          padding: const EdgeInsets.only(left: 14, top: 5, bottom: 5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: selected
                  ? colors.primary.withValues(alpha: .24)
                  : colors.outlineVariant,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: selected ? colors.primary : colors.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: selected
                      ? colors.primary.withValues(alpha: .1)
                      : colors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    color: selected ? colors.primary : colors.onSurfaceVariant,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (onEdit != null)
                PopupMenuButton<String>(
                  tooltip: 'Opciones de categoría',
                  padding: EdgeInsets.zero,
                  onSelected: (value) {
                    if (value == 'edit') onEdit?.call();
                    if (value == 'delete') onDelete?.call();
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: 'edit',
                      child: ListTile(
                        leading: Icon(Icons.edit_outlined),
                        title: Text('Editar'),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: ListTile(
                        leading: Icon(Icons.delete_outline_rounded),
                        title: Text('Eliminar'),
                      ),
                    ),
                  ],
                  icon: const Icon(Icons.more_vert_rounded, size: 19),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MenuProductCard extends StatelessWidget {
  final RestaurantMenuProduct product;
  final String category;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onToggle;

  const _MenuProductCard({
    required this.product,
    required this.category,
    required this.onEdit,
    required this.onDelete,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final availableColor = isDark
        ? const Color(0xFF78D6A1)
        : const Color(0xFF18794E);
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: colors.outlineVariant.withValues(alpha: .7)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: colors.primaryContainer,
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Icon(
                    Icons.restaurant_rounded,
                    color: colors.primary,
                    size: 23,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        category.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.primary,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: .8,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: product.isAvailable
                              ? Color.alphaBlend(
                                  availableColor.withValues(alpha: .14),
                                  colors.surface,
                                )
                              : colors.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          product.isAvailable ? 'Disponible' : 'Pausado',
                          style: TextStyle(
                            color: product.isAvailable
                                ? availableColor
                                : colors.onSurfaceVariant,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Opciones del producto',
                  onSelected: (value) {
                    if (value == 'edit') onEdit();
                    if (value == 'delete') onDelete();
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: 'edit',
                      child: ListTile(
                        leading: Icon(Icons.edit_outlined),
                        title: Text('Editar'),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: ListTile(
                        leading: Icon(Icons.delete_outline_rounded),
                        title: Text('Eliminar'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 15),
            Text(
              product.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 5),
            SizedBox(
              height: 38,
              child: Align(
                alignment: Alignment.topLeft,
                child: Text(
                  product.description.isEmpty
                      ? 'Producto preparado para pedidos en mesa.'
                      : product.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Divider(height: 1, color: colors.outlineVariant),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    AppCurrency.format(
                      product.price,
                      code: product.currencyCode,
                    ),
                    style: TextStyle(
                      color: colors.primary,
                      fontSize: 19,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Text(
                  'En menú',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                Switch.adaptive(
                  value: product.isAvailable,
                  onChanged: (_) => onToggle(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyMenu extends StatelessWidget {
  final bool hasProducts;
  final bool hasCategories;
  final VoidCallback onCreateProduct;
  final VoidCallback onCreateCategory;

  const _EmptyMenu({
    required this.hasProducts,
    required this.hasCategories,
    required this.onCreateProduct,
    required this.onCreateCategory,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final title = !hasCategories
        ? 'Organiza tu menú por categorías'
        : hasProducts
        ? 'No encontramos productos'
        : 'Tu menú empieza aquí';
    final description = !hasCategories
        ? 'Crea categorías como Entradas, Platos principales y Bebidas.'
        : hasProducts
        ? 'Prueba otra búsqueda o selecciona una categoría distinta.'
        : 'Añade tus platos y bebidas con su descripción y precio.';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 38),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: colors.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              !hasCategories
                  ? Icons.category_outlined
                  : Icons.restaurant_menu_rounded,
              color: colors.primary,
              size: 30,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            description,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
          ),
          if (!hasProducts) ...[
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: hasCategories ? onCreateProduct : onCreateCategory,
              icon: Icon(
                hasCategories ? Icons.add_rounded : Icons.category_outlined,
              ),
              label: Text(
                hasCategories ? 'Crear primer producto' : 'Crear categoría',
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CategoryEditorDialog extends StatefulWidget {
  final RestaurantMenuCategory? category;

  const _CategoryEditorDialog({this.category});

  @override
  State<_CategoryEditorDialog> createState() => _CategoryEditorDialogState();
}

class _CategoryEditorDialogState extends State<_CategoryEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.category?.name ?? '');
    _descriptionController = TextEditingController(
      text: widget.category?.description ?? '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.category == null ? 'Nueva categoría' : 'Editar categoría',
    ),
    content: SizedBox(
      width: 430,
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _nameController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Nombre de la categoría',
                hintText: 'Ej. Platos principales',
                prefixIcon: Icon(Icons.category_outlined),
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Escribe un nombre'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _descriptionController,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Descripción (opcional)',
                alignLabelWithHint: true,
              ),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: () {
          if (!_formKey.currentState!.validate()) return;
          Navigator.pop(
            context,
            RestaurantMenuCategory(
              id: widget.category?.id ?? const Uuid().v4(),
              name: _nameController.text.trim(),
              description: _descriptionController.text.trim(),
            ),
          );
        },
        child: const Text('Guardar categoría'),
      ),
    ],
  );
}

class _MenuProductEditorDialog extends StatefulWidget {
  final List<RestaurantMenuCategory> categories;
  final RestaurantMenuProduct? product;

  const _MenuProductEditorDialog({required this.categories, this.product});

  @override
  State<_MenuProductEditorDialog> createState() =>
      _MenuProductEditorDialogState();
}

class _MenuProductEditorDialogState extends State<_MenuProductEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _priceController;
  late String _categoryId;
  late String _currencyCode;
  late final List<CurrencyConfig> _currencies;

  @override
  void initState() {
    super.initState();
    _currencies = AppCurrency.configuredCurrencies;
    _nameController = TextEditingController(text: widget.product?.name ?? '');
    _descriptionController = TextEditingController(
      text: widget.product?.description ?? '',
    );
    _priceController = TextEditingController(
      text: widget.product?.price.toString() ?? '',
    );
    _categoryId = widget.product?.categoryId ?? widget.categories.first.id;
    _currencyCode =
        widget.product?.currencyCode ??
        (AppCurrency.configuredCurrencies.any(
              (currency) => currency.code == AppCurrency.baseCode,
            )
            ? AppCurrency.baseCode
            : AppCurrency.configuredCurrencies.first.code);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currencies = _currencies;
    return AlertDialog(
      title: Text(
        widget.product == null ? 'Nuevo producto del menú' : 'Editar producto',
      ),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _nameController,
                  autofocus: true,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Nombre del producto',
                    hintText: 'Ej. Hamburguesa de la casa',
                    prefixIcon: Icon(Icons.restaurant_outlined),
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Escribe el nombre del producto'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _descriptionController,
                  maxLines: 2,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Descripción (opcional)',
                    hintText: 'Ingredientes o detalles del plato',
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _categoryId,
                  decoration: const InputDecoration(
                    labelText: 'Categoría',
                    prefixIcon: Icon(Icons.category_outlined),
                  ),
                  items: [
                    for (final category in widget.categories)
                      DropdownMenuItem(
                        value: category.id,
                        child: Text(category.name),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _categoryId = value);
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
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
                          final parsed = double.tryParse(
                            (value ?? '').trim().replaceAll(',', '.'),
                          );
                          if (parsed == null ||
                              !parsed.isFinite ||
                              parsed < 0) {
                            return 'Precio no válido';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _currencyCode,
                        decoration: const InputDecoration(labelText: 'Moneda'),
                        items: [
                          for (final currency in currencies)
                            DropdownMenuItem(
                              value: currency.code,
                              child: Text(currency.code),
                            ),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setState(() => _currencyCode = value);
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest
                        .withValues(alpha: .45),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline_rounded, size: 18),
                      SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          'Este menú es independiente: sus productos no descuentan existencias del inventario general.',
                          style: TextStyle(fontSize: 12, height: 1.35),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            final price = double.parse(
              _priceController.text.trim().replaceAll(',', '.'),
            );
            Navigator.pop(
              context,
              RestaurantMenuProduct(
                id: widget.product?.id ?? const Uuid().v4(),
                categoryId: _categoryId,
                name: _nameController.text.trim(),
                description: _descriptionController.text.trim(),
                price: price,
                currencyCode: _currencyCode,
                isAvailable: widget.product?.isAvailable ?? true,
              ),
            );
          },
          child: const Text('Guardar producto'),
        ),
      ],
    );
  }
}
