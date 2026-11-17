import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/data/hive_database.dart';
import '../../../../core/utils/app_currency.dart';
import '../../../product/data/models/product_model.dart';
import '../../../product/domain/entities/product.dart';
import '../../data/virtual_store_order_storage.dart';
import '../../domain/entities/virtual_store_order.dart';

class VirtualStoreOrdersPage extends StatefulWidget {
  const VirtualStoreOrdersPage({super.key});

  @override
  State<VirtualStoreOrdersPage> createState() => _VirtualStoreOrdersPageState();
}

class _VirtualStoreOrdersPageState extends State<VirtualStoreOrdersPage> {
  final _storage = VirtualStoreOrderStorage();
  late List<VirtualStoreOrder> _orders;
  String? _loadError;
  final Set<String> _delivering = {};

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    try {
      _orders = _storage.load();
      _loadError = null;
    } catch (error) {
      _orders = [];
      _loadError = 'No se pudieron cargar los pedidos: $error';
    }
  }

  Future<void> _createOrder() async {
    final products = HiveDatabase.productBox.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final order = await showDialog<VirtualStoreOrder>(
      context: context,
      builder: (context) => _NewStoreOrderDialog(products: products),
    );
    if (order == null || !mounted) return;
    try {
      final orders = await _storage.add(order);
      if (mounted) setState(() => _orders = orders);
    } catch (error) {
      if (mounted) _showMessage('No se pudo guardar el pedido: $error');
    }
  }

  Future<void> _deliver(VirtualStoreOrder order) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Marcar pedido como entregado'),
        content: Text(
          'Se registrará una venta de ${AppCurrency.format(order.totalUsd, code: 'USD')} '
          'y se descontarán las existencias. Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirmar entrega'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _delivering.add(order.id));
    try {
      final orders = await _storage.markDelivered(order.id);
      if (mounted) {
        setState(() => _orders = orders);
        _showMessage(
          'Pedido entregado: venta registrada y existencias actualizadas.',
        );
      }
    } catch (error) {
      if (mounted) _showMessage(error.toString());
    } finally {
      if (mounted) setState(() => _delivering.remove(order.id));
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final pending = _orders.where((order) => !order.isDelivered).length;
    final delivered = _orders.where((order) => order.isDelivered);
    final revenueUsd = delivered.fold<double>(
      0,
      (total, order) => total + order.totalUsd,
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Pedidos de la tienda')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createOrder,
        icon: const Icon(Icons.add_shopping_cart_outlined),
        label: const Text('Nuevo pedido'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 920),
          child: _loadError != null
              ? Center(child: Text(_loadError!))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _OrderSummaryCard(
                            title: 'Pendientes',
                            value: '$pending',
                            icon: Icons.schedule_outlined,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _OrderSummaryCard(
                            title: 'Ventas entregadas',
                            value: AppCurrency.format(revenueUsd, code: 'USD'),
                            icon: Icons.trending_up_rounded,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    if (_orders.isEmpty)
                      const _EmptyOrders()
                    else
                      for (final order in _orders)
                        _OrderCard(
                          order: order,
                          isDelivering: _delivering.contains(order.id),
                          onDeliver: () => _deliver(order),
                        ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _OrderSummaryCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;

  const _OrderSummaryCard({
    required this.title,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 4),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _EmptyOrders extends StatelessWidget {
  const _EmptyOrders();

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        children: [
          Icon(
            Icons.receipt_long_outlined,
            size: 42,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 12),
          Text(
            'Todavía no hay pedidos',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          const Text(
            'Registra aquí los pedidos acordados por WhatsApp y controla su entrega.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );
}

class _OrderCard extends StatelessWidget {
  final VirtualStoreOrder order;
  final bool isDelivering;
  final VoidCallback onDeliver;

  const _OrderCard({
    required this.order,
    required this.isDelivering,
    required this.onDeliver,
  });

  @override
  Widget build(BuildContext context) {
    final date = DateFormat('dd/MM/yyyy · HH:mm', 'es').format(order.createdAt);
    final colors = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        order.customerName.isEmpty
                            ? 'Pedido ${order.id.substring(0, order.id.length > 8 ? 8 : order.id.length)}'
                            : order.customerName,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        order.customerPhone.isEmpty
                            ? date
                            : '${order.customerPhone} · $date',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                _OrderStatus(isDelivered: order.isDelivered),
              ],
            ),
            const Divider(height: 22),
            for (final line in order.lines)
              Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${line.quantity} ${line.unitLabel} · ${line.productName}'
                        '${line.variantAttributes.isEmpty ? '' : ' (${line.variantAttributes.values.join(' · ')})'}',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      AppCurrency.format(line.totalUsd, code: 'USD'),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            const Divider(height: 20),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Total del pedido',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                Text(
                  AppCurrency.format(order.totalUsd, code: 'USD'),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: colors.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            if (!order.isDelivered) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: isDelivering ? null : onDeliver,
                  icon: isDelivering
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check_circle_outline),
                  label: const Text('Marcar como entregado'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _OrderStatus extends StatelessWidget {
  final bool isDelivered;

  const _OrderStatus({required this.isDelivered});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Chip(
      avatar: Icon(
        isDelivered ? Icons.check_circle : Icons.schedule,
        size: 16,
        color: isDelivered ? colors.primary : colors.tertiary,
      ),
      label: Text(isDelivered ? 'Entregado' : 'Pendiente'),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _NewStoreOrderDialog extends StatefulWidget {
  final List<ProductModel> products;

  const _NewStoreOrderDialog({required this.products});

  @override
  State<_NewStoreOrderDialog> createState() => _NewStoreOrderDialogState();
}

class _NewStoreOrderDialogState extends State<_NewStoreOrderDialog> {
  final _formKey = GlobalKey<FormState>();
  final _customerName = TextEditingController();
  final _customerPhone = TextEditingController();
  final _quantity = TextEditingController(text: '1');
  final _lines = <VirtualStoreOrderLine>[];
  String? _productId;
  String? _variantId;

  ProductModel? get _product {
    for (final product in widget.products) {
      if (product.id == _productId) return product;
    }
    return null;
  }

  ProductVariant? get _variant {
    final product = _product;
    if (product == null || _variantId == null) return null;
    for (final variant in product.variants) {
      if (variant.id == _variantId) return variant;
    }
    return null;
  }

  @override
  void dispose() {
    _customerName.dispose();
    _customerPhone.dispose();
    _quantity.dispose();
    super.dispose();
  }

  void _addLine() {
    final product = _product;
    if (product == null) return;
    final variant = _variant;
    final quantity = double.tryParse(
      _quantity.text.trim().replaceAll(',', '.'),
    );
    if (quantity == null || !quantity.isFinite || quantity <= 0) {
      _showError('Ingresa una cantidad válida.');
      return;
    }
    final stock = variant?.stock ?? product.stock;
    final added = _lines
        .where(
          (line) =>
              line.productId == product.id && line.variantId == variant?.id,
        )
        .fold<double>(0, (total, line) => total + line.quantity);
    if (product.inventoryTracked && quantity + added > stock) {
      _showError('La cantidad supera la existencia disponible ($stock).');
      return;
    }
    double priceUsd;
    try {
      priceUsd = _priceToUsd(
        variant?.price ?? product.price,
        product.currencyCode,
      );
    } on StateError {
      _showError(
        'Configura la tasa de ${product.currencyCode} antes de agregar este producto.',
      );
      return;
    }
    setState(() {
      _lines.add(
        VirtualStoreOrderLine(
          productId: product.id,
          productName: product.name,
          quantity: quantity,
          unitPriceUsd: priceUsd,
          category: product.category,
          barcode: variant?.barcode.isNotEmpty == true
              ? variant!.barcode
              : product.barcode,
          variantId: variant?.id,
          variantAttributes: variant?.attributes ?? const {},
          unitLabel: variant?.unitLabel ?? product.unitLabel,
          inventoryTracked: product.inventoryTracked,
        ),
      );
      _quantity.text = '1';
    });
  }

  void _showError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  double _priceToUsd(double amount, String currencyCode) =>
      currencyCode == AppCurrency.baseCode
      ? amount
      : amount / AppCurrency.rateFor(currencyCode);

  void _save() {
    if (_lines.isEmpty) {
      _showError('Agrega al menos un producto al pedido.');
      return;
    }
    final phone = _customerPhone.text.replaceAll(RegExp(r'\D'), '');
    if (phone.isNotEmpty && !RegExp(r'^\d{8,15}$').hasMatch(phone)) {
      _showError('El teléfono debe incluir entre 8 y 15 dígitos.');
      return;
    }
    Navigator.pop(
      context,
      VirtualStoreOrder(
        id: const Uuid().v4(),
        createdAt: DateTime.now(),
        customerName: _customerName.text.trim(),
        customerPhone: phone,
        lines: List.unmodifiable(_lines),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final product = _product;
    final variants = product?.variants ?? const <ProductVariant>[];
    final total = _lines.fold<double>(0, (sum, line) => sum + line.totalUsd);
    return AlertDialog(
      title: const Text('Registrar pedido'),
      content: SizedBox(
        width: 520,
        child: widget.products.isEmpty
            ? const Text(
                'Agrega productos al inventario antes de registrar pedidos.',
              )
            : Form(
                key: _formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _customerName,
                        decoration: const InputDecoration(
                          labelText: 'Nombre del cliente (opcional)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _customerPhone,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: 'Teléfono (opcional)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        key: ValueKey('product-$_productId'),
                        initialValue: _productId,
                        decoration: const InputDecoration(
                          labelText: 'Producto',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          for (final item in widget.products)
                            DropdownMenuItem(
                              value: item.id,
                              child: Text(
                                item.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (value) => setState(() {
                          _productId = value;
                          final selected = _product;
                          _variantId = selected?.variants.isNotEmpty == true
                              ? selected!.variants.first.id
                              : null;
                        }),
                      ),
                      if (variants.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        DropdownButtonFormField<String>(
                          key: ValueKey('variant-$_productId'),
                          initialValue: _variantId,
                          decoration: const InputDecoration(
                            labelText: 'Variación',
                            border: OutlineInputBorder(),
                          ),
                          items: [
                            for (final variant in variants)
                              DropdownMenuItem(
                                value: variant.id,
                                child: Text(
                                  variant.label.isEmpty
                                      ? 'Variación'
                                      : variant.label,
                                ),
                              ),
                          ],
                          onChanged: (value) =>
                              setState(() => _variantId = value),
                        ),
                      ],
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _quantity,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: InputDecoration(
                                labelText:
                                    'Cantidad${product == null ? '' : ' (${_variant?.unitLabel ?? product.unitLabel})'}',
                                border: const OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          FilledButton.tonalIcon(
                            onPressed: _addLine,
                            icon: const Icon(Icons.add),
                            label: const Text('Agregar'),
                          ),
                        ],
                      ),
                      if (_lines.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        for (var index = 0; index < _lines.length; index++)
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              '${_lines[index].quantity} × ${_lines[index].productName}',
                            ),
                            subtitle: Text(
                              AppCurrency.format(
                                _lines[index].unitPriceUsd,
                                code: 'USD',
                              ),
                            ),
                            trailing: IconButton(
                              tooltip: 'Quitar producto',
                              onPressed: () =>
                                  setState(() => _lines.removeAt(index)),
                              icon: const Icon(Icons.delete_outline),
                            ),
                          ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            'Total: ${AppCurrency.format(total, code: 'USD')}',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                      ],
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
          onPressed: widget.products.isEmpty ? null : _save,
          child: const Text('Guardar pedido'),
        ),
      ],
    );
  }
}
