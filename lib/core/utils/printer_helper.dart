import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:permission_handler/permission_handler.dart';
import 'app_currency.dart';
import 'receipt_preferences.dart';

class PrinterException implements Exception {
  final String message;
  const PrinterException(this.message);

  @override
  String toString() => message;
}

class EscPos {
  static const List<int> init = [0x1B, 0x40];
  static const List<int> alignCenter = [0x1B, 0x61, 0x01];
  static const List<int> alignLeft = [0x1B, 0x61, 0x00];
  static const List<int> alignRight = [0x1B, 0x61, 0x02];
  static const List<int> boldOn = [0x1B, 0x45, 0x01];
  static const List<int> boldOff = [0x1B, 0x45, 0x00];
  static const List<int> textNormal = [0x1D, 0x21, 0x00];
  static const List<int> textLarge = [0x1D, 0x21, 0x11];
  static const List<int> lineFeed = [0x0A];

  static List<int> qrCode(String data) {
    final qrData = utf8.encode(data);
    final length = qrData.length + 3;
    return [
      0x1D,
      0x28,
      0x6B,
      0x04,
      0x00,
      0x31,
      0x41,
      0x32,
      0x00,
      0x1D,
      0x28,
      0x6B,
      0x03,
      0x00,
      0x31,
      0x43,
      0x05,
      0x1D,
      0x28,
      0x6B,
      0x03,
      0x00,
      0x31,
      0x45,
      0x31,
      0x1D,
      0x28,
      0x6B,
      length & 0xFF,
      (length >> 8) & 0xFF,
      0x31,
      0x50,
      0x30,
      ...qrData,
      0x1D,
      0x28,
      0x6B,
      0x03,
      0x00,
      0x31,
      0x51,
      0x30,
    ];
  }
}

class PrinterHelper {
  // Singleton
  static final PrinterHelper _instance = PrinterHelper._internal();
  factory PrinterHelper() => _instance;
  PrinterHelper._internal();

  bool _isConnected = false;
  bool get isConnected => _isConnected;

