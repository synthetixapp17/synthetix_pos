import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:hive/hive.dart';

import '../../../core/data/hive_database.dart';
import '../../../core/data/models/app_settings.dart';
import '../../credit/domain/entities/credit_record.dart';
import '../../customer/data/models/customer_model.dart';
import '../../product/domain/entities/product.dart';
import '../../product/data/models/product_model.dart';
import '../../reports/data/models/sale_model.dart';
import '../../shop/data/models/shop_model.dart';
import '../../shop/data/repositories/shop_repository_impl.dart';

enum CsvBackupScope {
  all,
  products,
  categories,
  customers,
  sales,
  credits,
  configuration,
}

class CsvBackupPlan {
  final CsvBackupScope scope;
  final List<ProductModel> products;
  final List<CustomerModel> customers;
  final List<SaleModel> sales;
  final List<CreditRecord> credits;
  final String categoriesJson;
  final ShopModel? shop;
  final Map<String, Object?> settings;

  const CsvBackupPlan({
    required this.scope,
    required this.products,
    required this.customers,
    required this.sales,
    required this.credits,
    required this.categoriesJson,
    required this.shop,
    required this.settings,
  });
}

class CsvBackupSummary {
  final int products;
  final int categories;
  final int customers;
  final int sales;
  final int credits;

  const CsvBackupSummary({
    required this.products,
    required this.categories,
    required this.customers,
    required this.sales,
    required this.credits,
  });
}

class CsvBackupImporter {
  static const _maxPackageBytes = 100 * 1024 * 1024;
  static const _maxExpandedBytes = 300 * 1024 * 1024;

  CsvBackupPlan parsePackage(Uint8List bytes) {
    if (bytes.isEmpty || bytes.length > _maxPackageBytes) {
      throw const FormatException('El paquete está vacío o supera 100 MB.');
    }

    final archive = ZipDecoder().decodeBytes(bytes, verify: true);
    final csvFiles = <String, Uint8List>{};
    var expandedBytes = 0;
    for (final entry in archive.files.where((entry) => entry.isFile)) {
      final name = entry.name.split('/').last.toLowerCase();
      if (!name.endsWith('.csv')) continue;
      final content = entry.readBytes();
      if (content == null) {
        throw FormatException('No se pudo leer el archivo ${entry.name}.');
      }
      expandedBytes += content.length;
      if (expandedBytes > _maxExpandedBytes) {
        throw const FormatException(
          'El contenido descomprimido del paquete supera 300 MB.',
        );
      }
      final key = _fileType(name);
      if (key == null) {
        throw FormatException('El paquete contiene un CSV desconocido: $name.');
      }
      if (csvFiles.containsKey(key)) {
        throw FormatException('El paquete contiene más de un CSV de $key.');
      }
      csvFiles[key] = content;
    }

    const requiredFiles = [
      'productos',
      'categorias',
      'clientes',
      'ventas',
      'creditos',
      'tienda_configuracion',
    ];
    final missing = requiredFiles.where((name) => !csvFiles.containsKey(name));
    if (missing.isNotEmpty) {
      throw FormatException(
        'Faltan archivos requeridos: ${missing.join(', ')}.',
      );
    }

    final products = _parseProducts(_csv(csvFiles['productos']!));
    final customers = _parseCustomers(_csv(csvFiles['clientes']!));
    final categories = _parseCategories(_csv(csvFiles['categorias']!));
    final sales = _parseSales(_csv(csvFiles['ventas']!));
    final credits = _parseCredits(_csv(csvFiles['creditos']!));
    final configuration = _parseConfiguration(
      _csv(csvFiles['tienda_configuracion']!),
    );

    return CsvBackupPlan(
      scope: CsvBackupScope.all,
      products: products,
      customers: customers,
      sales: sales,
      credits: credits,
      categoriesJson: jsonEncode([
        for (final category in categories)
          {'name': category.$1, 'icon': category.$2},
      ]),
      shop: configuration.$1,
      settings: configuration.$2,
    );
  }

