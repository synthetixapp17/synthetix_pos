import 'dart:convert';

import 'package:http/http.dart' as http;

import 'virtual_store_settings.dart';

class VirtualStorePublisher {
  final http.Client? client;

  const VirtualStorePublisher({this.client});

  Future<void> publish({
    required VirtualStoreSettings settings,
    required Map<String, Object?> catalog,
  }) async {
    if (settings.publisherApiKey.trim().isEmpty) {
      throw const FormatException(
        'Configura la clave de acceso del servicio de publicación.',
      );
    }
    final body = jsonEncode({
      'owner': settings.githubOwner,
      'repository': settings.githubRepository,
      'catalog': catalog,
    });
    if (utf8.encode(body).length > VirtualStoreCatalogBuilder.maxCatalogBytes) {
      throw const FormatException(
        'El catálogo supera 4 MB. Reduce o elimina algunas imágenes.',
      );
    }

    final response =
        await (client?.post(
                  Uri.parse(virtualStoreWorkerUrl),
                  headers: {
                    'Authorization': 'Bearer ${settings.publisherApiKey}',
                    'Content-Type': 'application/json',
                  },
                  body: body,
                ) ??
                http.post(
                  Uri.parse(virtualStoreWorkerUrl),
                  headers: {
                    'Authorization': 'Bearer ${settings.publisherApiKey}',
                    'Content-Type': 'application/json',
                  },
                  body: body,
                ))
            .timeout(const Duration(seconds: 45));
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
      throw StateError(message);
    }
  }
}
