import 'package:equatable/equatable.dart';

class Product extends Equatable {
  final String
  id; // Using barcode as ID usually, but keeping separate ID is safer
  final String name;
  final String barcode;
  final double price;
  final int stock;
  final String description;
  final String? imageData;
  final String currencyCode;
  final String category;

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
  });

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
  ];
}
