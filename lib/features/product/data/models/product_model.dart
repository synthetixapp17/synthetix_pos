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
  final int stock;
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
       );

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
    );
  }

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
    );
  }
}
