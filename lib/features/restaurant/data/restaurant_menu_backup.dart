import 'dart:convert';
import 'dart:typed_data';

import '../domain/entities/restaurant_menu.dart';

class RestaurantMenuBackup {
  static const _format = 'synthetix_restaurant_menu';
  static const _version = 1;

  Uint8List encode(RestaurantMenuState menu) {
    final json = jsonEncode({
      'format': _format,
      'version': _version,
      'menu': menu.toMap(),
    });
    return Uint8List.fromList(utf8.encode(json));
  }

  RestaurantMenuState decode(Uint8List bytes) {
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map ||
        decoded['format'] != _format ||
        decoded['version'] != _version ||
        decoded['menu'] is! Map) {
      throw const FormatException(
        'El archivo no es una copia válida del menú del restaurante.',
      );
    }
    return RestaurantMenuState.fromMap(decoded['menu'] as Map);
  }
}
