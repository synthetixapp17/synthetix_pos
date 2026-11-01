import 'dart:convert';

import 'package:flutter/material.dart';

import '../data/hive_database.dart';

class ProductCategory {
  final String name;
  final int iconCodePoint;

  const ProductCategory({required this.name, required this.iconCodePoint});

  IconData get icon => ProductCategories.iconFor(iconCodePoint);
}

class ProductCategories {
  static const _storageKey = 'product_categories';
  static const availableIcons = [
    Icons.category_outlined,
    Icons.restaurant_outlined,
    Icons.local_cafe_outlined,
    Icons.local_drink_outlined,
    Icons.shopping_bag_outlined,
    Icons.checkroom_outlined,
    Icons.watch_outlined,
    Icons.brush_outlined,
    Icons.spa_outlined,
    Icons.devices_outlined,
    Icons.toys_outlined,
    Icons.pets_outlined,
    Icons.sports_soccer_outlined,
    Icons.menu_book_outlined,
    Icons.home_outlined,
    Icons.medical_services_outlined,
    Icons.build_outlined,
    Icons.directions_car_outlined,
    Icons.music_note_outlined,
    Icons.sports_basketball_outlined,
  ];

  static IconData iconFor(int codePoint) => availableIcons.firstWhere(
    (icon) => icon.codePoint == codePoint,
    orElse: () => Icons.category_outlined,
  );

  static List<ProductCategory> load() {
    final stored = HiveDatabase.settingsBox.get(_storageKey);
    final categoriesByName = <String, ProductCategory>{};

    void addCategory(String name, {int? iconCodePoint}) {
      final normalized = name.trim();
      if (normalized.isEmpty) return;
      final key = normalized.toLowerCase();
      final existing = categoriesByName[key];
      categoriesByName[key] = ProductCategory(
        name: existing?.name ?? normalized,
        iconCodePoint:
            iconCodePoint ??
            existing?.iconCodePoint ??
            Icons.category_outlined.codePoint,
      );
    }

    if (stored is String) {
      final decoded = jsonDecode(stored);
      if (decoded is List) {
        for (final value in decoded) {
          if (value is Map<String, dynamic> && value['name'] is String) {
            addCategory(
              value['name'] as String,
              iconCodePoint: value['icon'] is int ? value['icon'] as int : null,
            );
          } else if (value is String) {
            addCategory(value);
          }
        }
      }
    } else if (stored is Iterable) {
      for (final value in stored) {
        if (value is String) addCategory(value);
      }
    }

    for (final product in HiveDatabase.productBox.values) {
      addCategory(product.category);
    }

    return categoriesByName.values.toList()..sort(
      (first, second) =>
          first.name.toLowerCase().compareTo(second.name.toLowerCase()),
    );
  }

  static Future<void> _save(Iterable<ProductCategory> categories) =>
      HiveDatabase.settingsBox.put(
        _storageKey,
        jsonEncode([
          for (final category in categories)
            {'name': category.name, 'icon': category.iconCodePoint},
        ]),
      );

  static Future<bool> add(String name, {required int iconCodePoint}) async {
    final normalized = name.trim();
    if (normalized.isEmpty) return false;

    final categories = load();
    if (categories.any(
      (category) => category.name.toLowerCase() == normalized.toLowerCase(),
    )) {
      return false;
    }

    categories.add(
      ProductCategory(name: normalized, iconCodePoint: iconCodePoint),
    );
    categories.sort(
      (first, second) =>
          first.name.toLowerCase().compareTo(second.name.toLowerCase()),
    );
    await _save(categories);
    return true;
  }

  static Future<void> updateIcon(String name, int iconCodePoint) async {
    final categories = load();
    final index = categories.indexWhere(
      (category) => category.name.toLowerCase() == name.toLowerCase(),
    );
    if (index == -1) return;

    categories[index] = ProductCategory(
      name: categories[index].name,
      iconCodePoint: iconCodePoint,
    );
    await _save(categories);
  }

  static Future<bool> remove(String name) async {
    final isInUse = HiveDatabase.productBox.values.any(
      (product) => product.category.trim().toLowerCase() == name.toLowerCase(),
    );
    if (isInUse) return false;

    final categories = load()
      ..removeWhere(
        (category) => category.name.toLowerCase() == name.toLowerCase(),
      );
    await _save(categories);
    return true;
  }
}