  CsvBackupPlan parseCsvFile(String fileName, Uint8List bytes) {
    if (bytes.isEmpty || bytes.length > _maxPackageBytes) {
      throw const FormatException('El CSV está vacío o supera 100 MB.');
    }

    final rows = _csv(bytes);
    if (rows.isEmpty) throw const FormatException('El CSV está vacío.');
    final fileType =
        _fileType(fileName.toLowerCase()) ?? _identifyCsvType(rows.first);
    if (fileType == null) {
      throw FormatException(
        'No se reconoce el tipo de datos del archivo $fileName.',
      );
    }

    final emptyCategories = jsonEncode(const <Object>[]);
    switch (fileType) {
      case 'productos':
        return CsvBackupPlan(
          scope: CsvBackupScope.products,
          products: _parseProducts(rows),
          customers: const [],
          sales: const [],
          credits: const [],
          categoriesJson: emptyCategories,
          shop: null,
          settings: const {},
        );
      case 'categorias':
        final categories = _parseCategories(rows);
        return CsvBackupPlan(
          scope: CsvBackupScope.categories,
          products: const [],
          customers: const [],
          sales: const [],
          credits: const [],
          categoriesJson: jsonEncode([
            for (final category in categories)
              {'name': category.$1, 'icon': category.$2},
          ]),
          shop: null,
          settings: const {},
        );
      case 'clientes':
        return CsvBackupPlan(
          scope: CsvBackupScope.customers,
          products: const [],
          customers: _parseCustomers(rows),
          sales: const [],
          credits: const [],
          categoriesJson: emptyCategories,
          shop: null,
          settings: const {},
        );
      case 'ventas':
        return CsvBackupPlan(
          scope: CsvBackupScope.sales,
          products: const [],
          customers: const [],
          sales: _parseSales(rows),
          credits: const [],
          categoriesJson: emptyCategories,
          shop: null,
          settings: const {},
        );
      case 'creditos':
        return CsvBackupPlan(
          scope: CsvBackupScope.credits,
          products: const [],
          customers: const [],
          sales: const [],
          credits: _parseCredits(rows),
          categoriesJson: emptyCategories,
          shop: null,
          settings: const {},
        );
      case 'tienda_configuracion':
        final configuration = _parseConfiguration(rows);
        return CsvBackupPlan(
          scope: CsvBackupScope.configuration,
          products: const [],
          customers: const [],
          sales: const [],
          credits: const [],
          categoriesJson: emptyCategories,
          shop: configuration.$1,
          settings: configuration.$2,
        );
      default:
        throw FormatException(
          'No se reconoce el tipo de datos del archivo $fileName.',
        );
    }
  }

  CsvBackupSummary summarize(CsvBackupPlan plan) => CsvBackupSummary(
    products: plan.products.length,
    categories: (jsonDecode(plan.categoriesJson) as List).length,
    customers: plan.customers.length,
    sales: plan.sales.length,
    credits: plan.credits.length,
  );

