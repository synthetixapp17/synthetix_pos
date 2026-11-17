import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'virtual_store_settings.dart';

class VirtualStorePublishException implements Exception {
  final String message;

  const VirtualStorePublishException(this.message);

  @override
  String toString() => message;
}

class VirtualStorePublisher {
  final http.Client? client;

  const VirtualStorePublisher({this.client});

  Future<String> publish({
    required VirtualStoreSettings settings,
    required Map<String, Object?> catalog,
  }) async {
    final businessId = settings.businessName.trim();
    if (businessId.isEmpty) {
      throw const FormatException('Ingresa el nombre de la tienda.');
    }
    final body = jsonEncode({'businessId': businessId, 'catalog': catalog});
    if (utf8.encode(body).length > VirtualStoreCatalogBuilder.maxCatalogBytes) {
      throw const FormatException(
        'El catálogo supera 4 MB. Reduce o elimina algunas imágenes.',
      );
    }

    final response = await _post(body);
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
      throw VirtualStorePublishException(message);
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      throw const VirtualStorePublishException(
        'El servicio devolvió una respuesta que no es JSON válido.',
      );
    }
    if (decoded is! Map ||
        decoded['ok'] != true ||
        decoded['url'] is! String ||
        (decoded['url'] as String).isEmpty) {
      throw const VirtualStorePublishException(
        'El servicio no devolvió un enlace válido para la tienda.',
      );
    }
    return decoded['url'] as String;
  }

  Future<http.Response> _post(String body) async {
    final uri = Uri.parse(virtualStoreWorkerUrl);
    try {
      return await (client?.post(
                uri,
                headers: const {'Content-Type': 'application/json'},
                body: body,
              ) ??
              http.post(
                uri,
                headers: const {'Content-Type': 'application/json'},
                body: body,
              ))
          .timeout(const Duration(seconds: 45));
    } on http.ClientException catch (error) {
      throw VirtualStorePublishException(
        'No se pudo conectar con el servicio de publicación. El navegador '
        'puede haber bloqueado la solicitud por CORS: verifica que el Worker '
        'permita el origen https://synthetixapp17.github.io y responda al '
        'preflight OPTIONS. Detalle: ${error.message}',
      );
    } on TimeoutException {
      throw const VirtualStorePublishException(
        'La solicitud al servicio de publicación superó el tiempo de espera.',
      );
    }
  }
}
