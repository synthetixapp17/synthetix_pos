import 'dart:convert';

import 'package:hive/hive.dart';

import '../../../../core/data/hive_database.dart';
import '../domain/entities/restaurant_menu.dart';

class RestaurantMenuRepository {
  static const storageKey = 'restaurant_menu_v1';

  RestaurantMenuState load() {
    final stored = HiveDatabase.settingsBox.get(storageKey);
    RestaurantMenuState menu = const RestaurantMenuState();
    if (stored != null) {
      if (stored is! Map) {
        throw const FormatException('Los datos del menú no son válidos.');
      }
      menu = RestaurantMenuState.fromMap(stored);
    }
    return _mergeLocalCatalog(menu);
  }

  RestaurantMenuState _mergeLocalCatalog(RestaurantMenuState menu) {
    if (!Hive.isBoxOpen(HiveDatabase.productBoxName)) return menu;

    final localProducts = HiveDatabase.productBox.values;
    if (menu.products.isNotEmpty || localProducts.isEmpty) return menu;

    final names = <String>[];
    final categories = <RestaurantMenuCategory>[];
    for (final product in localProducts) {
      final name = product.category.trim();
      final normalized = name.toLowerCase();
      if (normalized.isEmpty || names.contains(normalized)) continue;
      names.add(normalized);
      categories.add(
        RestaurantMenuCategory(
          id: 'local-category-${categories.length + 1}',
          name: name,
        ),
      );
    }

    if (categories.isEmpty && menu.categories.isNotEmpty) {
      return menu;
    }

    final categoryByName = <String, RestaurantMenuCategory>{
      for (final category in categories)
        category.name.trim().toLowerCase(): category,
    };
    final products = <RestaurantMenuProduct>[];
    for (final product in localProducts) {
      final categoryName = product.category.trim();
      final category = categoryByName[categoryName.toLowerCase()];
      if (category == null) continue;
      products.add(
        RestaurantMenuProduct(
          id: product.id,
          categoryId: category.id,
          name: product.name.trim(),
          description: product.description.trim(),
          price: product.variants.isNotEmpty
              ? product.variants.first.price
              : product.price,
          currencyCode: product.currencyCode.trim().isEmpty
              ? 'USD'
              : product.currencyCode,
          isAvailable: true,
          imageData: product.imageData,
        ),
      );
    }

    return RestaurantMenuState(
      categories: categories,
      products: products,
    );
  }

  void validate(RestaurantMenuState state) {
    final categoryIds = <String>{};
    final categoryNames = <String>{};
    for (final category in state.categories) {
      final normalizedName = category.name.trim().toLowerCase();
      if (!categoryIds.add(category.id) ||
          normalizedName.isEmpty ||
          !categoryNames.add(normalizedName)) {
        throw const FormatException(
          'Cada categoría debe tener un nombre único.',
        );
      }
    }
    final productIds = <String>{};
    final productNames = <String>{};
    for (final product in state.products) {
      final normalizedName = product.name.trim().toLowerCase();
      if (!productIds.add(product.id) ||
          normalizedName.isEmpty ||
          !productNames.add('${product.categoryId}:$normalizedName') ||
          !categoryIds.contains(product.categoryId) ||
          !product.price.isFinite ||
          product.price < 0 ||
          product.currencyCode.trim().isEmpty) {
        throw const FormatException(
          'Revisa los nombres, precios y categorías de los productos.',
        );
      }
      if (product.imageData != null) {
        try {
          base64Decode(product.imageData!);
        } on FormatException {
          throw const FormatException(
            'Una imagen del menú no tiene un formato válido.',
          );
        }
      }
    }
  }

  Future<void> save(RestaurantMenuState state) async {
    validate(state);
    await HiveDatabase.settingsBox.put(storageKey, state.toMap());
  }
}
