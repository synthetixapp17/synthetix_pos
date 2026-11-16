import 'dart:convert';
import 'dart:typed_data';

import '../../../core/data/hive_database.dart';
import '../../../core/data/models/app_settings.dart';
import '../../../core/utils/product_categories.dart';
import '../../credit/data/credit_repository.dart';
import 'csv_backup_importer.dart';

class JsonBackupFile {
  final String name;
  final Uint8List bytes;

  const JsonBackupFile({required this.name, required this.bytes});
}

class JsonBackupExporter {
  JsonBackupFile createBackup(CsvBackupScope scope) {
    final stamp = _timestamp();
    final data = _dataFor(scope);
    final envelope = {
      'format': 'synthetix_pos_backup',
      'version': 1,
      'scope': scope.name,
      'data': data,
    };
    return JsonBackupFile(
      name: 'respaldo_${_scopeFileName(scope)}_$stamp.json',
      bytes: Uint8List.fromList(
        utf8.encode(const JsonEncoder.withIndent('  ').convert(envelope)),
      ),
    );
  }

  JsonBackupFile createCompleteBackup() => createBackup(CsvBackupScope.all);

  Map<String, Object?> _dataFor(CsvBackupScope scope) {
    final products = [
      for (final product in HiveDatabase.productBox.values)
        {
          'id': product.id,
          'name': product.name,
          'category': product.category,
          'description': product.description,
          'barcode': product.barcode,
          'price': product.price,
          'currencyCode': product.currencyCode,
          'stock': product.stock,
          'unitLabel': product.unitLabel,
          'imageData': product.imageData,
          'variants': product.variants
              .map((variant) => variant.toJson())
              .toList(),
        },
    ];
    final categories = [
      for (final category in ProductCategories.load())
        {'name': category.name, 'icon': category.iconCodePoint},
    ];
    final customers = [
      for (final customer in HiveDatabase.customerBox.values)
        {
          'id': customer.id,
          'name': customer.name,
          'identityNumber': customer.identityNumber,
          'phone': customer.phone,
          'email': customer.email,
          'address': customer.address,
        },
    ];
    final sales = [
      for (final model in HiveDatabase.salesBox.values)
        () {
          final sale = model.toEntity();
          return {
            'id': sale.id,
            'soldAt': sale.soldAt.toIso8601String(),
            'total': sale.total,
            'totalInCurrency': sale.totalInCurrency,
            'exchangeRate': sale.exchangeRate,
            'customerId': sale.customerId,
            'customerName': sale.customerName,
            'currencyCode': sale.currencyCode,
            'paymentMethod': sale.paymentMethod,
            'amountTendered': sale.amountTendered,
            'changeAmount': sale.changeAmount,
            'lines': sale.lines.map((line) => line.toJson()).toList(),
          };
        }(),
    ];
    final credits = [
      for (final credit in CreditRepository.getAll()) credit.toJson(),
    ];
    final shop = HiveDatabase.shopBox.values.firstOrNull;
    final shopData = shop == null
        ? null
        : {
            'name': shop.name,
            'addressLine1': shop.addressLine1,
            'addressLine2': shop.addressLine2,
            'phoneNumber': shop.phoneNumber,
            'rif': shop.rif,
            'upiId': shop.upiId,
            'footerText': shop.footerText,
            'logoData': shop.logoData,
          };
    final settings = <String, Object?>{};
    for (final key in HiveDatabase.settingsBox.keys) {
      final value = HiveDatabase.settingsBox.get(key);
      settings[key.toString()] = value is AppSettings
          ? {
              'currencies': [
                for (final currency in value.currencies)
                  {
                    'code': currency.code,
                    'symbol': currency.symbol,
                    'isBase': currency.isBase,
                    'rate': currency.rate,
                  },
              ],
            }
          : value;
    }

    return switch (scope) {
      CsvBackupScope.all => {
        'products': products,
        'categories': categories,
        'customers': customers,
        'sales': sales,
        'credits': credits,
        'shop': shopData,
        'settings': settings,
      },
      CsvBackupScope.products => {'products': products},
      CsvBackupScope.categories => {'categories': categories},
      CsvBackupScope.customers => {'customers': customers},
      CsvBackupScope.sales => {'sales': sales},
      CsvBackupScope.credits => {'credits': credits},
      CsvBackupScope.configuration => {'shop': shopData, 'settings': settings},
    };
  }

  String _timestamp() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}_'
        '${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}'
        '${now.second.toString().padLeft(2, '0')}';
  }

  String _scopeFileName(CsvBackupScope scope) => switch (scope) {
    CsvBackupScope.all => 'completo',
    CsvBackupScope.products => 'productos',
    CsvBackupScope.categories => 'categorias',
    CsvBackupScope.customers => 'clientes',
    CsvBackupScope.sales => 'ventas',
    CsvBackupScope.credits => 'creditos',
    CsvBackupScope.configuration => 'tienda_configuracion',
  };
}