  Future<void> restore(CsvBackupPlan plan) async {
    final productsBox = HiveDatabase.productBox;
    final customersBox = HiveDatabase.customerBox;
    final salesBox = HiveDatabase.salesBox;
    final creditsBox = HiveDatabase.creditBox;
    final shopBox = HiveDatabase.shopBox;
    final settingsBox = HiveDatabase.settingsBox;
    final productsBefore = productsBox.toMap();
    final customersBefore = customersBox.toMap();
    final salesBefore = salesBox.toMap();
    final creditsBefore = creditsBox.toMap();
    final shopBefore = shopBox.toMap();
    final settingsBefore = settingsBox.toMap();

    try {
      switch (plan.scope) {
        case CsvBackupScope.all:
          await productsBox.clear();
          await productsBox.putAll({
            for (final item in plan.products) item.id: item,
          });
          await customersBox.clear();
          await customersBox.putAll({
            for (final item in plan.customers) item.id: item,
          });
          await salesBox.clear();
          await salesBox.putAll({for (final item in plan.sales) item.id: item});
          await creditsBox.clear();
          await creditsBox.putAll({
            for (final item in plan.credits) item.id: jsonEncode(item.toJson()),
          });
          await _restoreConfiguration(
            shopBox,
            settingsBox,
            plan,
            replaceSettings: true,
            categoriesJson: plan.categoriesJson,
          );
        case CsvBackupScope.products:
          await productsBox.clear();
          await productsBox.putAll({
            for (final item in plan.products) item.id: item,
          });
        case CsvBackupScope.categories:
          await settingsBox.put('product_categories', plan.categoriesJson);
        case CsvBackupScope.customers:
          await customersBox.clear();
          await customersBox.putAll({
            for (final item in plan.customers) item.id: item,
          });
        case CsvBackupScope.sales:
          await salesBox.clear();
          await salesBox.putAll({for (final item in plan.sales) item.id: item});
        case CsvBackupScope.credits:
          await creditsBox.clear();
          await creditsBox.putAll({
            for (final item in plan.credits) item.id: jsonEncode(item.toJson()),
          });
        case CsvBackupScope.configuration:
          await _restoreConfiguration(
            shopBox,
            settingsBox,
            plan,
            replaceSettings: true,
          );
      }
    } catch (error, stackTrace) {
      try {
        await productsBox.clear();
        await productsBox.putAll(productsBefore);
        await customersBox.clear();
        await customersBox.putAll(customersBefore);
        await salesBox.clear();
        await salesBox.putAll(salesBefore);
        await creditsBox.clear();
        await creditsBox.putAll(creditsBefore);
        await shopBox.clear();
        await shopBox.putAll(shopBefore);
        await settingsBox.clear();
        await settingsBox.putAll(settingsBefore);
      } catch (rollbackError) {
        throw StateError(
          'Falló la restauración ($error) y también la recuperación de los datos anteriores ($rollbackError).',
        );
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<void> _restoreConfiguration(
    Box<ShopModel> shopBox,
    Box settingsBox,
    CsvBackupPlan plan, {
    bool replaceSettings = false,
    String? categoriesJson,
  }) async {
    await shopBox.clear();
    final restoredShop = plan.shop;
    if (restoredShop != null) {
      await shopBox.put(ShopRepositoryImpl.shopKey, restoredShop);
    }
    if (replaceSettings) await settingsBox.clear();
    final settings = <String, Object?>{...plan.settings};
    if (categoriesJson != null) {
      settings['product_categories'] = categoriesJson;
    }
    await settingsBox.putAll(settings);
  }

  List<ProductModel> _parseProducts(List<List<String>> rows) {
    final table = _table(rows, 'productos', const [
      'id',
      'nombre',
      'categoría',
      'descripción',
      'código',
      'precio',
      'moneda',
      'existencias',
      'imagen_base64',
    ]);
    final result = <ProductModel>[];
    final ids = <String>{};
    for (final row in table) {
      final id = _required(row, 'id', 'productos');
      if (!ids.add(id)) throw FormatException('ID de producto duplicado: $id.');
      result.add(
        ProductModel(
          id: id,
          name: _required(row, 'nombre', 'productos'),
          category: row['categoría'] ?? '',
          description: row['descripción'] ?? '',
          barcode: row['código'] ?? '',
          price: _double(row, 'precio', 'productos'),
          currencyCode: _required(row, 'moneda', 'productos'),
          stock: _double(row, 'existencias', 'productos'),
          imageData: _optional(row['imagen_base64']),
          variantsJson: _optional(row['variaciones_json']) ?? '[]',
          variants: _parseVariants(row['variaciones_json']),
        ),
      );
    }
    return result;
  }

  List<CustomerModel> _parseCustomers(List<List<String>> rows) {
    final table = _table(rows, 'clientes', const [
      'id',
      'nombre',
      'identificación',
      'teléfono',
      'correo',
      'dirección',
    ]);
    final result = <CustomerModel>[];
    final ids = <String>{};
    for (final row in table) {
      final id = _required(row, 'id', 'clientes');
      if (!ids.add(id)) throw FormatException('ID de cliente duplicado: $id.');
      result.add(
        CustomerModel(
          id: id,
          name: _required(row, 'nombre', 'clientes'),
          identityNumber: row['identificación'] ?? '',
          phone: row['teléfono'] ?? '',
          email: row['correo'] ?? '',
          address: row['dirección'] ?? '',
        ),
      );
    }
    return result;
  }

  List<(String, int)> _parseCategories(List<List<String>> rows) {
    final table = _table(rows, 'categorías', const [
      'nombre',
      'icono_code_point',
      'cantidad_productos',
    ]);
    final result = <(String, int)>[];
    final names = <String>{};
    for (final row in table) {
      final name = _required(row, 'nombre', 'categorías');
      if (!names.add(name.toLowerCase())) {
        throw FormatException('Categoría duplicada: $name.');
      }
      final icon = int.tryParse(
        _required(row, 'icono_code_point', 'categorías'),
      );
      if (icon == null || icon <= 0) {
        throw FormatException('Icono inválido para la categoría $name.');
      }
      _int(row, 'cantidad_productos', 'categorías');
      result.add((name, icon));
    }
    return result;
  }

  List<SaleModel> _parseSales(List<List<String>> rows) {
    final table = _table(rows, 'ventas', const [
      'venta_id',
      'fecha',
      'cliente_id',
      'cliente',
      'total_venta',
      'moneda',
      'producto_id',
      'producto',
      'categoría',
      'codigo_producto',
      'cantidad',
      'precio_unitario',
      'total_linea',
      'forma_pago',
    ]);
    final sales = <String, _SaleRow>{};
    for (final row in table) {
      final id = _required(row, 'venta_id', 'ventas');
      final date = _date(_required(row, 'fecha', 'ventas'), 'ventas');
      final total = _double(row, 'total_venta', 'ventas');
      final totalInCurrency = row['total_en_moneda']?.trim().isNotEmpty == true
          ? _double(row, 'total_en_moneda', 'ventas')
          : total;
      final exchangeRate = row['tasa_cambio']?.trim().isNotEmpty == true
          ? _double(row, 'tasa_cambio', 'ventas')
          : 1.0;
      final currency = _required(row, 'moneda', 'ventas');
      final customerId = _optional(row['cliente_id']);
      final customerName = _optional(row['cliente']);
      final paymentMethod = _optional(row['forma_pago']) ?? 'Efectivo';
      final amountTendered = _optionalDouble(
        row['efectivo_recibido'],
        'efectivo_recibido',
      );
      final changeAmount = _optionalDouble(row['vuelto'], 'vuelto');
      final sale = sales.putIfAbsent(
        id,
        () => _SaleRow(
          id: id,
          date: date,
          total: total,
          totalInCurrency: totalInCurrency,
          exchangeRate: exchangeRate,
          currency: currency,
          customerId: customerId,
          customerName: customerName,
          paymentMethod: paymentMethod,
          amountTendered: amountTendered,
          changeAmount: changeAmount,
        ),
      );
      if (!sale.matches(
        date: date,
        total: total,
        totalInCurrency: totalInCurrency,
        exchangeRate: exchangeRate,
        currency: currency,
        customerId: customerId,
        customerName: customerName,
        paymentMethod: paymentMethod,
        amountTendered: amountTendered,
        changeAmount: changeAmount,
      )) {
        throw FormatException('Datos inconsistentes en la venta $id.');
      }
      final productId = _optional(row['producto_id']);
      if (productId != null) {
        sale.lines.add(
          _SaleLineRow(
            productId: productId,
            productName: _required(row, 'producto', 'ventas'),
            category: row['categoría'] ?? '',
            barcode: row['codigo_producto'] ?? '',
            quantity: _double(row, 'cantidad', 'ventas'),
            unitPrice: _double(row, 'precio_unitario', 'ventas'),
            variantId: _optional(row['variacion_id']),
            variantAttributes: _parseAttributes(row['variaciones_json']),
            unitLabel: _optional(row['unidad']) ?? 'ud.',
          ),
        );
      }
    }
    return [
      for (final sale in sales.values)
        SaleModel(
          id: sale.id,
          soldAt: sale.date,
          total: sale.total,
          totalInCurrency: sale.totalInCurrency,
          exchangeRate: sale.exchangeRate,
          customerId: sale.customerId,
          customerName: sale.customerName,
          currencyCode: sale.currency,
          paymentMethod: sale.paymentMethod,
          amountTendered: sale.amountTendered,
          changeAmount: sale.changeAmount,
          linesJson: jsonEncode([
            for (final line in sale.lines)
              {
                'productId': line.productId,
                'productName': line.productName,
                'category': line.category,
                'barcode': line.barcode,
                'quantity': line.quantity,
                'unitPrice': line.unitPrice,
                'variantId': line.variantId,
                'variantAttributes': line.variantAttributes,
                'unitLabel': line.unitLabel,
              },
          ]),
        ),
    ];
  }

  List<CreditRecord> _parseCredits(List<List<String>> rows) {
    final table = _table(rows, 'créditos', const [
      'credito_id',
      'fecha_registro',
      'fecha_vencimiento',
      'cliente_id',
      'cliente',
      'identificacion_cliente',
      'telefono_cliente',
      'correo_cliente',
      'direccion_cliente',
      'total_compra',
      'monto_compra_sin_interes',
      'abono_inicial',
      'porcentaje_interes',
      'monto_interes',
      'total_abonado',
      'saldo_pendiente',
      'moneda',
      'cantidad_cuotas',
      'dias_entre_cuotas',
      'historial_abonos_json',
      'productos_json',
      'comprobante_pdf_base64',
    ]);
    final result = <CreditRecord>[];
    final ids = <String>{};
    for (final row in table) {
      final id = _required(row, 'credito_id', 'créditos');
      if (!ids.add(id)) throw FormatException('ID de crédito duplicado: $id.');
      final payments = _jsonList(row, 'historial_abonos_json', 'créditos');
      final lines = _jsonList(row, 'productos_json', 'créditos');
      final record = CreditRecord.fromJson({
        'id': id,
        'createdAt': _date(
          _required(row, 'fecha_registro', 'créditos'),
          'créditos',
        ).toIso8601String(),
        'dueDate': _optional(row['fecha_vencimiento']),
        'customerId': _required(row, 'cliente_id', 'créditos'),
        'customerName': _required(row, 'cliente', 'créditos'),
        'customerIdentity': row['identificacion_cliente'] ?? '',
        'customerPhone': row['telefono_cliente'] ?? '',
        'customerEmail': row['correo_cliente'] ?? '',
        'customerAddress': row['direccion_cliente'] ?? '',
        'total': _double(row, 'total_compra', 'créditos'),
        'purchaseAmount': _nullableDouble(row['monto_compra_sin_interes']),
        'initialPayment': _double(row, 'abono_inicial', 'créditos'),
        'interestPercentage': _double(row, 'porcentaje_interes', 'créditos'),
        'interestAmount': _double(row, 'monto_interes', 'créditos'),
        'currencyCode': _required(row, 'moneda', 'créditos'),
        'installmentCount': _nullableInt(row['cantidad_cuotas']),
        'daysBetweenPayments': _nullableInt(row['dias_entre_cuotas']),
        'pdfBase64': row['comprobante_pdf_base64'] ?? '',
        'payments': payments,
        'lines': lines,
      });
      final recordedPaid = _double(row, 'total_abonado', 'créditos');
      final recordedBalance = _double(row, 'saldo_pendiente', 'créditos');
      if ((recordedPaid - record.paidAmount).abs() > 0.01 ||
          (recordedBalance - record.balance).abs() > 0.01) {
        throw FormatException(
          'Abonos o saldo inconsistentes en el crédito $id.',
        );
      }
      result.add(record);
    }
    return result;
  }

  (ShopModel?, Map<String, Object?>) _parseConfiguration(
    List<List<String>> rows,
  ) {
    if (rows.isEmpty || rows.first.length != 2 || rows.first[0] != 'dato') {
      throw const FormatException('El CSV de configuración no es válido.');
    }
    final shopValues = <String, String>{};
    final settings = <String, Object?>{};
    const requiredShopFields = {
      'nombre_tienda',
      'dirección',
      'complemento_dirección',
      'teléfono',
      'identificador_pago',
      'mensaje_ticket',
      'logotipo_base64',
    };
    const shopFields = {...requiredShopFields, 'RIF'};
    for (final row in rows.skip(1)) {
      if (row.length != 2 || row[0].isEmpty) {
        throw const FormatException('Hay una fila inválida en configuración.');
      }
      final key = row[0];
      if (shopFields.contains(key)) {
        shopValues[key] = row[1];
      } else {
        try {
          final decoded = jsonDecode(row[1]);
          settings[key] = key == 'app_settings'
              ? _parseAppSettings(decoded)
              : decoded as Object?;
        } on FormatException catch (error) {
          throw FormatException('Configuración inválida para "$key": $error');
        }
      }
    }
    ShopModel? shop;
    if (shopValues.isNotEmpty) {
      final missing = requiredShopFields.where(
        (field) => !shopValues.containsKey(field),
      );
      if (missing.isNotEmpty) {
        throw FormatException(
          'Faltan datos de la tienda: ${missing.join(', ')}.',
        );
      }
      shop = ShopModel(
        name: shopValues['nombre_tienda']!,
        addressLine1: shopValues['dirección']!,
        addressLine2: shopValues['complemento_dirección']!,
        phoneNumber: shopValues['teléfono']!,
        rif: shopValues['RIF'] ?? '',
        upiId: shopValues['identificador_pago']!,
        footerText: shopValues['mensaje_ticket']!,
        logoData: _optional(shopValues['logotipo_base64']),
      );
    }
    return (shop, settings);
  }

  AppSettings _parseAppSettings(Object? value) {
    if (value is! Map || value['currencies'] is! List) {
      throw const FormatException('La configuración de monedas no es válida.');
    }
    final currencies = <CurrencyConfig>[];
    for (final item in value['currencies'] as List) {
      if (item is! Map ||
          item['code'] is! String ||
          item['symbol'] is! String ||
          item['isBase'] is! bool ||
          item['rate'] is! num) {
        throw const FormatException(
          'Hay una moneda inválida en la configuración.',
        );
      }
      currencies.add(
        CurrencyConfig(
          code: item['code'] as String,
          symbol: item['symbol'] as String,
          isBase: item['isBase'] as bool,
          rate: (item['rate'] as num).toDouble(),
        ),
      );
    }
    if (currencies.isEmpty ||
        currencies.where((currency) => currency.isBase).length != 1 ||
        currencies.any(
          (currency) =>
              !currency.rate.isFinite ||
              currency.rate <= 0 ||
              (currency.isBase && currency.rate != 1),
        ) ||
        currencies.map((currency) => currency.code).toSet().length !=
            currencies.length) {
      throw const FormatException('Las tasas de moneda no son válidas.');
    }
    return AppSettings(currencies: currencies);
  }

  String? _fileType(String name) {
    const types = [
      'tienda_configuracion',
      'productos',
      'categorias',
      'clientes',
      'ventas',
      'creditos',
    ];
    for (final type in types) {
      if (name.startsWith('respaldo_${type}_')) return type;
    }
    return null;
  }

  String? _identifyCsvType(List<String> headers) {
    const requiredHeaders = {
      'productos': [
        'id',
        'nombre',
        'categoría',
        'descripción',
        'código',
        'precio',
        'moneda',
        'existencias',
        'imagen_base64',
      ],
      'categorias': ['nombre', 'icono_code_point', 'cantidad_productos'],
      'clientes': [
        'id',
        'nombre',
        'identificación',
        'teléfono',
        'correo',
        'dirección',
      ],
      'ventas': [
        'venta_id',
        'fecha',
        'cliente_id',
        'cliente',
        'total_venta',
        'moneda',
        'producto_id',
        'producto',
        'categoría',
        'codigo_producto',
        'cantidad',
        'precio_unitario',
        'total_linea',
        'forma_pago',
      ],
      'creditos': [
        'credito_id',
        'fecha_registro',
        'fecha_vencimiento',
        'cliente_id',
        'cliente',
        'identificacion_cliente',
        'telefono_cliente',
        'correo_cliente',
        'direccion_cliente',
        'total_compra',
        'monto_compra_sin_interes',
        'abono_inicial',
        'porcentaje_interes',
        'monto_interes',
        'total_abonado',
        'saldo_pendiente',
        'moneda',
        'cantidad_cuotas',
        'dias_entre_cuotas',
        'historial_abonos_json',
        'productos_json',
        'comprobante_pdf_base64',
      ],
      'tienda_configuracion': ['dato', 'valor'],
    };
    for (final entry in requiredHeaders.entries) {
      if (entry.value.every(headers.contains)) return entry.key;
    }
    return null;
  }

  List<List<String>> _csv(Uint8List bytes) {
    var source = utf8.decode(bytes, allowMalformed: false);
    if (source.startsWith('\uFEFF')) source = source.substring(1);
    final rows = <List<String>>[];
    final row = <String>[];
    final field = StringBuffer();
    var quoted = false;
    var fieldWasQuoted = false;
    for (var index = 0; index < source.length; index++) {
      final character = source[index];
      if (quoted) {
        if (character == '"') {
          if (index + 1 < source.length && source[index + 1] == '"') {
            field.write('"');
            index++;
          } else {
            quoted = false;
          }
        } else {
          field.write(character);
        }
        continue;
      }
      if (character == '"') {
        if (field.isNotEmpty || fieldWasQuoted) {
          throw const FormatException('Comillas inválidas en el CSV.');
        }
        quoted = true;
        fieldWasQuoted = true;
      } else if (character == ',') {
        row.add(field.toString());
        field.clear();
        fieldWasQuoted = false;
      } else if (character == '\r' || character == '\n') {
        row.add(field.toString());
        field.clear();
        fieldWasQuoted = false;
        rows.add(List<String>.of(row));
        row.clear();
        if (character == '\r' &&
            index + 1 < source.length &&
            source[index + 1] == '\n') {
          index++;
        }
      } else {
        if (fieldWasQuoted && character.trim().isNotEmpty) {
          throw const FormatException(
            'Texto después de una celda entre comillas.',
          );
        }
        if (!fieldWasQuoted) field.write(character);
      }
    }
    if (quoted) {
      throw const FormatException('El CSV termina dentro de comillas.');
    }
    if (field.isNotEmpty || row.isNotEmpty || fieldWasQuoted) {
      row.add(field.toString());
      rows.add(List<String>.of(row));
    }
    return rows;
  }

  List<Map<String, String>> _table(
    List<List<String>> rows,
    String label,
    List<String> requiredHeaders,
  ) {
    if (rows.isEmpty) throw FormatException('El CSV de $label está vacío.');
    final headers = rows.first;
    if (headers.isEmpty || headers.toSet().length != headers.length) {
      throw FormatException('Encabezados inválidos en el CSV de $label.');
    }
    final missingHeaders = requiredHeaders.where(
      (header) => !headers.contains(header),
    );
    if (missingHeaders.isNotEmpty) {
      throw FormatException(
        'Faltan columnas en el CSV de $label: ${missingHeaders.join(', ')}.',
      );
    }
    final result = <Map<String, String>>[];
    for (final row in rows.skip(1)) {
      if (row.length != headers.length) {
        throw FormatException('Fila incompleta en el CSV de $label.');
      }
      result.add({
        for (var index = 0; index < headers.length; index++)
          headers[index]: row[index],
      });
    }
    return result;
  }

  String _required(Map<String, String> row, String key, String label) {
    final value = row[key]?.trim();
    if (value == null || value.isEmpty) {
      throw FormatException('Falta "$key" en el CSV de $label.');
    }
    return value;
  }

  String? _optional(String? value) {
    if (value == null || value.isEmpty) return null;
    return value;
  }

  double _double(Map<String, String> row, String key, String label) {
    final value = double.tryParse(
      _required(row, key, label).replaceAll(',', '.'),
    );
    if (value == null || !value.isFinite) {
      throw FormatException('Número inválido "$key" en el CSV de $label.');
    }
    return value;
  }

  List<ProductVariant> _parseVariants(String? source) {
    if (source == null || source.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(source);
      if (decoded is! List) {
        throw const FormatException('Se esperaba una lista.');
      }
      return decoded
          .map(
            (item) =>
                ProductVariant.fromJson((item as Map).cast<String, dynamic>()),
          )
          .toList();
    } on Object catch (error) {
      throw FormatException('JSON de variaciones inválido: $error');
    }
  }

  Map<String, String> _parseAttributes(String? source) {
    if (source == null || source.trim().isEmpty) return const {};
    try {
      final decoded = jsonDecode(source);
      if (decoded is! Map) {
        throw const FormatException('Se esperaba un objeto.');
      }
      return decoded.map(
        (key, value) => MapEntry(key.toString(), value.toString()),
      );
    } on Object catch (error) {
      throw FormatException('Atributos de variación inválidos: $error');
    }
  }

  double _optionalDouble(String? source, String key) {
    if (source == null || source.trim().isEmpty) return 0;
    final value = double.tryParse(source.trim());
    if (value == null || !value.isFinite) {
      throw FormatException('Número inválido "$key" en el CSV de ventas.');
    }
    return value;
  }

  int _int(Map<String, String> row, String key, String label) {
    final value = int.tryParse(_required(row, key, label));
    if (value == null) {
      throw FormatException('Entero inválido "$key" en el CSV de $label.');
    }
    return value;
  }

  double? _nullableDouble(String? value) {
    if (value == null || value.isEmpty) return null;
    final result = double.tryParse(value);
    if (result == null || !result.isFinite) {
      throw const FormatException('Número opcional inválido en créditos.');
    }
    return result;
  }

  int? _nullableInt(String? value) {
    if (value == null || value.isEmpty) return null;
    final result = int.tryParse(value);
    if (result == null) {
      throw const FormatException('Entero opcional inválido en créditos.');
    }
    return result;
  }

  DateTime _date(String value, String label) {
    final result = DateTime.tryParse(value);
    if (result == null) throw FormatException('Fecha inválida en $label.');
    return result;
  }

  List<Map<String, dynamic>> _jsonList(
    Map<String, String> row,
    String key,
    String label,
  ) {
    try {
      final decoded = jsonDecode(_required(row, key, label));
      if (decoded is! List) {
        throw const FormatException('Se esperaba una lista.');
      }
      return decoded.map((value) {
        if (value is! Map) {
          throw const FormatException('Elemento JSON no válido.');
        }
        return value.cast<String, dynamic>();
      }).toList();
    } on FormatException catch (error) {
      throw FormatException('JSON inválido "$key" en $label: $error');
    }
  }
}

class _SaleRow {
  final String id;
  final DateTime date;
  final double total;
  final double totalInCurrency;
  final double exchangeRate;
  final String currency;
  final String? customerId;
  final String? customerName;
  final String paymentMethod;
  final double amountTendered;
  final double changeAmount;
  final List<_SaleLineRow> lines = [];

  _SaleRow({
    required this.id,
    required this.date,
    required this.total,
    required this.totalInCurrency,
    required this.exchangeRate,
    required this.currency,
    required this.customerId,
    required this.customerName,
    required this.paymentMethod,
    required this.amountTendered,
    required this.changeAmount,
  });

  bool matches({
    required DateTime date,
    required double total,
    required double totalInCurrency,
    required double exchangeRate,
    required String currency,
    required String? customerId,
    required String? customerName,
    required String paymentMethod,
    required double amountTendered,
    required double changeAmount,
  }) =>
      this.date == date &&
      this.total == total &&
      this.totalInCurrency == totalInCurrency &&
      this.exchangeRate == exchangeRate &&
      this.currency == currency &&
      this.customerId == customerId &&
      this.customerName == customerName &&
      this.paymentMethod == paymentMethod &&
      this.amountTendered == amountTendered &&
      this.changeAmount == changeAmount;
}

class _SaleLineRow {
  final String productId;
  final String productName;
  final String category;
  final String barcode;
  final double quantity;
  final double unitPrice;
  final String? variantId;
  final Map<String, String> variantAttributes;
  final String unitLabel;

  const _SaleLineRow({
    required this.productId,
    required this.productName,
    required this.category,
    required this.barcode,
    required this.quantity,
    required this.unitPrice,
    required this.variantId,
    required this.variantAttributes,
    required this.unitLabel,
  });
}
