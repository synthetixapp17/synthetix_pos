class RestaurantMenuState {
  final List<RestaurantMenuCategory> categories;
  final List<RestaurantMenuProduct> products;

  const RestaurantMenuState({
    this.categories = const [],
    this.products = const [],
  });

  factory RestaurantMenuState.fromMap(Map<dynamic, dynamic> map) {
    final categories = map['categories'];
    final products = map['products'];
    if (categories is! List || products is! List) {
      throw const FormatException('El menú del restaurante no es válido.');
    }
    return RestaurantMenuState(
      categories: categories
          .map((item) => RestaurantMenuCategory.fromMap(item as Map))
          .toList(),
      products: products
          .map((item) => RestaurantMenuProduct.fromMap(item as Map))
          .toList(),
    );
  }

  Map<String, Object> toMap() => {
    'categories': categories.map((item) => item.toMap()).toList(),
    'products': products.map((item) => item.toMap()).toList(),
  };
}

class RestaurantMenuCategory {
  final String id;
  final String name;
  final String description;

  const RestaurantMenuCategory({
    required this.id,
    required this.name,
    this.description = '',
  });

  Map<String, Object> toMap() => {
    'id': id,
    'name': name,
    'description': description,
  };

  factory RestaurantMenuCategory.fromMap(Map map) {
    final id = map['id'];
    final name = map['name'];
    final description = map['description'] ?? '';
    if (id is! String ||
        id.isEmpty ||
        name is! String ||
        name.trim().isEmpty ||
        description is! String) {
      throw const FormatException('Una categoría del menú no es válida.');
    }
    return RestaurantMenuCategory(id: id, name: name, description: description);
  }
}

class RestaurantMenuProduct {
  final String id;
  final String categoryId;
  final String name;
  final String description;
  final double price;
  final String currencyCode;
  final bool isAvailable;

  const RestaurantMenuProduct({
    required this.id,
    required this.categoryId,
    required this.name,
    this.description = '',
    required this.price,
    required this.currencyCode,
    this.isAvailable = true,
  });

  RestaurantMenuProduct copyWith({
    String? categoryId,
    String? name,
    String? description,
    double? price,
    String? currencyCode,
    bool? isAvailable,
  }) => RestaurantMenuProduct(
    id: id,
    categoryId: categoryId ?? this.categoryId,
    name: name ?? this.name,
    description: description ?? this.description,
    price: price ?? this.price,
    currencyCode: currencyCode ?? this.currencyCode,
    isAvailable: isAvailable ?? this.isAvailable,
  );

  Map<String, Object> toMap() => {
    'id': id,
    'categoryId': categoryId,
    'name': name,
    'description': description,
    'price': price,
    'currencyCode': currencyCode,
    'isAvailable': isAvailable,
  };

  factory RestaurantMenuProduct.fromMap(Map map) {
    final id = map['id'];
    final categoryId = map['categoryId'];
    final name = map['name'];
    final description = map['description'] ?? '';
    final price = map['price'];
    final currencyCode = map['currencyCode'] ?? 'USD';
    final isAvailable = map['isAvailable'] ?? true;
    if (id is! String ||
        id.isEmpty ||
        categoryId is! String ||
        categoryId.isEmpty ||
        name is! String ||
        name.trim().isEmpty ||
        description is! String ||
        price is! num ||
        !price.toDouble().isFinite ||
        price < 0 ||
        currencyCode is! String ||
        currencyCode.isEmpty ||
        isAvailable is! bool) {
      throw const FormatException('Un producto del menú no es válido.');
    }
    return RestaurantMenuProduct(
      id: id,
      categoryId: categoryId,
      name: name,
      description: description,
      price: price.toDouble(),
      currencyCode: currencyCode,
      isAvailable: isAvailable,
    );
  }
}
