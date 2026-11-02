import 'dart:convert';
import 'dart:io';

import 'package:billing_app/core/data/hive_database.dart';
import 'package:billing_app/core/utils/product_categories.dart';
import 'package:billing_app/features/product/data/models/product_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory directory;

  setUpAll(() {
    Hive.registerAdapter(ProductModelAdapter());
  });

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('product-categories-');
    Hive.init(directory.path);
    await Hive.openBox<ProductModel>(HiveDatabase.productBoxName);
    await Hive.openBox(HiveDatabase.settingsBoxName);
  });

  tearDown(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  test('renaming a category updates its products and saved icon', () async {
    await HiveDatabase.settingsBox.put(
      'product_categories',
      jsonEncode([
        {'name': 'Bebidas', 'icon': Icons.local_drink_outlined.codePoint},
      ]),
    );
    await HiveDatabase.productBox.put(
      'product-1',
      const ProductModel(
        id: 'product-1',
        name: 'Agua',
        barcode: '123',
        price: 2,
        stock: 5,
        category: 'Bebidas',
      ),
    );

    final renamed = await ProductCategories.rename(
      'Bebidas',
      'Bebidas y alimentos',
      iconCodePoint: Icons.local_cafe_outlined.codePoint,
    );

    expect(renamed, isTrue);
    expect(
      HiveDatabase.productBox.get('product-1')?.category,
      'Bebidas y alimentos',
    );
    expect(ProductCategories.load().single.name, 'Bebidas y alimentos');
    expect(
      ProductCategories.load().single.iconCodePoint,
      Icons.local_cafe_outlined.codePoint,
    );
  });

  test('refuses a duplicate category name without changing products', () async {
    await HiveDatabase.settingsBox.put(
      'product_categories',
      jsonEncode([
        {'name': 'Bebidas', 'icon': Icons.local_drink_outlined.codePoint},
        {'name': 'Comida', 'icon': Icons.restaurant_outlined.codePoint},
      ]),
    );

    final renamed = await ProductCategories.rename(
      'Bebidas',
      ' Comida ',
      iconCodePoint: Icons.local_cafe_outlined.codePoint,
    );

    expect(renamed, isFalse);
    expect(
      ProductCategories.load().map((category) => category.name),
      containsAll(['Bebidas', 'Comida']),
    );
  });
}
