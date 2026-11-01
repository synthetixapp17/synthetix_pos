import 'dart:convert';
import 'dart:typed_data';

import '../../../core/data/hive_database.dart';
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
      ['id', 'nombre', 'teléfono', 'correo', 'dirección'],
      for (final customer in HiveDatabase.customerBox.values)
        [
          customer.id,
          customer.name,
          customer.phone,
          customer.email,
          customer.address,
        ],
    ];
    final sales = <List<Object?>>[
      [
        'venta_id',
        'fecha',
        'cliente_id',
        'cliente',
        'total_venta',
        'moneda',
        'producto_id',
        'producto',
        'categoría',
        'cantidad',
        'precio_unitario',
        'total_linea',
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
          sale.currencyCode,
          '',
          '',
          '',
          '',
          '',
          '',
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
          sale.currencyCode,
          line.productId,
          line.productName,
          line.category,
          line.quantity,
          line.unitPrice,
          line.total,
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
        'telefono_cliente',
        'correo_cliente',
        'direccion_cliente',
        'total_compra',
        'total_abonado',
        'saldo_pendiente',
        'moneda',
        'historial_abonos_json',
        'comprobante_pdf_base64',
      ],
      for (final credit in CreditRepository.getAll())
        [
          credit.id,
          credit.createdAt.toIso8601String(),
          credit.dueDate?.toIso8601String() ?? '',
          credit.customerId,
          credit.customerName,
          credit.customerPhone,
          credit.customerEmail,
          credit.customerAddress,
          credit.total,
          credit.paidAmount,
          credit.balance,
          credit.currencyCode,
          jsonEncode(
            credit.payments.map((payment) => payment.toJson()).toList(),
          ),
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
        ['identificador_pago', model.upiId],
        ['mensaje_ticket', model.footerText],
        ['logotipo_base64', model.logoData ?? ''],
      ]);
    }
    for (final key in HiveDatabase.settingsBox.keys) {
      shop.add([key.toString(), jsonEncode(HiveDatabase.settingsBox.get(key))]);
    }

    return [
      _file('respaldo_productos_$stamp.csv', products),
      _file('respaldo_clientes_$stamp.csv', customers),
      _file('respaldo_ventas_$stamp.csv', sales),
      _file('respaldo_creditos_$stamp.csv', credits),
      _file('respaldo_tienda_configuracion_$stamp.csv', shop),
    ];
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
