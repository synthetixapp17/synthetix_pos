import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'restaurant_menu_publication_settings.dart';

class RestaurantMenuPublishException implements Exception {
  final String message;

  const RestaurantMenuPublishException(this.message);

  @override
  String toString() => message;
}

class RestaurantMenuPublisher {
  final http.Client? client;

  const RestaurantMenuPublisher({this.client});

  Future<String> publish({
    required RestaurantMenuPublicationSettings settings,
    required Map<String, Object?> menu,
  }) async {
    if (!RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          caseSensitive: false,
        ).hasMatch(settings.businessId) ||
        !RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(settings.clientSecret)) {
      throw const FormatException(
        'No se pudo crear la identidad segura del menú.',
      );
    }

    final body = jsonEncode({
      'siteType': 'restaurant',
      'businessId': settings.businessId,
      'clientSecret': settings.clientSecret,
      'menu': menu,
    });
    if (utf8.encode(body).length > RestaurantMenuCatalogBuilder.maxMenuBytes) {
      throw const FormatException(
        'El menú supera 4 MB. Reduce o elimina algunas imágenes.',
      );
    }

    http.Response response;
    try {
      response =
          await (client?.post(
                    Uri.parse(restaurantMenuWorkerUrl),
                    headers: const {'Content-Type': 'application/json'},
                    body: body,
                  ) ??
                  http.post(
                    Uri.parse(restaurantMenuWorkerUrl),
                    headers: const {'Content-Type': 'application/json'},
                    body: body,
                  ))
              .timeout(const Duration(seconds: 45));
    } on http.ClientException catch (error) {
      throw RestaurantMenuPublishException(
        'No se pudo conectar con el servicio de publicación. Verifica CORS y '
        'la configuración del Worker. Detalle: ${error.message}',
      );
    } on TimeoutException {
      throw const RestaurantMenuPublishException(
        'La publicación del menú superó el tiempo de espera.',
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      var message = 'El servicio respondió con HTTP ${response.statusCode}.';
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map && decoded['error'] is String) {
          message = decoded['error'] as String;
        }
      } on FormatException {
        // Keep the HTTP status when the proxy does not return JSON.
      }
      throw RestaurantMenuPublishException(message);
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      throw const RestaurantMenuPublishException(
        'El servicio devolvió una respuesta que no es JSON válida.',
      );
    }
    if (decoded is! Map ||
        decoded['ok'] != true ||
        decoded['url'] is! String ||
        (decoded['url'] as String).isEmpty) {
      throw const RestaurantMenuPublishException(
        'El servicio no devolvió un enlace válido para el menú.',
      );
    }
    return decoded['url'] as String;
  }
}
