import 'package:hive_flutter/hive_flutter.dart';
import '../../features/product/data/models/product_model.dart';
import '../../features/shop/data/models/shop_model.dart';
import '../../features/customer/data/models/customer_model.dart';
import '../../features/reports/data/models/sale_model.dart';

class HiveDatabase {
  static const String productBoxName = 'products';
  static const String shopBoxName = 'shop';
  static const String settingsBoxName = 'settings';
  static const String customerBoxName = 'customers';
  static const String salesBoxName = 'sales';
  static const String creditBoxName = 'credits';

  static Future<void> init() async {
    await Hive.initFlutter();

    // Register Adapters
    Hive.registerAdapter(ProductModelAdapter());
    Hive.registerAdapter(ShopModelAdapter());
    Hive.registerAdapter(CustomerModelAdapter());
    Hive.registerAdapter(SaleModelAdapter());

    // Open Boxes
    await Hive.openBox<ProductModel>(productBoxName);
    await Hive.openBox<ShopModel>(shopBoxName);
    await Hive.openBox<CustomerModel>(customerBoxName);
    await Hive.openBox<SaleModel>(salesBoxName);
    await Hive.openBox<String>(creditBoxName);
    await Hive.openBox(settingsBoxName); // Generic box for simple key-value
  }

  static Box<ProductModel> get productBox =>
      Hive.box<ProductModel>(productBoxName);
  static Box<ShopModel> get shopBox => Hive.box<ShopModel>(shopBoxName);
  static Box<CustomerModel> get customerBox =>
      Hive.box<CustomerModel>(customerBoxName);
  static Box<SaleModel> get salesBox => Hive.box<SaleModel>(salesBoxName);
  static Box<String> get creditBox => Hive.box<String>(creditBoxName);
  static Box get settingsBox => Hive.box(settingsBoxName);
}
