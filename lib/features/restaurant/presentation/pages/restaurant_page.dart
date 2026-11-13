import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/utils/app_currency.dart';
import '../../../billing/domain/entities/cart_item.dart';
import '../../../billing/presentation/bloc/billing_bloc.dart';
import '../../../product/domain/entities/product.dart';
import '../../../product/presentation/bloc/product_bloc.dart';
import '../../data/restaurant_repository.dart';
import '../../data/restaurant_menu_repository.dart';
import '../../domain/entities/restaurant_menu.dart';
import '../../domain/entities/restaurant_state.dart';

enum _TableFilter { all, available, reserved, occupied }

class RestaurantPage extends StatefulWidget {
  const RestaurantPage({super.key});

  @override
  State<RestaurantPage> createState() => _RestaurantPageState();
}

class _RestaurantPageState extends State<RestaurantPage> {
  final _repository = RestaurantRepository();
  final _menuRepository = RestaurantMenuRepository();
  RestaurantState _data = const RestaurantState();
  RestaurantMenuState _menu = const RestaurantMenuState();
  _TableFilter _filter = _TableFilter.all;
  bool _isLoading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = _repository.load();
      final menu = _menuRepository.load();
      if (!mounted) return;
      setState(() {
        _data = data;
        _menu = menu;
        _loadError = null;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = 'No se pudieron cargar las mesas: $error';
        _isLoading = false;
      });
    }
  }

  Future<bool> _save(RestaurantState next) async {
    try {
      await _repository.save(next);
      if (!mounted) return false;
      setState(() {
        _data = next;
        _loadError = null;
      });
      return true;
    } catch (error) {
      _showMessage('No se pudo guardar el cambio: $error');
      return false;
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  DateTime get _today {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  List<TableReservation> get _activeReservations =>
      _data.reservations
          .where(
            (reservation) =>
                reservation.isActive &&
                !DateTime(
                  reservation.startsAt.year,
                  reservation.startsAt.month,
                  reservation.startsAt.day,
                ).isBefore(_today),
          )
          .toList()
        ..sort((first, second) => first.startsAt.compareTo(second.startsAt));

  TableReservation? _reservationFor(DiningTable table) {
    for (final reservation in _data.reservations) {
      if (reservation.isActive &&
          reservation.tableId == table.id &&
          _sameDay(reservation.startsAt, _today)) {
        return reservation;
      }
    }
    return null;
  }

  bool _sameDay(DateTime first, DateTime second) =>
      first.year == second.year &&
      first.month == second.month &&
      first.day == second.day;

  bool _hasTimeConflict(String tableId, DateTime startsAt) {
    const serviceDuration = Duration(hours: 2);
    return _data.reservations.any((reservation) {
      if (!reservation.isActive || reservation.tableId != tableId) return false;
      final existingEnd = reservation.startsAt.add(serviceDuration);
      final requestedEnd = startsAt.add(serviceDuration);
      return startsAt.isBefore(existingEnd) &&
          reservation.startsAt.isBefore(requestedEnd);
    });
  }

  Future<void> _createTable() async {
    final result = await showDialog<({String name, int seats})>(
      context: context,
      builder: (context) => const _TableFormDialog(),
    );
    if (result == null || !mounted) return;
    final table = DiningTable(
      id: const Uuid().v4(),
      name: result.name,
      seats: result.seats,
    );
    await _save(
      RestaurantState(
        tables: [..._data.tables, table],
        reservations: _data.reservations,
      ),
    );
  }

  Future<void> _editTable(DiningTable table) async {
    final result = await showDialog<({String name, int seats})>(
      context: context,
      builder: (context) => _TableFormDialog(table: table),
    );
    if (result == null || !mounted) return;
    final tables = [
      for (final item in _data.tables)
        if (item.id == table.id)
          item.copyWith(name: result.name, seats: result.seats)
        else
          item,
    ];
    await _save(
      RestaurantState(tables: tables, reservations: _data.reservations),
    );
  }

  Future<void> _deleteTable(DiningTable table) async {
    if (table.isOpen ||
        _data.reservations.any(
          (reservation) =>
              reservation.isActive && reservation.tableId == table.id,
        )) {
      _showMessage(
        'Libera la mesa y cancela sus reservas activas antes de eliminarla.',
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.delete_outline_rounded),
        title: Text('Eliminar ${table.name}'),
        content: const Text(
          'Esta acción elimina la mesa de la configuración del restaurante.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Conservar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar mesa'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final tables = _data.tables.where((item) => item.id != table.id).toList();
    final reservations = _data.reservations
        .where((item) => item.tableId != table.id)
        .toList();
    await _save(RestaurantState(tables: tables, reservations: reservations));
  }

  Future<void> _createReservation({String? tableId}) async {
    if (_data.tables.isEmpty) {
      _showMessage('Crea una mesa antes de registrar una reserva.');
      return;
    }
    final reservation = await showDialog<TableReservation>(
      context: context,
      builder: (context) => _ReservationFormDialog(
        tables: _data.tables,
        initialTableId: tableId,
        hasConflict: _hasTimeConflict,
      ),
    );
    if (reservation == null || !mounted) return;
    await _save(
      RestaurantState(
        tables: _data.tables,
        reservations: [..._data.reservations, reservation],
      ),
    );
  }

  Future<void> _cancelReservation(TableReservation reservation) async {
    final reservations = [
      for (final item in _data.reservations)
        if (item.id == reservation.id)
          item.copyWith(status: 'cancelled')
        else
          item,
    ];
    await _save(
      RestaurantState(tables: _data.tables, reservations: reservations),
    );
  }

  Future<void> _seatReservation(TableReservation reservation) async {
    final tableIndex = _data.tables.indexWhere(
      (table) => table.id == reservation.tableId,
    );
    if (tableIndex < 0) {
      _showMessage('La mesa asociada a esta reserva ya no existe.');
      return;
    }
    final table = _data.tables[tableIndex];
    if (table.isOpen) {
      _showMessage('${table.name} ya tiene una atención abierta.');
      return;
    }
    final tables = [..._data.tables]
      ..[tableIndex] = table.copyWith(openedAt: DateTime.now());
    final reservations = [
      for (final item in _data.reservations)
        if (item.id == reservation.id)
          item.copyWith(status: 'seated')
        else
          item,
    ];
    final saved = await _save(
      RestaurantState(tables: tables, reservations: reservations),
    );
    if (saved && mounted) await _openTable(tables[tableIndex]);
  }

  Future<void> _openTable(DiningTable initialTable) async {
    final table = _data.tables.firstWhere(
      (item) => item.id == initialTable.id,
      orElse: () => initialTable,
    );
    final reservation = _reservationFor(table);
    final menu = _menuRepository.load();
    if (mounted) setState(() => _menu = menu);
    final products = menu.products
        .where((product) => product.isAvailable)
        .map((product) => _asMenuCartProduct(product, menu))
        .toList();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => _DiningTableDialog(
        table: table,
        reservation: reservation,
        products: products,
        onStart: () async {
          final index = _data.tables.indexWhere((item) => item.id == table.id);
          if (index < 0) return false;
          final tables = [..._data.tables]
            ..[index] = _data.tables[index].copyWith(openedAt: DateTime.now());
          final reservations = reservation == null
              ? _data.reservations
              : [
                  for (final item in _data.reservations)
                    if (item.id == reservation.id)
                      item.copyWith(status: 'seated')
                    else
                      item,
                ];
          return _save(
            RestaurantState(tables: tables, reservations: reservations),
          );
        },
        onAddProduct: (product) => _addProductToTable(table, product),
        onUpdateQuantity: (lineIndex, quantity) =>
            _updateOrderQuantity(table, lineIndex, quantity),
        onClear: () => _clearTable(table),
        onCheckout: () => _checkoutTable(table),
        onEdit: () => _editTable(table),
      ),
    );
  }

  Future<bool> _addProductToTable(DiningTable table, Product product) async {
    final latest = _data.tables.firstWhere(
      (item) => item.id == table.id,
      orElse: () => table,
    );
    final existingCurrency = latest.order.isEmpty
        ? null
        : latest.order.first.currencyCode;
    if (existingCurrency != null && existingCurrency != product.currencyCode) {
      _showMessage(
        'No se pueden mezclar monedas distintas en el pedido de una mesa.',
      );
      return false;
    }
    final index = latest.order.indexWhere(
      (line) =>
          line.productId == product.id &&
          line.variantId == product.selectedVariantId,
    );
    final quantity = (index < 0 ? 0.0 : latest.order[index].quantity) + 1;
    if (product.inventoryTracked && quantity > product.availableStock) {
      _showMessage('No hay existencias suficientes de "${product.name}".');
      return false;
    }
    final lines = [...latest.order];
    final line = TableOrderLine(
      productId: product.id,
      variantId: product.selectedVariantId,
      name: product.variationLabel.isEmpty
          ? product.name
          : '${product.name} · ${product.variationLabel}',
      currencyCode: product.currencyCode,
      quantity: quantity,
      unitPrice: product.price,
      category: product.category,
      inventoryTracked: product.inventoryTracked,
    );
    if (index < 0) {
      lines.add(line);
    } else {
      lines[index] = line;
    }
    return _replaceTable(latest.copyWith(order: lines));
  }

  Future<bool> _updateOrderQuantity(
    DiningTable table,
    int lineIndex,
    double quantity,
  ) async {
    final latest = _data.tables.firstWhere(
      (item) => item.id == table.id,
      orElse: () => table,
    );
    if (lineIndex < 0 || lineIndex >= latest.order.length) return false;
    final lines = [...latest.order];
    if (quantity <= 0) {
      lines.removeAt(lineIndex);
    } else {
      final line = lines[lineIndex];
      final product = _findProduct(line);
      if (line.inventoryTracked &&
          (product == null || quantity > product.availableStock)) {
        _showMessage(
          'No hay existencias suficientes para actualizar la cantidad.',
        );
        return false;
      }
      lines[lineIndex] = TableOrderLine(
        productId: line.productId,
        variantId: line.variantId,
        name: line.name,
        currencyCode: line.currencyCode,
        quantity: quantity,
        unitPrice: line.unitPrice,
        category: line.category,
        inventoryTracked: line.inventoryTracked,
      );
    }
    return _replaceTable(latest.copyWith(order: lines));
  }

  Product? _findProduct(TableOrderLine line) {
    if (!line.inventoryTracked) return null;
    final products = context.read<ProductBloc>().state.products;
    for (final product in products) {
      if (product.id != line.productId) continue;
      if (line.variantId == null) return product;
      for (final variant in product.variants) {
        if (variant.id == line.variantId) return product.forVariant(variant);
      }
      return null;
    }
    return null;
  }

  Future<bool> _replaceTable(DiningTable updated) async {
    final tables = [
      for (final item in _data.tables)
        if (item.id == updated.id) updated else item,
    ];
    return _save(
      RestaurantState(tables: tables, reservations: _data.reservations),
    );
  }

  Future<void> _clearTable(DiningTable table) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Liberar mesa sin cobrar'),
        content: const Text(
          'Se descartará el pedido abierto. ¿Confirmas que deseas liberar esta mesa?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Volver al pedido'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Liberar mesa'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final latest = _data.tables.firstWhere(
      (item) => item.id == table.id,
      orElse: () => table,
    );
    final updated = latest.copyWith(clearSession: true);
    if (await _replaceTable(updated) && mounted) Navigator.pop(context);
  }

  Future<void> _checkoutTable(DiningTable table) async {
    final latest = _data.tables.firstWhere(
      (item) => item.id == table.id,
      orElse: () => table,
    );
    if (latest.order.isEmpty) {
      _showMessage('Agrega productos al pedido antes de enviarlo a caja.');
      return;
    }
    final billing = context.read<BillingBloc>();
    if (billing.state.cartItems.isNotEmpty) {
      _showMessage(
        'Hay una venta abierta. Finalízala o límpiala antes de cobrar la mesa.',
      );
      return;
    }
    final catalog = context.read<ProductBloc>().state.products;
    final cartItems = <CartItem>[];
    for (final line in latest.order) {
      if (!line.inventoryTracked) {
        cartItems.add(
          CartItem(
            product: Product(
              id: line.productId,
              name: line.name,
              barcode: '',
              price: line.unitPrice,
              stock: double.infinity,
              currencyCode: line.currencyCode,
              category: line.category,
              inventoryTracked: false,
            ),
            quantity: line.quantity,
          ),
        );
        continue;
      }
      Product? current;
      for (final product in catalog) {
        if (product.id == line.productId) {
          current = product;
          break;
        }
      }
      if (current == null) {
        _showMessage(
          'El producto "${line.name}" ya no existe en el inventario.',
        );
        return;
      }
      Product? selectedVariantProduct;
      if (line.variantId != null) {
        for (final variant in current.variants) {
          if (variant.id == line.variantId) {
            selectedVariantProduct = current.forVariant(variant);
            break;
          }
        }
        if (selectedVariantProduct == null) {
          _showMessage(
            'La variación "${line.name}" ya no está disponible en el inventario.',
          );
          return;
        }
      }
      final source = selectedVariantProduct ?? current;
      if (source.currencyCode != line.currencyCode) {
        _showMessage(
          'La moneda de "${line.name}" cambió en el catálogo. '
          'Actualiza el pedido antes de cobrar.',
        );
        return;
      }
      if (line.quantity > source.availableStock) {
        _showMessage(
          'Existencias insuficientes para "${line.name}". '
          'Disponibles: ${source.availableStock}.',
        );
        return;
      }
      cartItems.add(
        CartItem(
          product: Product(
            id: source.id,
            name: source.name,
            barcode: source.barcode,
            price: line.unitPrice,
            stock: source.stock,
            description: source.description,
            imageData: source.imageData,
            currencyCode: source.currencyCode,
            category: source.category,
            unitLabel: source.unitLabel,
            variants: source.variants,
            selectedVariantId: source.selectedVariantId,
            inventoryTracked: source.inventoryTracked,
          ),
          quantity: line.quantity,
        ),
      );
    }

    final cartChanged = billing.stream.firstWhere(
      (state) =>
          state.cartItems.length == cartItems.length || state.error != null,
    );
    billing.add(LoadTableOrderEvent(cartItems));
    try {
      final loadedState = await cartChanged.timeout(const Duration(seconds: 5));
      if (loadedState.error != null || loadedState.cartItems.isEmpty) {
        _showMessage(loadedState.error ?? 'No se pudo preparar el pedido.');
        return;
      }
      if (mounted) {
        await context.push(
          '/checkout',
          extra: {'tableId': table.id, 'tableName': table.name},
        );
      }
    } on TimeoutException {
      _showMessage('La caja no respondió a tiempo. El pedido sigue guardado.');
    }
  }

  Product _asMenuCartProduct(
    RestaurantMenuProduct item,
    RestaurantMenuState menu,
  ) {
    RestaurantMenuCategory? category;
    for (final candidate in menu.categories) {
      if (candidate.id == item.categoryId) {
        category = candidate;
        break;
      }
    }
    return Product(
      id: 'restaurant-menu:${item.id}',
      name: item.name,
      barcode: '',
      price: item.price,
      stock: double.infinity,
      description: item.description,
      currencyCode: item.currencyCode,
      category: category?.name ?? 'Menú',
      inventoryTracked: false,
    );
  }

  Future<void> _openRestaurantMenu() async {
    await context.push('/restaurant/menu');
    if (!mounted) return;
    try {
      setState(() => _menu = _menuRepository.load());
    } catch (error) {
      _showMessage('No se pudo actualizar el menú: $error');
    }
  }

  Future<void> _handleReservationAction(
    TableReservation reservation,
    bool seat,
  ) async {
    if (seat) {
      await _seatReservation(reservation);
    } else {
      await _cancelReservation(reservation);
    }
  }

  String _tableStatus(DiningTable table) {
    if (table.isOpen) return 'En servicio';
    if (_reservationFor(table) != null) return 'Reservada hoy';
    return 'Disponible';
  }

  Color _statusColor(BuildContext context, DiningTable table) {
    if (table.isOpen) return const Color(0xFFB54735);
    if (_reservationFor(table) != null) return const Color(0xFF9A6700);
    return const Color(0xFF17815D);
  }

  @override
  Widget build(BuildContext context) {
    AppCurrencyScope.of(context);
    final colors = Theme.of(context).colorScheme;
    final reservedToday = _data.reservations
        .where(
          (item) =>
              item.isActive &&
              _sameDay(item.startsAt, _today) &&
              !_data.tables.any(
                (table) => table.id == item.tableId && table.isOpen,
              ),
        )
        .length;
    final occupiedCount = _data.tables.where((table) => table.isOpen).length;
    final filteredTables =
        _data.tables.where((table) {
          return switch (_filter) {
            _TableFilter.all => true,
            _TableFilter.available =>
              !table.isOpen && _reservationFor(table) == null,
            _TableFilter.reserved =>
              !table.isOpen && _reservationFor(table) != null,
            _TableFilter.occupied => table.isOpen,
          };
        }).toList()..sort(
          (first, second) =>
              first.name.toLowerCase().compareTo(second.name.toLowerCase()),
        );

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Restaurante'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Opciones del restaurante',
            onSelected: (value) {
              if (value == 'menu') _openRestaurantMenu();
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'menu',
                child: ListTile(
                  leading: Icon(Icons.restaurant_menu_rounded),
                  title: Text('Menú del restaurante'),
                  subtitle: Text('Productos y categorías'),
                ),
              ),
            ],
          ),
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _isLoading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: _data.tables.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _createReservation(),
              icon: const Icon(Icons.event_available_rounded),
              label: const Text('Nueva reserva'),
            ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
          ? _LoadFailure(message: _loadError!, onRetry: _load)
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 100),
                children: [
                  _RestaurantHeader(
                    tableCount: _data.tables.length,
                    occupiedCount: occupiedCount,
                    reservationCount: reservedToday,
                    menuProductCount: _menu.products.length,
                    onCreateTable: _createTable,
                    onCreateReservation: () => _createReservation(),
                    onManageMenu: _openRestaurantMenu,
                  ),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Plano de mesas',
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'Consulta la disponibilidad y gestiona el salón',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: colors.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: _createTable,
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('Agregar mesa'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final filter in _TableFilter.values)
                        FilterChip(
                          selected: _filter == filter,
                          backgroundColor: colors.surface,
                          selectedColor: colors.primaryContainer,
                          side: BorderSide(
                            color: _filter == filter
                                ? colors.primary.withValues(alpha: .25)
                                : colors.outlineVariant,
                          ),
                          label: Text(switch (filter) {
                            _TableFilter.all => 'Todas',
                            _TableFilter.available => 'Disponibles',
                            _TableFilter.reserved => 'Reservadas',
                            _TableFilter.occupied => 'En servicio',
                          }),
                          onSelected: (_) => setState(() => _filter = filter),
                          showCheckmark: false,
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  if (filteredTables.isEmpty)
                    _EmptyTables(
                      hasTables: _data.tables.isNotEmpty,
                      onCreate: _createTable,
                    )
                  else
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final columns = constraints.maxWidth >= 1000
                            ? 4
                            : constraints.maxWidth >= 700
                            ? 3
                            : constraints.maxWidth >= 440
                            ? 2
                            : 1;
                        final tileWidth =
                            (constraints.maxWidth - (columns - 1) * 12) /
                            columns;
                        return Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            for (final table in filteredTables)
                              SizedBox(
                                width: tileWidth,
                                child: _DiningTableCard(
                                  table: table,
                                  reservation: _reservationFor(table),
                                  status: _tableStatus(table),
                                  statusColor: _statusColor(context, table),
                                  onTap: () => _openTable(table),
                                  onReserve: () =>
                                      _createReservation(tableId: table.id),
                                  onEdit: () => _editTable(table),
                                  onDelete: () => _deleteTable(table),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  const SizedBox(height: 28),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Reservas próximas',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      Text(
                        '${_activeReservations.length} activas',
                        style: TextStyle(color: colors.onSurfaceVariant),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (_activeReservations.isEmpty)
                    const _NoReservations()
                  else
                    for (final reservation in _activeReservations)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _ReservationCard(
                          reservation: reservation,
                          table: _tableById(reservation.tableId),
                          onSeat: () =>
                              _handleReservationAction(reservation, true),
                          onCancel: () =>
                              _handleReservationAction(reservation, false),
                        ),
                      ),
                ],
              ),
            ),
    );
  }

  DiningTable? _tableById(String id) {
    for (final table in _data.tables) {
      if (table.id == id) return table;
    }
    return null;
  }
}

