import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../../../core/data/hive_database.dart';
import '../../../core/data/models/app_settings.dart';
import '../../../core/utils/product_categories.dart';
import '../../credit/data/credit_repository.dart';

class CsvBackupFile {
  final String name;
  final Uint8List bytes;

  const CsvBackupFile({required this.name, required this.bytes});
}

class CsvBackupExporter {
  List<CsvBackupFile> createBackup() {
    final now = DateTime.now();
    final stamp =
        '${now.year.toString().padLeft(4, '0')}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}_'
        '${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}';

    final products = <List<Object?>>[
      [
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
      for (final product in HiveDatabase.productBox.values)
        [
          product.id,
          product.name,
          product.category,
          product.description,
          product.barcode,
          product.price,
          product.currencyCode,
          product.stock,
          product.imageData ?? '',
        ],
    ];
    final customers = <List<Object?>>[
      ['id', 'nombre', 'identificación', 'teléfono', 'correo', 'dirección'],
      for (final customer in HiveDatabase.customerBox.values)
        [
          customer.id,
          customer.name,
          customer.identityNumber,
          customer.phone,
          customer.email,
          customer.address,
        ],
    ];
    final categories = <List<Object?>>[
      ['nombre', 'icono_code_point', 'cantidad_productos'],
      for (final category in ProductCategories.load())
        [
          category.name,
          category.iconCodePoint,
          HiveDatabase.productBox.values
              .where(
                (product) =>
                    product.category.trim().toLowerCase() ==
                    category.name.toLowerCase(),
              )
              .length,
        ],
    ];
    final sales = <List<Object?>>[
      [
        'venta_id',
        'fecha',
        'cliente_id',
        'cliente',
        'total_venta',
        'total_en_moneda',
        'tasa_cambio',
        'moneda',
        'producto_id',
        'producto',
        'categoría',
        'codigo_producto',
        'cantidad',
        'precio_unitario',
        'total_linea',
        'forma_pago',
        'efectivo_recibido',
        'vuelto',
      ],
    ];
    for (final model in HiveDatabase.salesBox.values) {
      final sale = model.toEntity();
      if (sale.lines.isEmpty) {
        sales.add([
          sale.id,
          sale.soldAt.toIso8601String(),
          sale.customerId ?? '',
          sale.customerName ?? '',
          sale.total,
          sale.totalInCurrency,
          sale.exchangeRate,
          sale.currencyCode,
          '',
          '',
          '',
          '',
          '',
          '',
          '',
          sale.paymentMethod,
          sale.amountTendered,
          sale.changeAmount,
        ]);
        continue;
      }
      for (final line in sale.lines) {
        sales.add([
          sale.id,
          sale.soldAt.toIso8601String(),
          sale.customerId ?? '',
          sale.customerName ?? '',
          sale.total,
          sale.totalInCurrency,
          sale.exchangeRate,
          sale.currencyCode,
          line.productId,
          line.productName,
          line.category,
          line.barcode,
          line.quantity,
          line.unitPrice,
          line.total,
          sale.paymentMethod,
          sale.amountTendered,
          sale.changeAmount,
        ]);
      }
    }
    final credits = <List<Object?>>[
      [
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
      for (final credit in CreditRepository.getAll())
        [
          credit.id,
          credit.createdAt.toIso8601String(),
          credit.dueDate?.toIso8601String() ?? '',
          credit.customerId,
          credit.customerName,
          credit.customerIdentity,
          credit.customerPhone,
          credit.customerEmail,
          credit.customerAddress,
          credit.total,
          credit.purchaseAmount ?? '',
          credit.initialPayment,
          credit.interestPercentage,
          credit.interestAmount,
          credit.paidAmount,
          credit.balance,
          credit.currencyCode,
          credit.installmentCount ?? '',
          credit.daysBetweenPayments ?? '',
          jsonEncode(
            credit.payments.map((payment) => payment.toJson()).toList(),
          ),
          jsonEncode(credit.lines.map((line) => line.toJson()).toList()),
          credit.pdfBase64,
        ],
    ];
    final shop = <List<Object?>>[
      ['dato', 'valor'],
    ];
    for (final model in HiveDatabase.shopBox.values) {
      shop.addAll([
        ['nombre_tienda', model.name],
        ['dirección', model.addressLine1],
        ['complemento_dirección', model.addressLine2],
        ['teléfono', model.phoneNumber],
        ['RIF', model.rif],
        ['identificador_pago', model.upiId],
        ['mensaje_ticket', model.footerText],
        ['logotipo_base64', model.logoData ?? ''],
      ]);
    }
    for (final key in HiveDatabase.settingsBox.keys) {
      final value = HiveDatabase.settingsBox.get(key);
      final jsonValue = value is AppSettings
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
      shop.add([key.toString(), jsonEncode(jsonValue)]);
    }

    return [
      _file('respaldo_productos_$stamp.csv', products),
      _file('respaldo_categorias_$stamp.csv', categories),
      _file('respaldo_clientes_$stamp.csv', customers),
      _file('respaldo_ventas_$stamp.csv', sales),
      _file('respaldo_creditos_$stamp.csv', credits),
      _file('respaldo_tienda_configuracion_$stamp.csv', shop),
    ];
  }

  CsvBackupFile createBackupPackage() {
    final files = createBackup();
    final archive = Archive();
    for (final file in files) {
      archive.add(ArchiveFile.bytes(file.name, file.bytes));
    }
    final now = DateTime.now();
    final stamp =
        '${now.year.toString().padLeft(4, '0')}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}_'
        '${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}'
        '${now.second.toString().padLeft(2, '0')}';
    return CsvBackupFile(
      name: 'respaldo_completo_$stamp.zip',
      bytes: Uint8List.fromList(ZipEncoder().encodeBytes(archive)),
    );
  }

  CsvBackupFile _file(String name, List<List<Object?>> rows) {
    final csv = rows.map((row) => row.map(_escape).join(',')).join('\r\n');
    return CsvBackupFile(
      name: name,
      bytes: Uint8List.fromList(utf8.encode('\uFEFF$csv')),
    );
  }

  String _escape(Object? value) {
    final text = value?.toString() ?? '';
    return '"${text.replaceAll('"', '""')}"';
  }
}
