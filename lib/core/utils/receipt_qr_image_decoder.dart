import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:zxing2/qrcode.dart';

class ReceiptQrImageDecoder {
  static String decode(Uint8List bytes) {
    final image = img.decodeImage(bytes);
    if (image == null) {
      throw const FormatException('El archivo no es una imagen compatible.');
    }

    for (final angle in [0, 90, 180, 270]) {
      final oriented = angle == 0 ? image : img.copyRotate(image, angle: angle);
      final rgba = oriented.getBytes(order: img.ChannelOrder.rgba);
      final pixels = Int32List(oriented.width * oriented.height);
      for (var index = 0; index < pixels.length; index++) {
        final offset = index * 4;
        pixels[index] =
            (rgba[offset] << 16) | (rgba[offset + 1] << 8) | rgba[offset + 2];
      }

      final source = RGBLuminanceSource(
        oriented.width,
        oriented.height,
        pixels,
      );
      for (final candidate in [source, source.invert()]) {
        try {
          return QRCodeReader()
              .decode(BinaryBitmap(HybridBinarizer(candidate)))
              .text;
        } on ReaderException {
          // Try the next orientation or polarity before reporting a miss.
        }
      }
    }
    throw const FormatException(
      'No se encontró un código QR legible en la imagen.',
    );
  }
}
