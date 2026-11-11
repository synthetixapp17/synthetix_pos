import 'dart:io';

import 'package:billing_app/core/data/hive_database.dart';
import 'package:billing_app/features/restaurant/data/restaurant_menu_repository.dart';
import 'package:billing_app/features/restaurant/domain/entities/restaurant_menu.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('restaurant-menu-test-');
    Hive.init(directory.path);
    await Hive.openBox(HiveDatabase.settingsBoxName);
  });

  tearDown(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  test('persists restaurant categories and products independently', () async {
    final repository = RestaurantMenuRepository();
    const menu = RestaurantMenuState(
      categories: [RestaurantMenuCategory(id: 'drinks', name: 'Bebidas')],
      products: [
        RestaurantMenuProduct(
          id: 'coffee',
          categoryId: 'drinks',
          name: 'Café',
          price: 2.5,
          currencyCode: 'USD',
        ),
      ],
    );

    await repository.save(menu);
    final loaded = repository.load();

    expect(loaded.categories.single.name, 'Bebidas');
    expect(loaded.products.single.name, 'Café');
    expect(loaded.products.single.price, 2.5);
  });

  test('rejects products assigned to categories that do not exist', () async {
    final repository = RestaurantMenuRepository();
    const menu = RestaurantMenuState(
      products: [
        RestaurantMenuProduct(
          id: 'coffee',
          categoryId: 'missing',
          name: 'Café',
          price: 2.5,
          currencyCode: 'USD',
        ),
      ],
    );

    expect(repository.save(menu), throwsFormatException);
  });

  test('rejects duplicate category names', () async {
    final repository = RestaurantMenuRepository();
    const menu = RestaurantMenuState(
      categories: [
        RestaurantMenuCategory(id: 'hot', name: 'Bebidas'),
        RestaurantMenuCategory(id: 'cold', name: ' bebidas '),
      ],
    );

    expect(repository.save(menu), throwsFormatException);
  });
}
