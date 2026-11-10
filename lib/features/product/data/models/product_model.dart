import 'dart:convert';

import 'package:hive/hive.dart';

import '../../domain/entities/product.dart';

part 'product_model.g.dart'; // Hive generator

@HiveType(typeId: 0)
class ProductModel extends Product {
  @override
  @HiveField(0)
  final String id;
  @override
  @HiveField(1)
  final String name;
  @override
  @HiveField(2)
  final String barcode;
  @override
  @HiveField(3)
  final double price;
  @override
  @HiveField(4)
  final double stock;
  @HiveField(5, defaultValue: '')
  @override
  final String description;
  @HiveField(6)
  @override
  final String? imageData;
  @HiveField(7, defaultValue: 'USD')
  @override
  final String currencyCode;
  @HiveField(8, defaultValue: '')
  @override
  final String category;
  @HiveField(9, defaultValue: '[]')
  final String variantsJson;
  @HiveField(10, defaultValue: 'ud.')
  @override
  final String unitLabel;

  const ProductModel({
    required this.id,
    required this.name,
    required this.barcode,
    required this.price,
    required this.stock,
    this.description = '',
    this.imageData,
    this.currencyCode = 'USD',
    this.category = '',
    this.variantsJson = '[]',
    this.unitLabel = 'ud.',
    List<ProductVariant> variants = const [],
  }) : super(
         id: id,
         name: name,
         barcode: barcode,
         price: price,
         stock: stock,
         description: description,
         imageData: imageData,
         currencyCode: currencyCode,
         category: category,
         unitLabel: unitLabel,
         variants: variants,
       );

  ProductModel copyWith({
    String? id,
    String? name,
    String? barcode,
    double? price,
    double? stock,
    String? description,
    String? imageData,
    String? currencyCode,
    String? category,
    String? unitLabel,
    List<ProductVariant>? variants,
  }) => ProductModel(
    id: id ?? this.id,
    name: name ?? this.name,
    barcode: barcode ?? this.barcode,
    price: price ?? this.price,
    stock: stock ?? this.stock,
    description: description ?? this.description,
    imageData: imageData ?? this.imageData,
    currencyCode: currencyCode ?? this.currencyCode,
    category: category ?? this.category,
    unitLabel: unitLabel ?? this.unitLabel,
    variantsJson: variants == null
        ? variantsJson
        : jsonEncode(variants.map((variant) => variant.toJson()).toList()),
    variants: variants ?? this.variants,
  );

  @override
  List<ProductVariant> get variants {
    final decoded = decodeProductVariants(variantsJson);
    return decoded.isEmpty ? super.variants : decoded;
  }

  static List<ProductVariant> decodeVariants(String source) =>
      decodeProductVariants(source);

  factory ProductModel.fromEntity(Product product) {
    return ProductModel(
      id: product.id,
      name: product.name,
      barcode: product.barcode,
      price: product.price,
      stock: product.stock,
      description: product.description,
      imageData: product.imageData,
      currencyCode: product.currencyCode,
      category: product.category,
      unitLabel: product.unitLabel,
      variantsJson: jsonEncode(
        product.variants.map((variant) => variant.toJson()).toList(),
      ),
      variants: product.variants,
    );
  }

  static List<ProductVariant> decodeProductVariants(String source) =>
      (jsonDecode(source) as List<dynamic>)
          .map((item) => ProductVariant.fromJson(item as Map<String, dynamic>))
          .toList();

  Product toEntity() {
    return Product(
      id: id,
      name: name,
      barcode: barcode,
      price: price,
      stock: stock,
      description: description,
      imageData: imageData,
      currencyCode: currencyCode,
      category: category,
      unitLabel: unitLabel,
      variants: variants,
    );
  }
}
