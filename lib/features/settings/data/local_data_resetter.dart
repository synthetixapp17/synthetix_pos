import '../../../core/data/hive_database.dart';

class LocalDataResetter {
  Future<void> reset() async {
    final productsBox = HiveDatabase.productBox;
    final shopBox = HiveDatabase.shopBox;
    final customersBox = HiveDatabase.customerBox;
    final salesBox = HiveDatabase.salesBox;
    final creditsBox = HiveDatabase.creditBox;
    final settingsBox = HiveDatabase.settingsBox;
    final productsBefore = productsBox.toMap();
    final shopBefore = shopBox.toMap();
    final customersBefore = customersBox.toMap();
    final salesBefore = salesBox.toMap();
    final creditsBefore = creditsBox.toMap();
    final settingsBefore = settingsBox.toMap();

    try {
      await productsBox.clear();
      await shopBox.clear();
      await customersBox.clear();
      await salesBox.clear();
      await creditsBox.clear();
      await settingsBox.clear();
    } catch (error, stackTrace) {
      try {
        await productsBox.clear();
        await productsBox.putAll(productsBefore);
        await shopBox.clear();
        await shopBox.putAll(shopBefore);
        await customersBox.clear();
        await customersBox.putAll(customersBefore);
        await salesBox.clear();
        await salesBox.putAll(salesBefore);
        await creditsBox.clear();
        await creditsBox.putAll(creditsBefore);
        await settingsBox.clear();
        await settingsBox.putAll(settingsBefore);
      } catch (rollbackError) {
        throw StateError(
          'Falló el borrado ($error) y también la recuperación de los datos anteriores ($rollbackError).',
        );
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }
}
