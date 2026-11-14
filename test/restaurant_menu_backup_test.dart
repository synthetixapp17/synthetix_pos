import 'dart:typed_data';

import 'package:billing_app/features/restaurant/data/restaurant_menu_backup.dart';
import 'package:billing_app/features/restaurant/domain/entities/restaurant_menu.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('menu backup preserves categories, availability, and photos', () {
    const menu = RestaurantMenuState(
      categories: [
        RestaurantMenuCategory(
          id: 'drinks',
          name: 'Bebidas',
          description: 'Frías y calientes',
        ),
      ],
      products: [
        RestaurantMenuProduct(
          id: 'coffee',
          categoryId: 'drinks',
          name: 'Café',
          description: 'Con leche',
          price: 2.5,
          currencyCode: 'USD',
          isAvailable: false,
          imageData: 'aW1hZ2U=',
        ),
      ],
    );

    final restored = RestaurantMenuBackup().decode(
      RestaurantMenuBackup().encode(menu),
    );

    expect(restored.categories.single.description, 'Frías y calientes');
    expect(restored.products.single.isAvailable, isFalse);
    expect(restored.products.single.imageData, 'aW1hZ2U=');
  });

  test('rejects files that are not restaurant menu backups', () {
    expect(
      () => RestaurantMenuBackup().decode(
        Uint8List.fromList('{"format":"other"}'.codeUnits),
      ),
      throwsFormatException,
    );
  });
}
