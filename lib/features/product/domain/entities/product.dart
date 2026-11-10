import 'package:equatable/equatable.dart';

class ProductVariant extends Equatable {
  final String id;
  final Map<String, String> attributes;
  final double price;
  final double stock;
  final String barcode;
  final String unitLabel;

  const ProductVariant({
    required this.id,
    required this.attributes,
    required this.price,
    required this.stock,
    this.barcode = '',
    this.unitLabel = 'ud.',
  });

  String get label => attributes.entries
      .map((entry) => '${entry.key}: ${entry.value}')
      .join(' · ');

  Map<String, Object> toJson() => {
    'id': id,
    'attributes': attributes,
    'price': price,
    'stock': stock,
    'barcode': barcode,
    'unitLabel': unitLabel,
  };

  factory ProductVariant.fromJson(Map<String, dynamic> json) => ProductVariant(
    id: json['id'] as String,
    attributes: (json['attributes'] as Map<String, dynamic>? ?? {}).map(
      (key, value) => MapEntry(key, value.toString()),
    ),
    price: (json['price'] as num).toDouble(),
    stock: (json['stock'] as num).toDouble(),
    barcode: json['barcode'] as String? ?? '',
    unitLabel: json['unitLabel'] as String? ?? 'ud.',
  );

  @override
  List<Object?> get props => [id, attributes, price, stock, barcode, unitLabel];
}

class Product extends Equatable {
  final String
  id; // Using barcode as ID usually, but keeping separate ID is safer
  final String name;
  final String barcode;
  final double price;
  final double stock;
  final String description;
  final String? imageData;
  final String currencyCode;
  final String category;
  final List<ProductVariant> variants;
  final String? selectedVariantId;

  const Product({
    required this.id,
    required this.name,
    required this.barcode,
    required this.price,
    this.stock = 0,
    this.description = '',
    this.imageData,
    this.currencyCode = 'USD',
    this.category = '',
    this.variants = const [],
    this.selectedVariantId,
  });

  ProductVariant? get selectedVariant {
    final id = selectedVariantId;
    if (id == null) return null;
    for (final variant in variants) {
      if (variant.id == id) return variant;
    }
    return null;
  }

  bool get hasVariants => variants.isNotEmpty;
  double get availableStock => selectedVariant?.stock ?? stock;
  double get salePrice => selectedVariant?.price ?? price;
  String get saleBarcode => selectedVariant?.barcode.isNotEmpty == true
      ? selectedVariant!.barcode
      : barcode;
  String get cartKey =>
      selectedVariantId == null ? id : '$id:$selectedVariantId';
  String get variationLabel => selectedVariant?.label ?? '';

  Product forVariant(ProductVariant variant) => Product(
    id: id,
    name: name,
    barcode: variant.barcode.isNotEmpty ? variant.barcode : barcode,
    price: variant.price,
    stock: variant.stock,
    description: description,
    imageData: imageData,
    currencyCode: currencyCode,
    category: category,
    variants: variants,
    selectedVariantId: variant.id,
  );

  @override
  List<Object?> get props => [
    id,
    name,
    barcode,
    price,
    stock,
    description,
    imageData,
    currencyCode,
    category,
    variants,
    selectedVariantId,
  ];
}
