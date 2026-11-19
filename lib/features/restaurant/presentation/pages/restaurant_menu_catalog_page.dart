import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

class RestaurantMenuCatalogPage extends StatefulWidget {
  const RestaurantMenuCatalogPage({super.key});

  @override
  State<RestaurantMenuCatalogPage> createState() =>
      _RestaurantMenuCatalogPageState();
}

class _RestaurantMenuCatalogPageState
    extends State<RestaurantMenuCatalogPage> {
  Map<String, dynamic>? _publication;
  Map<String, int> _cart = {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadMenu();
  }

  Future<void> _loadMenu() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await http.get(Uri.parse('menu.json'));
      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map ||
          decoded['format'] != 'synthetix_restaurant_menu' ||
          decoded['version'] != 1 ||
          decoded['menu'] is! Map) {
        throw const FormatException('Formato de menú no válido.');
      }
      final menu = decoded['menu'] as Map;
      if (menu['categories'] is! List || menu['products'] is! List) {
        throw const FormatException('El menú no contiene categorías o productos.');
      }
      if (!mounted) return;
      setState(() {
        _publication = Map<String, dynamic>.from(decoded);
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudo cargar el menú.';
        _loading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _categories {
    final menu = _publication?['menu'] as Map?;
    final categories = menu?['categories'];
    if (categories is! List) return const [];
    return categories.whereType<Map>().map(Map<String, dynamic>.from).toList();
  }

  List<Map<String, dynamic>> get _products {
    final menu = _publication?['menu'] as Map?;
    final products = menu?['products'];
    if (products is! List) return const [];
    return products.whereType<Map>().map(Map<String, dynamic>.from).toList();
  }

  void _addProduct(Map<String, dynamic> product) {
    final id = product['id']?.toString();
    if (id == null || id.isEmpty) return;
    setState(() => _cart[id] = (_cart[id] ?? 0) + 1);
  }

  double get _cartTotal {
    var total = 0.0;
    for (final entry in _cart.entries) {
      Map<String, dynamic>? product;
      for (final item in _products) {
        if (item['id'] == entry.key) {
          product = item;
          break;
        }
      }
      final price = product?['price'];
      if (price is num) total += price.toDouble() * entry.value;
    }
    return total;
  }

  Future<void> _sendWhatsapp() async {
    if (_cart.isEmpty) return;
    final lines = <String>['Hola, quisiera hacer un pedido:'];
    for (final entry in _cart.entries) {
      Map<String, dynamic>? product;
      for (final item in _products) {
        if (item['id'] == entry.key) {
          product = item;
          break;
        }
      }
      if (product == null) continue;
      lines.add('${entry.value} x ${product['name']}');
    }
    lines.add('');
    lines.add('Total: ${_cartTotal.toStringAsFixed(2)}');

    final whatsapp = _publication?['whatsapp']?.toString() ?? '';
    if (!RegExp(r'^\d{8,15}$').hasMatch(whatsapp)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El restaurante no configuró WhatsApp.')),
      );
      return;
    }
    final uri = Uri.parse(
      'https://wa.me/$whatsapp?text=${Uri.encodeComponent(lines.join('\n'))}',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _loadMenu,
                child: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    final cartCount = _cart.values.fold<int>(0, (sum, quantity) => sum + quantity);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Menú'),
        actions: [
          IconButton(
            tooltip: 'Vaciar carrito',
            onPressed: _cart.isEmpty ? null : () => setState(() => _cart = {}),
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
        children: [
          for (final category in _categories)
            Builder(
              builder: (context) {
                final categoryId = category['id']?.toString();
                final products = _products.where((product) {
                  if (product['isAvailable'] == false) return false;
                  return product['categoryId']?.toString() == categoryId;
                }).toList();
                if (products.isEmpty) return const SizedBox.shrink();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        category['name']?.toString() ?? '',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    ),
                    for (final product in products)
                      Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: ListTile(
                          leading: const Icon(Icons.restaurant_menu_rounded),
                          title: Text(product['name']?.toString() ?? ''),
                          subtitle: Text(
                            '${product['description']?.toString() ?? ''}\n'
                            '${(product['price'] is num) ? (product['price'] as num).toStringAsFixed(2) : ''}',
                          ),
                          trailing: IconButton.filled(
                            tooltip: 'Añadir',
                            onPressed: () => _addProduct(product),
                            icon: const Icon(Icons.add_rounded),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.icon(
            onPressed: cartCount == 0 ? null : _sendWhatsapp,
            icon: const Icon(Icons.chat_rounded),
            label: Text(
              cartCount == 0
                  ? 'Carrito vacío'
                  : 'Pedir por WhatsApp ($cartCount) · ${_cartTotal.toStringAsFixed(2)}',
            ),
          ),
        ),
      ),
    );
  }
}
