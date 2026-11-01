import 'package:flutter/material.dart';

import '../../../../core/data/hive_database.dart';
import '../../../../core/utils/product_categories.dart';

class CategoryManagementPage extends StatefulWidget {
  const CategoryManagementPage({super.key});

  @override
  State<CategoryManagementPage> createState() => _CategoryManagementPageState();
}

class _CategoryManagementPageState extends State<CategoryManagementPage> {
  late List<ProductCategory> _categories;

  @override
  void initState() {
    super.initState();
    _reloadCategories();
  }

  void _reloadCategories() {
    _categories = ProductCategories.load();
  }

  int _productCount(String category) => HiveDatabase.productBox.values
      .where(
        (product) =>
            product.category.trim().toLowerCase() == category.toLowerCase(),
      )
      .length;

  Future<int?> _chooseIcon(int selectedCodePoint) => showDialog<int>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Elige un icono'),
      content: SizedBox(
        width: 360,
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final icon in ProductCategories.availableIcons)
              IconButton(
                tooltip: 'Seleccionar icono',
                onPressed: () => Navigator.pop(context, icon.codePoint),
                style: IconButton.styleFrom(
                  backgroundColor: icon.codePoint == selectedCodePoint
                      ? Theme.of(context).colorScheme.primaryContainer
                      : Theme.of(context).colorScheme.surfaceContainerLow,
                ),
                icon: Icon(
                  icon,
                  color: icon.codePoint == selectedCodePoint
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
      ],
    ),
  );

  Future<void> _addCategory() async {
    final controller = TextEditingController();
    var selectedIconCodePoint = Icons.category_outlined.codePoint;
    final result = await showDialog<(String, int)>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nueva categoría'),
        content: StatefulBuilder(
          builder: (context, setDialogState) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Nombre',
                  hintText: 'Ej.: Bebidas',
                  prefixIcon: Icon(Icons.category_outlined),
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final iconCodePoint = await _chooseIcon(
                      selectedIconCodePoint,
                    );
                    if (iconCodePoint != null) {
                      setDialogState(
                        () => selectedIconCodePoint = iconCodePoint,
                      );
                    }
                  },
                  icon: Icon(ProductCategories.iconFor(selectedIconCodePoint)),
                  label: const Text('Elegir icono'),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, (
              controller.text.trim(),
              selectedIconCodePoint,
            )),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null || !mounted) return;
    final (name, iconCodePoint) = result;
    if (name.isEmpty) {
      _showMessage('Escribe un nombre para la categoría.');
      return;
    }

    try {
      final added = await ProductCategories.add(
        name,
        iconCodePoint: iconCodePoint,
      );
      if (!mounted) return;
      if (!added) {
        _showMessage('Ya existe una categoría con ese nombre.');
        return;
      }
      setState(_reloadCategories);
      _showMessage('Categoría creada correctamente.');
    } catch (error) {
      if (mounted) _showMessage('No se pudo guardar la categoría: $error');
    }
  }

  Future<void> _removeCategory(String category) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar categoría'),
        content: Text('¿Quieres eliminar “$category”?'),
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

    try {
      final removed = await ProductCategories.remove(category);
      if (!mounted) return;
      if (!removed) {
        _showMessage(
          'No se puede eliminar: hay productos que usan esta categoría.',
        );
        return;
      }
      setState(_reloadCategories);
      _showMessage('Categoría eliminada.');
    } catch (error) {
      if (mounted) _showMessage('No se pudo eliminar la categoría: $error');
    }
  }

  Future<void> _editCategoryIcon(ProductCategory category) async {
    final iconCodePoint = await _chooseIcon(category.iconCodePoint);
    if (iconCodePoint == null || !mounted) return;
    try {
      await ProductCategories.updateIcon(category.name, iconCodePoint);
      if (mounted) setState(_reloadCategories);
    } catch (error) {
      if (mounted) _showMessage('No se pudo actualizar el icono: $error');
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final assignedCount = _categories
        .where((category) => _productCount(category.name) > 0)
        .length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Categorías'),
        actions: [
          IconButton(
            tooltip: 'Crear categoría',
            onPressed: _addCategory,
            icon: const Icon(Icons.add_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addCategory,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Nueva categoría'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 96),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: colors.primaryContainer,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: colors.surface.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(Icons.category_rounded, color: colors.primary),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Organiza tu catálogo',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: Colors.black,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${_categories.length} categorías · $assignedCount en uso',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onPrimaryContainer,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Tus categorías',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          if (_categories.isEmpty)
            Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: colors.outlineVariant),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.create_new_folder_outlined,
                    size: 42,
                    color: colors.onSurfaceVariant,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Aún no tienes categorías',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'Crea categorías para seleccionarlas al registrar productos.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: colors.onSurfaceVariant),
                  ),
                ],
              ),
            )
          else
            ..._categories.map((category) {
              final productCount = _productCount(category.name);
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                elevation: 0,
                color: colors.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                  side: BorderSide(color: colors.outlineVariant),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.fromLTRB(14, 6, 8, 6),
                  leading: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: colors.primaryContainer,
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(category.icon, size: 20, color: colors.primary),
                  ),
                  title: Text(
                    category.name,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    '$productCount ${productCount == 1 ? 'producto' : 'productos'}',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Cambiar icono',
                        onPressed: () => _editCategoryIcon(category),
                        icon: Icon(Icons.edit_outlined, color: colors.primary),
                      ),
                      IconButton(
                        tooltip: 'Eliminar categoría',
                        onPressed: () => _removeCategory(category.name),
                        icon: Icon(
                          Icons.delete_outline_rounded,
                          color: productCount > 0
                              ? colors.onSurfaceVariant
                              : colors.error,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}