  Future<bool> checkPermission() async {
    if (!Platform.isAndroid) return true;
    if (await PrintBluetoothThermal.isPermissionBluetoothGranted) return true;

    final statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
    ].request();
    final permissionsGranted = statuses.values.every(
      (status) => status.isGranted,
    );
    if (!permissionsGranted ||
        !await PrintBluetoothThermal.isPermissionBluetoothGranted) {
      throw const PrinterException(
        'Falta conceder el permiso de dispositivos cercanos para usar Bluetooth. '
        'Actívalo en los ajustes de la aplicación.',
      );
    }
    return true;
  }

  Future<List<BluetoothInfo>> getBondedDevices() async {
    await checkPermission();
    if (!await PrintBluetoothThermal.bluetoothEnabled) {
      throw const PrinterException(
        'Activa Bluetooth en el dispositivo y vuelve a buscar impresoras.',
      );
    }
    return PrintBluetoothThermal.pairedBluetooths;
  }

  Future<bool> connect(String macAddress) async {
    await checkPermission();
    if (!await PrintBluetoothThermal.bluetoothEnabled) {
      _isConnected = false;
      throw const PrinterException(
        'Activa Bluetooth en el dispositivo antes de conectar la impresora.',
      );
    }
    final connected = await PrintBluetoothThermal.connect(
      macPrinterAddress: macAddress,
    );
    _isConnected = connected && await PrintBluetoothThermal.connectionStatus;
    return _isConnected;
  }

  Future<bool> checkConnection() async {
    _isConnected = await PrintBluetoothThermal.connectionStatus;
    return _isConnected;
  }

  Future<bool> disconnect() async {
    if (!await checkConnection()) return true;
    final disconnected = await PrintBluetoothThermal.disconnect;
    _isConnected = await PrintBluetoothThermal.connectionStatus;
    return disconnected && !_isConnected;
  }

  Future<void> printText(String text) async {
    if (!await checkConnection()) {
      throw const PrinterException(
        'La impresora no está conectada. Conéctala antes de imprimir.',
      );
    }
    final printed = await PrintBluetoothThermal.writeBytes(text.codeUnits);
    if (!printed) {
      _isConnected = false;
      throw const PrinterException(
        'La impresora no respondió. Comprueba el papel, la batería y la conexión.',
      );
    }
  }

  Future<void> printBarcodeLabel({
    required String productName,
    required String barcode,
    required double price,
  }) async {
    if (!await checkConnection()) {
      throw const PrinterException(
        'La impresora no está conectada. Conéctala antes de imprimir.',
      );
    }
    if (barcode.isEmpty ||
        barcode.length > 64 ||
        !RegExp(r'^[\x20-\x7E]+$').hasMatch(barcode)) {
      throw const PrinterException(
        'El código debe contener entre 1 y 64 caracteres ASCII imprimibles.',
      );
    }

    final code128Data = '{B$barcode'.codeUnits;
    final bytes = <int>[
      ...EscPos.init,
      ...EscPos.alignCenter,
      ...EscPos.boldOn,
      ..._textToBytes(productName),
      ...EscPos.lineFeed,
      ...EscPos.textLarge,
      ...EscPos.boldOn,
      ..._textToBytes('Precio: ${AppCurrency.format(price)}'),
      ...EscPos.lineFeed,
      ...EscPos.textNormal,
      ...EscPos.boldOff,
      0x1D,
      0x48,
      0x02,
      0x1D,
      0x68,
      0x50,
      0x1D,
      0x77,
      0x02,
      0x1D,
      0x6B,
      0x49,
      code128Data.length,
      ...code128Data,
      ...EscPos.lineFeed,
      ..._textToBytes(barcode),
      ...EscPos.lineFeed,
      ...EscPos.lineFeed,
      ...EscPos.lineFeed,
    ];
    final printed = await PrintBluetoothThermal.writeBytes(bytes);
    _isConnected = printed && await PrintBluetoothThermal.connectionStatus;
    if (!printed) {
      throw const PrinterException(
        'No se pudo imprimir la etiqueta del código de barras.',
      );
    }
  }

  Future<bool> printReceipt({
    required String shopName,
    required String address1,
    required String address2,
    required String phone,
    String rif = '',
    String? qrData,
    String? customerName,
    String? logoData,
    required List<Map<String, dynamic>> items, // Name, Qty, Price, Total
    required double total,
    required String footer,
    String currencyCode = 'USD',
    double exchangeRate = 1,
    String paymentMethod = 'Efectivo',
    double amountTendered = 0,
    double changeAmount = 0,
    bool showAddress = true,
    bool showPhone = true,
    bool showRif = true,
    bool showInvoiceQr = true,
    bool showDate = true,
    bool showBarcode = false,
    bool showUnitPrices = true,
  }) async {
    if (!exchangeRate.isFinite || exchangeRate <= 0) {
      throw ArgumentError.value(exchangeRate, 'exchangeRate');
    }
    if (!await checkConnection()) {
      throw const PrinterException(
        'La impresora se desconectó antes de imprimir el recibo.',
      );
    }

    final paperColumns = ReceiptPreferences.paperColumns;
    final totalColumnWidth = paperColumns == 48 ? 12 : 8;
    final priceColumnWidth = paperColumns == 48 ? 10 : 8;
    final productColumnWidth = paperColumns - totalColumnWidth;
    final unitPriceProductWidth = paperColumns -
        totalColumnWidth -
        priceColumnWidth;
    final separator = '-' * paperColumns;

    // Construct ESC/POS bytes manually or using helper
    List<int> bytes = [];

    // Init
    bytes += EscPos.init;

    // Shop Name (Center, Bold, Large)
    bytes += EscPos.alignCenter;
    if (logoData != null && logoData.isNotEmpty) {
      try {
        bytes += _logoRasterBytes(base64Decode(logoData));
      } on FormatException catch (error) {
        throw PrinterException('El logotipo del ticket no es válido: $error');
      }
    }
    bytes += EscPos.boldOn;
    bytes += EscPos.textLarge;
    bytes += _textToBytes(shopName);
    bytes += EscPos.lineFeed;

    // Address & Phone (Normal, Center)
    bytes += EscPos.textNormal;
    bytes += EscPos.boldOff;
    if (showAddress && address1.isNotEmpty) {
      bytes += _textToBytes(address1);
      bytes += EscPos.lineFeed;
    }
    if (showAddress && address2.isNotEmpty) {
      bytes += _textToBytes(address2);
      bytes += EscPos.lineFeed;
    }
    if (showPhone && phone.isNotEmpty) {
      bytes += _textToBytes(phone);
      bytes += EscPos.lineFeed;
    }
    if (showRif && rif.trim().isNotEmpty) {
      bytes += _textToBytes('RIF: ${rif.trim()}');
      bytes += EscPos.lineFeed;
    }

    if (showDate) {
      final formattedDate = DateFormat(
        'dd/MM/yyyy HH:mm',
        'es',
      ).format(DateTime.now());
      bytes += _textToBytes(formattedDate);
      bytes += EscPos.lineFeed;
    }
    if (customerName != null && customerName.trim().isNotEmpty) {
      bytes += _textToBytes('Cliente: $customerName');
      bytes += EscPos.lineFeed;
    }
    bytes += _textToBytes('Forma de pago: $paymentMethod');
    bytes += EscPos.lineFeed;
    bytes += _textToBytes(
      'Tasa: 1 USD = ${exchangeRate.toString()} $currencyCode',
    );
    bytes += EscPos.lineFeed;

    bytes += _textToBytes(separator);
    bytes += EscPos.lineFeed;

    // Header (Align Left)
    bytes += EscPos.alignLeft;
    bytes += _textToBytes(
      showUnitPrices
          ? 'Producto'.padRight(unitPriceProductWidth) +
                'Precio'.padLeft(priceColumnWidth) +
                'Total'.padLeft(totalColumnWidth)
          : 'Producto'.padRight(productColumnWidth) +
                'Total'.padLeft(totalColumnWidth),
    );
    bytes += EscPos.lineFeed;
    bytes += _textToBytes(separator);
    bytes += EscPos.lineFeed;

    // Items
    for (var item in items) {
      String name = item['name'].toString();
      String qty = item['qty'].toString();
      String price = AppCurrency.format(
        item['price'] as num,
        code: currencyCode,
      );
      String totalItem = AppCurrency.format(
        item['total'] as num,
        code: currencyCode,
      );

      final barcode = item['barcode']?.toString() ?? '';
      final rawPrefix = '${qty}x $name';
      final productTextWidth = showUnitPrices
          ? unitPriceProductWidth
          : productColumnWidth;
      final prefix = rawPrefix.length > productTextWidth
          ? rawPrefix.substring(0, productTextWidth)
          : rawPrefix;

      final line = showUnitPrices
          ? prefix.padRight(unitPriceProductWidth) +
                price.padLeft(priceColumnWidth) +
                totalItem.padLeft(totalColumnWidth)
          : prefix.padRight(productColumnWidth) +
                totalItem.padLeft(totalColumnWidth);
      bytes += _textToBytes(line);
      bytes += EscPos.lineFeed;
      bytes += _textToBytes(
        showUnitPrices
            ? '  Ref. USD: ${((item['price'] as num) / exchangeRate).toStringAsFixed(2)} / u · '
                  '${((item['total'] as num) / exchangeRate).toStringAsFixed(2)}'
            : '  Ref. USD: ${((item['total'] as num) / exchangeRate).toStringAsFixed(2)}',
      );
      bytes += EscPos.lineFeed;
      if (showBarcode && barcode.isNotEmpty) {
        bytes += _textToBytes('  Código: $barcode');
        bytes += EscPos.lineFeed;
      }
    }

    bytes += _textToBytes(separator);
    bytes += EscPos.lineFeed;

    // Total (Align Right)
    bytes += EscPos.alignRight;
    bytes += EscPos.boldOn;
    bytes += _textToBytes(
      'TOTAL: ${AppCurrency.format(total, code: currencyCode)}',
    );
    bytes += EscPos.lineFeed;
    bytes += _textToBytes(
      'Ref. USD: ${(total / exchangeRate).toStringAsFixed(2)}',
    );
    bytes += EscPos.lineFeed;
    bytes += EscPos.boldOff;
    if (paymentMethod.toLowerCase() == 'efectivo' && amountTendered > 0) {
      bytes += _textToBytes(
        'Recibido: ${AppCurrency.format(amountTendered, code: currencyCode)}',
      );
      bytes += EscPos.lineFeed;
      bytes += _textToBytes(
        'Vuelto: ${AppCurrency.format(changeAmount, code: currencyCode)}',
      );
      bytes += EscPos.lineFeed;
      bytes += _textToBytes(
        'Ref. USD: ${(amountTendered / exchangeRate).toStringAsFixed(2)} recibido · '
        '${(changeAmount / exchangeRate).toStringAsFixed(2)} vuelto',
      );
      bytes += EscPos.lineFeed;
    }
    if (showInvoiceQr && qrData != null && qrData.isNotEmpty) {
      bytes += EscPos.lineFeed;
      bytes += EscPos.alignCenter;
      bytes += EscPos.qrCode(qrData);
      bytes += _textToBytes('Consulta esta venta por QR');
      bytes += EscPos.lineFeed;
      bytes += EscPos.alignLeft;
    }
    bytes += EscPos.lineFeed;

    // Footer (Center)
    bytes += EscPos.alignCenter;
    bytes += _textToBytes(footer);
    bytes += EscPos.lineFeed;
    bytes += EscPos.lineFeed; // One line space after footer
    bytes += EscPos.lineFeed;
    bytes += EscPos.lineFeed; // Additional Feed

    final printed = await PrintBluetoothThermal.writeBytes(bytes);
    _isConnected = printed && await PrintBluetoothThermal.connectionStatus;
    if (!printed) {
      throw const PrinterException(
        'No se pudo enviar el recibo. Comprueba la impresora e inténtalo de nuevo.',
      );
    }
    return true;
  }

  List<int> _textToBytes(String text) {
    return List.from(text.codeUnits);
  }

  List<int> _logoRasterBytes(Uint8List data) {
    final decoded = img.decodeImage(data);
    if (decoded == null) {
      throw const PrinterException(
        'No se pudo interpretar la imagen del logotipo.',
      );
    }

    final scale = math.min(
      1.0,
      math.min(384 / decoded.width, 384 / decoded.height),
    );
    final width = math.max(1, (decoded.width * scale).round()).toInt();
    final height = math.max(1, (decoded.height * scale).round()).toInt();
    final resized = img.copyResize(decoded, width: width, height: height);
    final widthBytes = (width + 7) ~/ 8;
    final raster = Uint8List(widthBytes * height);

    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final pixel = resized.getPixel(x, y);
        final alpha = pixel.a / 255;
        final red = pixel.r * alpha + 255 * (1 - alpha);
        final green = pixel.g * alpha + 255 * (1 - alpha);
        final blue = pixel.b * alpha + 255 * (1 - alpha);
        final luminance = red * 0.299 + green * 0.587 + blue * 0.114;
        if (luminance < 160) {
          final index = y * widthBytes + x ~/ 8;
          raster[index] |= 0x80 >> (x % 8);
        }
      }
    }

    return [
      0x1D,
      0x76,
      0x30,
      0x00,
      widthBytes & 0xFF,
      (widthBytes >> 8) & 0xFF,
      height & 0xFF,
      (height >> 8) & 0xFF,
      ...raster,
      ...EscPos.lineFeed,
    ];
  }
}