class _RestaurantHeader extends StatelessWidget {
  final int tableCount;
  final int occupiedCount;
  final int reservationCount;
  final int menuProductCount;
  final VoidCallback onCreateTable;
  final VoidCallback onCreateReservation;
  final VoidCallback onManageMenu;

  const _RestaurantHeader({
    required this.tableCount,
    required this.occupiedCount,
    required this.reservationCount,
    required this.menuProductCount,
    required this.onCreateTable,
    required this.onCreateReservation,
    required this.onManageMenu,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: .7)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .045),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final spacing = 10.0;
          final statWidth = constraints.maxWidth < 520
              ? (constraints.maxWidth - spacing) / 2
              : (constraints.maxWidth - spacing * 3) / 4;
          return Column(
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
                      Icons.table_restaurant_rounded,
                      color: colors.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'SERVICIO DE SALÓN',
                          style: TextStyle(
                            color: colors.primary,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Mesas y reservas',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Organiza el salón, registra pedidos y envía la cuenta a caja.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: [
                  SizedBox(
                    width: statWidth,
                    child: _HeaderStat(
                      label: 'Mesas',
                      value: '$tableCount',
                      icon: Icons.table_restaurant_outlined,
                      color: colors.primary,
                    ),
                  ),
                  SizedBox(
                    width: statWidth,
                    child: _HeaderStat(
                      label: 'En servicio',
                      value: '$occupiedCount',
                      icon: Icons.room_service_outlined,
                      color: const Color(0xFFB54735),
                    ),
                  ),
                  SizedBox(
                    width: statWidth,
                    child: _HeaderStat(
                      label: 'Reservas hoy',
                      value: '$reservationCount',
                      icon: Icons.event_available_outlined,
                      color: const Color(0xFF9A6700),
                    ),
                  ),
                  SizedBox(
                    width: statWidth,
                    child: _HeaderStat(
                      label: 'Productos menú',
                      value: '$menuProductCount',
                      icon: Icons.restaurant_menu_outlined,
                      color: const Color(0xFF7057A3),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton.icon(
                    onPressed: onCreateReservation,
                    icon: const Icon(Icons.event_available_rounded),
                    label: const Text('Nueva reserva'),
                  ),
                  OutlinedButton.icon(
                    onPressed: onCreateTable,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Agregar mesa'),
                  ),
                  TextButton.icon(
                    onPressed: onManageMenu,
                    icon: const Icon(Icons.restaurant_menu_rounded),
                    label: const Text('Menú'),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _HeaderStat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _HeaderStat({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .07),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: color.withValues(alpha: .12)),
    ),
    child: Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: color.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(icon, size: 18, color: color),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color.withValues(alpha: .85),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  color: color,
                  fontSize: 20,
                  height: 1.1,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _DiningTableCard extends StatelessWidget {
  final DiningTable table;
  final TableReservation? reservation;
  final String status;
  final Color statusColor;
  final VoidCallback onTap;
  final VoidCallback onReserve;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _DiningTableCard({
    required this.table,
    required this.reservation,
    required this.status,
    required this.statusColor,
    required this.onTap,
    required this.onReserve,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final currency = table.order.isEmpty
        ? null
        : table.order.first.currencyCode;
    final total = table.order.fold<double>(0, (sum, line) => sum + line.total);
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(17),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: statusColor.withValues(alpha: .24)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: .025),
                blurRadius: 12,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: .1),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(
                      Icons.table_restaurant_rounded,
                      color: statusColor,
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          table.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          '${table.seats} ${table.seats == 1 ? 'puesto' : 'puestos'}',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colors.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Opciones de mesa',
                    onSelected: (value) {
                      if (value == 'edit') onEdit();
                      if (value == 'delete') onDelete();
                      if (value == 'reserve') onReserve();
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'edit',
                        child: ListTile(
                          leading: Icon(Icons.edit_outlined),
                          title: Text('Editar mesa'),
                        ),
                      ),
                      if (!table.isOpen)
                        const PopupMenuItem(
                          value: 'reserve',
                          child: ListTile(
                            leading: Icon(Icons.event_available_outlined),
                            title: Text('Crear reserva'),
                          ),
                        ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: ListTile(
                          leading: Icon(Icons.delete_outline),
                          title: Text('Eliminar mesa'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 15),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      status,
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              if (reservation != null) ...[
                const SizedBox(height: 10),
                Text(
                  '${DateFormat('HH:mm', 'es').format(reservation!.startsAt)} · '
                  '${reservation!.customerName} · ${reservation!.guests} personas',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              if (table.isOpen) ...[
                const SizedBox(height: 12),
                Divider(height: 1, color: colors.outlineVariant),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${table.order.length} ${table.order.length == 1 ? 'producto' : 'productos'}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    if (currency != null)
                      Text(
                        AppCurrency.format(total, code: currency),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ReservationCard extends StatelessWidget {
  final TableReservation reservation;
  final DiningTable? table;
  final VoidCallback onSeat;
  final VoidCallback onCancel;

  const _ReservationCard({
    required this.reservation,
    required this.table,
    required this.onSeat,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final date = reservation.startsAt;
    final colors = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colors.outlineVariant.withValues(alpha: .65)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 52,
              decoration: BoxDecoration(
                color: colors.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    DateFormat('dd', 'es').format(date),
                    style: TextStyle(
                      color: colors.primary,
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    DateFormat('MMM', 'es').format(date).toUpperCase(),
                    style: TextStyle(
                      color: colors.primary,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    reservation.customerName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${table?.name ?? 'Mesa eliminada'} · '
                    '${DateFormat('HH:mm', 'es').format(date)} · '
                    '${reservation.guests} personas',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (reservation.phone.isNotEmpty)
                    Text(
                      reservation.phone,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                ],
              ),
            ),
            if (_isToday(date) && table != null && !table!.isOpen)
              IconButton.filledTonal(
                tooltip: 'Sentar clientes',
                onPressed: onSeat,
                icon: const Icon(Icons.event_seat_rounded),
              ),
            IconButton(
              tooltip: 'Cancelar reserva',
              onPressed: onCancel,
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
      ),
    );
  }

  bool _isToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }
}

class _TableFormDialog extends StatefulWidget {
  final DiningTable? table;

  const _TableFormDialog({this.table});

  @override
  State<_TableFormDialog> createState() => _TableFormDialogState();
}

class _TableFormDialogState extends State<_TableFormDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _seatsController;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.table?.name ?? '');
    _seatsController = TextEditingController(
      text: '${widget.table?.seats ?? 4}',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _seatsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.table == null ? 'Configurar mesa' : 'Editar mesa'),
    content: SizedBox(
      width: 380,
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _nameController,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Nombre o número',
                hintText: 'Ej. Terraza 1',
                prefixIcon: Icon(Icons.table_restaurant_outlined),
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Indica el nombre de la mesa.'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _seatsController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Capacidad',
                suffixText: 'puestos',
                prefixIcon: Icon(Icons.chair_alt_outlined),
              ),
              validator: (value) {
                final seats = int.tryParse(value ?? '');
                return seats == null || seats < 1 || seats > 100
                    ? 'La capacidad debe estar entre 1 y 100.'
                    : null;
              },
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
      FilledButton.icon(
        onPressed: () {
          if (!_formKey.currentState!.validate()) return;
          Navigator.pop(context, (
            name: _nameController.text.trim(),
            seats: int.parse(_seatsController.text),
          ));
        },
        icon: Icon(
          widget.table == null ? Icons.add_rounded : Icons.save_rounded,
        ),
        label: Text(widget.table == null ? 'Crear mesa' : 'Guardar cambios'),
      ),
    ],
  );
}

class _ReservationFormDialog extends StatefulWidget {
  final List<DiningTable> tables;
  final String? initialTableId;
  final bool Function(String, DateTime) hasConflict;

  const _ReservationFormDialog({
    required this.tables,
    required this.hasConflict,
    this.initialTableId,
  });

  @override
  State<_ReservationFormDialog> createState() => _ReservationFormDialogState();
}

class _ReservationFormDialogState extends State<_ReservationFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _guestsController = TextEditingController(text: '2');
  final _notesController = TextEditingController();
  late String _tableId;
  late DateTime _startsAt;

  @override
  void initState() {
    super.initState();
    _tableId = widget.initialTableId ?? widget.tables.first.id;
    final now = DateTime.now();
    _startsAt = DateTime(
      now.year,
      now.month,
      now.day,
      now.hour + (now.minute >= 30 ? 1 : 0),
      now.minute < 30 ? 30 : 0,
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _guestsController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _chooseDate() async {
    final now = DateTime.now();
    final initial = _startsAt.isBefore(DateTime(now.year, now.month, now.day))
        ? DateTime(now.year, now.month, now.day)
        : _startsAt;
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 3),
      helpText: 'Día de la reserva',
      cancelText: 'Cancelar',
      confirmText: 'Continuar',
    );
    if (date == null || !mounted) return;
    setState(() {
      _startsAt = DateTime(
        date.year,
        date.month,
        date.day,
        _startsAt.hour,
        _startsAt.minute,
      );
    });
  }

  Future<void> _chooseTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_startsAt),
      helpText: 'Hora de llegada',
      cancelText: 'Cancelar',
      confirmText: 'Aplicar',
    );
    if (time == null || !mounted) return;
    setState(() {
      _startsAt = DateTime(
        _startsAt.year,
        _startsAt.month,
        _startsAt.day,
        time.hour,
        time.minute,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final table = widget.tables.firstWhere((item) => item.id == _tableId);
    return AlertDialog(
      title: const Text('Nueva reserva'),
      content: SizedBox(
        width: 430,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _nameController,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Nombre del cliente',
                    prefixIcon: Icon(Icons.person_outline_rounded),
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Indica el nombre del cliente.'
                      : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Teléfono (opcional)',
                    prefixIcon: Icon(Icons.phone_outlined),
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: _tableId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Mesa',
                    prefixIcon: Icon(Icons.table_restaurant_outlined),
                  ),
                  items: [
                    for (final item in widget.tables)
                      DropdownMenuItem(
                        value: item.id,
                        child: Text('${item.name} · ${item.seats} puestos'),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _tableId = value);
                  },
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _guestsController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Personas',
                    prefixIcon: Icon(Icons.groups_outlined),
                  ),
                  validator: (value) {
                    final guests = int.tryParse(value ?? '');
                    if (guests == null || guests < 1) {
                      return 'Indica cuántas personas asistirán.';
                    }
                    if (guests > table.seats) {
                      return 'La mesa admite hasta ${table.seats} personas.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _chooseDate,
                        icon: const Icon(Icons.calendar_today_outlined),
                        label: Text(
                          DateFormat('EEE d MMM', 'es').format(_startsAt),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: _chooseTime,
                      icon: const Icon(Icons.schedule_rounded),
                      label: Text(DateFormat('HH:mm', 'es').format(_startsAt)),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _notesController,
                  textCapitalization: TextCapitalization.sentences,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Notas para el servicio (opcional)',
                    prefixIcon: Icon(Icons.notes_rounded),
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
        FilledButton.icon(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            if (_startsAt.isBefore(DateTime.now())) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('La reserva no puede quedar en el pasado.'),
                ),
              );
              return;
            }
            if (widget.hasConflict(_tableId, _startsAt)) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Esta mesa ya tiene una reserva dentro de ese horario. '
                    'El servicio se bloquea por dos horas.',
                  ),
                ),
              );
              return;
            }
            Navigator.pop(
              context,
              TableReservation(
                id: const Uuid().v4(),
                tableId: _tableId,
                customerName: _nameController.text.trim(),
                phone: _phoneController.text.trim(),
                guests: int.parse(_guestsController.text),
                startsAt: _startsAt,
                notes: _notesController.text.trim(),
              ),
            );
          },
          icon: const Icon(Icons.event_available_rounded),
          label: const Text('Confirmar reserva'),
        ),
      ],
    );
  }
}

class _DiningTableDialog extends StatefulWidget {
  final DiningTable table;
  final TableReservation? reservation;
  final List<Product> products;
  final Future<bool> Function() onStart;
  final Future<bool> Function(Product) onAddProduct;
  final Future<bool> Function(int, double) onUpdateQuantity;
  final Future<void> Function() onClear;
  final Future<void> Function() onCheckout;
  final Future<void> Function() onEdit;

