import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/data/hive_database.dart';
import '../../../../core/utils/product_categories.dart';
import '../../../product/presentation/bloc/product_bloc.dart';

class CategoryManagementPage extends StatefulWidget {
  const CategoryManagementPage({super.key});

  @override
  State<CategoryManagementPage> createState() => _CategoryManagementPageState();
}

class _CategoryManagementPageState extends State<CategoryManagementPage> {
  late List<ProductCategory> _categories;
  String _query = '';

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

  Future<int?> _chooseIcon(int selectedCodePoint) {
    final colors = Theme.of(context).colorScheme;
    return showDialog<int>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: colors.primaryContainer,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        Icons.grid_view_rounded,
                        color: colors.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Icono de categoría',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Elige un símbolo para identificarla.',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: colors.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Cerrar',
                      onPressed: () => Navigator.pop(dialogContext),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                GridView.count(
                  crossAxisCount: 5,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 9,
                  crossAxisSpacing: 9,
                  children: [
                    for (final icon in ProductCategories.availableIcons)
                      Tooltip(
                        message: 'Seleccionar icono',
                        child: Material(
                          color: icon.codePoint == selectedCodePoint
                              ? colors.primary
                              : colors.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(13),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(13),
                            onTap: () =>
                                Navigator.pop(dialogContext, icon.codePoint),
                            child: Icon(
                              icon,
                              color: icon.codePoint == selectedCodePoint
                                  ? colors.onPrimary
                                  : colors.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('Cancelar'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _addCategory() async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final colors = Theme.of(context).colorScheme;
    var selectedIconCodePoint = Icons.category_outlined.codePoint;
    final result = await showDialog<(String, int)>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: StatefulBuilder(
            builder: (context, setDialogState) => Padding(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 54,
                          height: 54,
                          decoration: BoxDecoration(
                            color: colors.primary,
                            borderRadius: BorderRadius.circular(17),
                          ),
                          child: Icon(
                            ProductCategories.iconFor(selectedIconCodePoint),
                            color: colors.onPrimary,
                            size: 25,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Crear categoría',
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                              SizedBox(height: 3),
                              Text(
                                'Organiza tus productos con una nueva categoría.',
                                style: TextStyle(
                                  color: Color(0xFF737985),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Cerrar',
                          onPressed: () => Navigator.pop(dialogContext),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Nombre de la categoría',
                      style: TextStyle(
                        color: Color(0xFF282C32),
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: controller,
                      autofocus: true,
                      textCapitalization: TextCapitalization.words,
                      maxLength: 40,
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? 'Escribe un nombre para continuar.'
                          : null,
                      decoration: InputDecoration(
                        hintText: 'Ej.: Bebidas y alimentos',
                        counterText: '',
                        prefixIcon: const Icon(Icons.edit_outlined),
                        filled: true,
                        fillColor: colors.surfaceContainerHighest,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(
                            color: Color(0xFFE6E8EB),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(
                            color: colors.primary,
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Icono identificador',
                                style: TextStyle(
                                  color: Color(0xFF282C32),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                              SizedBox(height: 3),
                              Text(
                                'Personaliza cómo aparece en el catálogo.',
                                style: TextStyle(
                                  color: Color(0xFF737985),
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        OutlinedButton.icon(
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
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF111111),
                            side: const BorderSide(color: Color(0xFFD9DDE2)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          icon: const Icon(Icons.grid_view_rounded, size: 17),
                          label: const Text('Elegir'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(dialogContext),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(48),
                              foregroundColor: const Color(0xFF333840),
                              side: const BorderSide(color: Color(0xFFD9DDE2)),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(13),
                              ),
                            ),
                            child: const Text('Cancelar'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () {
                              if (formKey.currentState!.validate()) {
                                Navigator.pop(dialogContext, (
                                  controller.text.trim(),
                                  selectedIconCodePoint,
                                ));
                              }
                            },
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(48),
                              backgroundColor: colors.primary,
                              foregroundColor: colors.onPrimary,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(13),
                              ),
                            ),
                            icon: const Icon(Icons.add_rounded, size: 18),
                            label: const Text('Crear categoría'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
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

  Future<void> _editCategory(ProductCategory category) async {
    final controller = TextEditingController(text: category.name);
    final formKey = GlobalKey<FormState>();
    var selectedIconCodePoint = category.iconCodePoint;
    final result = await showDialog<(String, int)>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Editar categoría'),
          content: SizedBox(
            width: 420,
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextFormField(
                    controller: controller,
                    autofocus: true,
                    textCapitalization: TextCapitalization.words,
                    maxLength: 40,
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Escribe un nombre para continuar.'
                        : null,
                    decoration: const InputDecoration(
                      labelText: 'Nombre de la categoría',
                      hintText: 'Ej.: Bebidas y alimentos',
                    ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
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
                    icon: Icon(
                      ProductCategories.iconFor(selectedIconCodePoint),
                    ),
                    label: const Text('Cambiar icono'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            FilledButton.icon(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.pop(dialogContext, (
                    controller.text.trim(),
                    selectedIconCodePoint,
                  ));
                }
              },
              icon: const Icon(Icons.save_outlined),
              label: const Text('Guardar cambios'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (result == null || !mounted) return;

    try {
      final updated = await ProductCategories.rename(
        category.name,
        result.$1,
        iconCodePoint: result.$2,
      );
      if (!mounted) return;
      if (!updated) {
        _showMessage('Ya existe una categoría con ese nombre.');
        return;
      }
      context.read<ProductBloc>().add(LoadProducts());
      setState(_reloadCategories);
      _showMessage('Categoría actualizada.');
    } catch (error) {
      if (mounted) _showMessage('No se pudo actualizar la categoría: $error');
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    final primaryForeground = theme.colorScheme.onPrimary;
    final colors = theme.colorScheme.copyWith(
      brightness: Brightness.light,
      primary: primaryColor,
      onPrimary: primaryForeground,
      primaryContainer: primaryColor.withValues(alpha: .12),
      onPrimaryContainer: primaryColor,
      surface: Colors.white,
      onSurface: const Color(0xFF1D2127),
      onSurfaceVariant: const Color(0xFF747B86),
      outlineVariant: const Color(0xFFE5E7EB),
    );
    final assignedCount = _categories
        .where((category) => _productCount(category.name) > 0)
        .length;
    final visibleCategories = _categories
        .where(
          (category) =>
              category.name.toLowerCase().contains(_query.trim().toLowerCase()),
        )
        .toList();

    return Theme(
      data: theme.copyWith(
        brightness: Brightness.light,
        colorScheme: colors,
        scaffoldBackgroundColor: const Color(0xFFF4F5F7),
        textTheme: theme.textTheme.apply(
          bodyColor: const Color(0xFF1D2127),
          displayColor: const Color(0xFF111111),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFF4F5F7),
          foregroundColor: Color(0xFF111111),
          centerTitle: true,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
        ),
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFFF4F5F7),
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
          backgroundColor: colors.primary,
          foregroundColor: colors.onPrimary,
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 96),
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: colors.primary,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: .12),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: .12),
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: Icon(
                          Icons.category_rounded,
                          color: colors.onPrimary,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Gestión de categorías',
                              style: TextStyle(
                                color: colors.onPrimary,
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            SizedBox(height: 3),
                            Text(
                              'Mantén tu catálogo ordenado y fácil de explorar.',
                              style: TextStyle(
                                color: Color(0xFFBFC3C9),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      _CategoryMetric(
                        label: 'CATEGORÍAS',
                        value: '${_categories.length}',
                      ),
                      const SizedBox(width: 10),
                      _CategoryMetric(label: 'EN USO', value: '$assignedCount'),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            TextField(
              onChanged: (value) => setState(() => _query = value),
              decoration: InputDecoration(
                hintText: 'Buscar categoría',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Limpiar búsqueda',
                        onPressed: () => setState(() => _query = ''),
                        icon: const Icon(Icons.close_rounded),
                      ),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: colors.primary, width: 1.4),
                ),
              ),
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Tus categorías',
                    style: TextStyle(
                      color: Color(0xFF17191D),
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  '${visibleCategories.length} resultados',
                  style: TextStyle(
                    color: colors.onSurfaceVariant,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 11),
            if (_categories.isEmpty)
              _CategoryEmptyState(
                icon: Icons.create_new_folder_outlined,
                title: 'Aún no tienes categorías',
                message:
                    'Crea la primera para organizar tus productos y encontrarlos más rápido.',
                action: _addCategory,
              )
            else if (visibleCategories.isEmpty)
              _CategoryEmptyState(
                icon: Icons.search_off_rounded,
                title: 'Sin resultados',
                message: 'Prueba con otro nombre de categoría.',
              )
            else
              ...visibleCategories.map((category) {
                final productCount = _productCount(category.name);
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(19),
                    border: Border.all(color: const Color(0xFFE7E9ED)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: .025),
                        blurRadius: 12,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.fromLTRB(14, 7, 8, 7),
                    leading: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: colors.primary,
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Icon(
                        category.icon,
                        size: 22,
                        color: colors.onPrimary,
                      ),
                    ),
                    title: Text(
                      category.name,
                      style: const TextStyle(
                        color: Color(0xFF1D2127),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '$productCount ${productCount == 1 ? 'producto' : 'productos'} asignados',
                        style: TextStyle(
                          color: colors.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Editar categoría',
                          onPressed: () => _editCategory(category),
                          style: IconButton.styleFrom(
                            foregroundColor: const Color(0xFF30343B),
                            backgroundColor: const Color(0xFFF3F4F6),
                          ),
                          icon: const Icon(Icons.edit_outlined, size: 18),
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          tooltip: 'Eliminar categoría',
                          onPressed: () => _removeCategory(category.name),
                          style: IconButton.styleFrom(
                            foregroundColor: productCount > 0
                                ? colors.onSurfaceVariant
                                : colors.error,
                          ),
                          icon: const Icon(
                            Icons.delete_outline_rounded,
                            size: 20,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}

class _CategoryMetric extends StatelessWidget {
  final String label;
  final String value;

  const _CategoryMetric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final foreground = Theme.of(context).colorScheme.onPrimary;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        decoration: BoxDecoration(
          color: foreground.withValues(alpha: .1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: foreground.withValues(alpha: .12)),
        ),
        child: Row(
          children: [
            Text(
              value,
              style: TextStyle(
                color: foreground,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: foreground.withValues(alpha: .74),
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: .7,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final VoidCallback? action;

  const _CategoryEmptyState({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(26),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE7E9ED)),
      ),
      child: Column(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: colors.primaryContainer,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(icon, size: 28, color: colors.primary),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF17191D),
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF747B86), height: 1.4),
          ),
          if (action != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: FilledButton.icon(
                onPressed: action,
                style: FilledButton.styleFrom(
                  backgroundColor: colors.primary,
                  foregroundColor: colors.onPrimary,
                ),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Crear categoría'),
              ),
            ),
        ],
      ),
    );
  }
}
