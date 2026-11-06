import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:zxing2/qrcode.dart';

class ReceiptQrImageDecoder {
  static String decode(Uint8List bytes) {
    final image = img.decodeImage(bytes);
    if (image == null) {
      throw const FormatException('El archivo no es una imagen compatible.');
    }

    final rgba = image.getBytes(order: img.ChannelOrder.rgba);
    final pixels = Int32List(image.width * image.height);
    for (var index = 0; index < pixels.length; index++) {
      final offset = index * 4;
      pixels[index] =
          (rgba[offset] << 16) | (rgba[offset + 1] << 8) | rgba[offset + 2];
    }

    final source = RGBLuminanceSource(image.width, image.height, pixels);
    final bitmap = BinaryBitmap(HybridBinarizer(source));
    return QRCodeReader().decode(bitmap).text;
  }
}
