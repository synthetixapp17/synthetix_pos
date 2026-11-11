import '../../../../core/data/hive_database.dart';
import '../domain/entities/restaurant_menu.dart';

class RestaurantMenuRepository {
  static const storageKey = 'restaurant_menu_v1';

  RestaurantMenuState load() {
    final stored = HiveDatabase.settingsBox.get(storageKey);
    if (stored == null) return const RestaurantMenuState();
    if (stored is! Map) {
      throw const FormatException('Los datos del menú no son válidos.');
    }
    return RestaurantMenuState.fromMap(stored);
  }

  Future<void> save(RestaurantMenuState state) async {
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
    }
    await HiveDatabase.settingsBox.put(storageKey, state.toMap());
  }
}
