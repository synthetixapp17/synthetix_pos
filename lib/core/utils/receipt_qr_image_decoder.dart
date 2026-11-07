import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:zxing2/qrcode.dart';

class ReceiptQrImageDecoder {
  static String decode(Uint8List bytes) {
    final image = img.decodeImage(bytes);
    if (image == null) {
      throw const FormatException('El archivo no es una imagen compatible.');
    }

    final orientations = [
      image,
      for (final angle in [90, 180, 270]) img.copyRotate(image, angle: angle),
    ];
    for (final oriented in orientations) {
      final decoded =
          _tryDecode(oriented) ?? _tryDecode(img.grayscale(oriented));
      if (decoded != null) return decoded;
    }

    for (final oriented in orientations) {
      for (final crop in _overlappingCrops(oriented)) {
        final decoded = _tryDecode(crop) ?? _tryDecode(img.grayscale(crop));
        if (decoded != null) return decoded;
      }
    }
    throw const FormatException(
      'No se encontró un código QR legible en la imagen.',
    );
  }

  static Iterable<img.Image> _overlappingCrops(img.Image image) sync* {
    if (image.width < 160 || image.height < 160) return;
    final cropWidth = (image.width * 0.6).round();
    final cropHeight = (image.height * 0.6).round();
    final offsetsX = [
      0,
      (image.width - cropWidth) ~/ 2,
      image.width - cropWidth,
    ];
    final offsetsY = [
      0,
      (image.height - cropHeight) ~/ 2,
      image.height - cropHeight,
    ];
    for (final y in offsetsY.toSet()) {
      for (final x in offsetsX.toSet()) {
        yield img.copyCrop(
          image,
          x: x,
          y: y,
          width: cropWidth,
          height: cropHeight,
        );
      }
    }
  }

  static String? _tryDecode(img.Image image) {
    final rgba = image.getBytes(order: img.ChannelOrder.rgba);
    final pixels = Int32List(image.width * image.height);
    for (var index = 0; index < pixels.length; index++) {
      final offset = index * 4;
      pixels[index] =
          (rgba[offset] << 16) | (rgba[offset + 1] << 8) | rgba[offset + 2];
    }

    final source = RGBLuminanceSource(image.width, image.height, pixels);
    for (final candidate in [source, source.invert()]) {
      try {
        return QRCodeReader()
            .decode(BinaryBitmap(HybridBinarizer(candidate)))
            .text;
      } on ReaderException {
        // Continue through image crops and orientations before reporting a miss.
      }
    }
    return null;
  }
}