  const _DiningTableDialog({
    required this.table,
    required this.reservation,
    required this.products,
    required this.onStart,
    required this.onAddProduct,
    required this.onUpdateQuantity,
    required this.onClear,
    required this.onCheckout,
    required this.onEdit,
  });

  @override
  State<_DiningTableDialog> createState() => _DiningTableDialogState();
}

class _DiningTableDialogState extends State<_DiningTableDialog> {
  late DiningTable _table;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _table = widget.table;
  }

  Future<void> _start() async {
    setState(() => _working = true);
    final saved = await widget.onStart();
    if (mounted) {
      setState(() {
        if (saved) {
          _table = _table.copyWith(openedAt: DateTime.now());
        }
        _working = false;
      });
    }
  }

  Future<void> _addItem() async {
    final product = await showModalBottomSheet<Product>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (context) => _ProductPickerSheet(products: widget.products),
    );
    if (product == null || !mounted) return;
    setState(() => _working = true);
    final saved = await widget.onAddProduct(product);
    if (mounted) {
      setState(() {
        if (saved) {
          final index = _table.order.indexWhere(
            (line) =>
                line.productId == product.id &&
                line.variantId == product.selectedVariantId,
          );
          final lines = [..._table.order];
          final line = TableOrderLine(
            productId: product.id,
            variantId: product.selectedVariantId,
            name: product.variationLabel.isEmpty
                ? product.name
                : '${product.name} · ${product.variationLabel}',
            currencyCode: product.currencyCode,
            quantity: index < 0 ? 1 : lines[index].quantity + 1,
            unitPrice: product.price,
            category: product.category,
            inventoryTracked: product.inventoryTracked,
          );
          if (index < 0) {
            lines.add(line);
          } else {
            lines[index] = line;
          }
          _table = _table.copyWith(order: lines);
        }
        _working = false;
      });
    }
  }

  Future<void> _setQuantity(int index, double quantity) async {
    setState(() => _working = true);
    final saved = await widget.onUpdateQuantity(index, quantity);
    if (mounted) {
      setState(() {
        if (saved) {
          final lines = [..._table.order];
          if (quantity <= 0) {
            lines.removeAt(index);
          } else {
            final line = lines[index];
            lines[index] = TableOrderLine(
              productId: line.productId,
              variantId: line.variantId,
              name: line.name,
              currencyCode: line.currencyCode,
              quantity: quantity,
              unitPrice: line.unitPrice,
              category: line.category,
              inventoryTracked: line.inventoryTracked,
            );
          }
          _table = _table.copyWith(order: lines);
        }
        _working = false;
      });
    }
  }

  Future<void> _checkout() async {
    if (_table.order.isEmpty) return;
    Navigator.pop(context);
    await widget.onCheckout();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final currencyCode = _table.order.isEmpty
        ? AppCurrency.baseCode
        : _table.order.first.currencyCode;
    final total = _table.order.fold<double>(0, (sum, line) => sum + line.total);
    final elapsed = _table.openedAt == null
        ? null
        : DateTime.now().difference(_table.openedAt!);
    final headerForeground = colors.onPrimary;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 540,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 18),
              color: colors.primary,
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: headerForeground.withValues(alpha: .14),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(
                      Icons.table_restaurant_rounded,
                      color: headerForeground,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _table.name,
                          style: TextStyle(
                            color: headerForeground,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          elapsed == null
                              ? '${_table.seats} puestos · Sin servicio abierto'
                              : '${_table.seats} puestos · '
                                    '${_durationLabel(elapsed)} en servicio',
                          style: TextStyle(
                            color: headerForeground.withValues(alpha: .75),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Editar mesa',
                    onPressed: () async {
                      Navigator.pop(context);
                      await widget.onEdit();
                    },
                    color: headerForeground,
                    icon: const Icon(Icons.edit_outlined),
                  ),
                  IconButton(
                    tooltip: 'Cerrar',
                    onPressed: () => Navigator.pop(context),
                    color: headerForeground,
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Flexible(
              child: _working
                  ? const SizedBox(
                      height: 260,
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (widget.reservation case final reservation?)
                            _ReservationSummary(reservation: reservation),
                          if (!_table.isOpen) ...[
                            const SizedBox(height: 8),
                            FilledButton.icon(
                              onPressed: _start,
                              icon: const Icon(Icons.play_arrow_rounded),
                              label: const Text('Abrir servicio de mesa'),
                            ),
                          ] else ...[
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Pedido de la mesa',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w800),
                                  ),
                                ),
                                TextButton.icon(
                                  onPressed: _addItem,
                                  icon: const Icon(Icons.add_rounded, size: 18),
                                  label: const Text('Agregar'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            if (_table.order.isEmpty)
                              const _EmptyOrder()
                            else
                              for (
                                var index = 0;
                                index < _table.order.length;
                                index++
                              )
                                _OrderLineTile(
                                  line: _table.order[index],
                                  onDecrease: () => _setQuantity(
                                    index,
                                    _table.order[index].quantity - 1,
                                  ),
                                  onIncrease: () => _setQuantity(
                                    index,
                                    _table.order[index].quantity + 1,
                                  ),
                                ),
                            const SizedBox(height: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 14,
                              ),
                              decoration: BoxDecoration(
                                color: colors.surfaceContainerHighest
                                    .withValues(alpha: .45),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Row(
                                children: [
                                  const Expanded(
                                    child: Text(
                                      'Total de la cuenta',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    AppCurrency.format(
                                      total,
                                      code: currencyCode,
                                    ),
                                    style: TextStyle(
                                      color: colors.primary,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 18),
              child: Row(
                children: [
                  if (_table.isOpen)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: widget.onClear,
                        icon: const Icon(Icons.logout_rounded),
                        label: const Text('Liberar'),
                      ),
                    ),
                  if (_table.isOpen) const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: !_table.isOpen || _table.order.isEmpty
                          ? null
                          : _checkout,
                      icon: const Icon(Icons.point_of_sale_rounded),
                      label: const Text('Enviar a caja'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _durationLabel(Duration duration) {
    if (duration.inHours > 0) {
      return '${duration.inHours} h ${duration.inMinutes.remainder(60)} min';
    }
    return '${math.max(duration.inMinutes, 1)} min';
  }
}

class _ReservationSummary extends StatelessWidget {
  final TableReservation reservation;

  const _ReservationSummary({required this.reservation});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const reservationAccent = Color(0xFF936200);
    final accent = isDark
        ? Color.lerp(reservationAccent, Colors.white, .45)!
        : reservationAccent;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          accent.withValues(alpha: isDark ? .16 : .08),
          colors.surface,
        ),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: accent.withValues(alpha: isDark ? .45 : .3)),
      ),
      child: Row(
        children: [
          Icon(Icons.event_available_rounded, color: accent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Reserva de ${reservation.customerName}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(
                  '${DateFormat('HH:mm', 'es').format(reservation.startsAt)} · '
                  '${reservation.guests} personas'
                  '${reservation.phone.isEmpty ? '' : ' · ${reservation.phone}'}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (reservation.notes.isNotEmpty)
                  Text(
                    reservation.notes,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductPickerSheet extends StatefulWidget {
  final List<Product> products;

  const _ProductPickerSheet({required this.products});

  @override
  State<_ProductPickerSheet> createState() => _ProductPickerSheetState();
}

class _ProductPickerSheetState extends State<_ProductPickerSheet> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final products = widget.products
        .where(
          (product) =>
              product.name.toLowerCase().contains(_query.toLowerCase()) ||
              product.category.toLowerCase().contains(_query.toLowerCase()) ||
              product.barcode.toLowerCase().contains(_query.toLowerCase()),
        )
        .toList();
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .82,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Agregar al pedido',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  '${products.length} productos',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextField(
              controller: _searchController,
              onChanged: (value) => setState(() => _query = value.trim()),
              decoration: InputDecoration(
                hintText: 'Buscar por nombre, categoría o código',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                        icon: const Icon(Icons.close_rounded),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: products.isEmpty
                ? Center(
                    child: Text(
                      widget.products.isEmpty
                          ? 'Aún no hay productos disponibles en el menú del restaurante.'
                          : 'No encontramos productos con esa búsqueda.',
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                    itemCount: products.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      final product = products[index];
                      final variants = product.hasVariants
                          ? product.variants
                          : const [];
                      return Card(
                        elevation: 0,
                        color: colors.surfaceContainerLow,
                        child: Column(
                          children: [
                            ListTile(
                              leading: CircleAvatar(
                                backgroundColor: colors.primaryContainer,
                                child: Icon(
                                  Icons.restaurant_menu_rounded,
                                  color: colors.primary,
                                ),
                              ),
                              title: Text(
                                product.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              subtitle: Text(
                                product.inventoryTracked
                                    ? '${product.category.isEmpty ? 'Menú' : product.category} · '
                                          '${product.availableStock} ${product.unitLabel} disponibles'
                                    : '${product.category.isEmpty ? 'Menú' : product.category} · '
                                          'Menú del restaurante',
                              ),
                              trailing: Text(
                                AppCurrency.format(
                                  product.price,
                                  code: product.currencyCode,
                                ),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              onTap: product.hasVariants
                                  ? null
                                  : product.inventoryTracked &&
                                        product.availableStock <= 0
                                  ? null
                                  : () => Navigator.pop(context, product),
                            ),
                            if (product.hasVariants)
                              for (final variant in variants)
                                ListTile(
                                  dense: true,
                                  contentPadding: const EdgeInsets.only(
                                    left: 64,
                                    right: 16,
                                  ),
                                  title: Text(
                                    variant.label.isEmpty
                                        ? 'Presentación'
                                        : variant.label,
                                  ),
                                  subtitle: Text(
                                    '${variant.stock} ${variant.unitLabel} disponibles',
                                  ),
                                  trailing: Text(
                                    AppCurrency.format(
                                      variant.price,
                                      code: product.currencyCode,
                                    ),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  enabled: variant.stock > 0,
                                  onTap: variant.stock > 0
                                      ? () => Navigator.pop(
                                          context,
                                          product.forVariant(variant),
                                        )
                                      : null,
                                ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _OrderLineTile extends StatelessWidget {
  final TableOrderLine line;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;

  const _OrderLineTile({
    required this.line,
    required this.onDecrease,
    required this.onIncrease,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(11),
          ),
          child: const Icon(Icons.restaurant_menu_rounded, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                line.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                '${AppCurrency.format(line.unitPrice, code: line.currencyCode)} · '
                'Total ${AppCurrency.format(line.total, code: line.currencyCode)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: onDecrease,
          icon: const Icon(Icons.remove_circle_outline_rounded, size: 19),
        ),
        Text(
          NumberFormat('#,##0.##', 'es').format(line.quantity),
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: onIncrease,
          icon: const Icon(Icons.add_circle_outline_rounded, size: 19),
        ),
      ],
    ),
  );
}

class _EmptyTables extends StatelessWidget {
  final bool hasTables;
  final VoidCallback onCreate;

  const _EmptyTables({required this.hasTables, required this.onCreate});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 18),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
    ),
    child: Column(
      children: [
        const Icon(
          Icons.table_restaurant_outlined,
          size: 40,
          color: Color(0xFF7C8795),
        ),
        const SizedBox(height: 10),
        Text(
          hasTables
              ? 'No hay mesas con este filtro.'
              : 'Configura tu primera mesa',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 5),
        Text(
          hasTables
              ? 'Prueba otra opción para ver las mesas.'
              : 'Define el nombre y la capacidad del salón.',
          textAlign: TextAlign.center,
        ),
        if (!hasTables) ...[
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: onCreate,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Crear mesa'),
          ),
        ],
      ],
    ),
  );
}

class _EmptyOrder extends StatelessWidget {
  const _EmptyOrder();

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 14),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(14),
    ),
    child: const Column(
      children: [
        Icon(Icons.dining_outlined, size: 28, color: Color(0xFF748194)),
        SizedBox(height: 7),
        Text(
          'Todavía no hay productos en esta cuenta.',
          textAlign: TextAlign.center,
        ),
      ],
    ),
  );
}

class _NoReservations extends StatelessWidget {
  const _NoReservations();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
    ),
    child: const Row(
      children: [
        Icon(Icons.event_note_rounded, color: Color(0xFF748194)),
        SizedBox(width: 12),
        Expanded(
          child: Text('No hay reservas activas para hoy o los próximos días.'),
        ),
      ],
    ),
  );
}

class _LoadFailure extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _LoadFailure({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_rounded, size: 42),
          const SizedBox(height: 10),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Reintentar'),
          ),
        ],
      ),
    ),
  );
}
