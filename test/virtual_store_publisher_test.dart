import 'dart:convert';

import 'package:billing_app/features/settings/data/virtual_store_publisher.dart';
import 'package:billing_app/features/settings/data/virtual_store_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'posts the catalog and selected repository to the configured Worker',
    () async {
      final client = MockClient((request) async {
        expect(
          request.url,
          Uri.parse('https://synthetix-pos.synthetixapp17.workers.dev'),
        );
        expect(request.method, 'POST');
        expect(request.headers['Authorization'], 'Bearer client-key');
        expect(request.headers['Content-Type'], 'application/json');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['owner'], 'merchant');
        expect(body['repository'], 'shop');
        expect(body['catalog'], {'schemaVersion': 1, 'products': []});
        return http.Response('{"ok":true}', 200);
      });

      await VirtualStorePublisher(client: client).publish(
        settings: const VirtualStoreSettings(
          githubOwner: 'merchant',
          githubRepository: 'shop',
          publisherApiKey: 'client-key',
        ),
        catalog: const {'schemaVersion': 1, 'products': []},
      );
      client.close();
    },
  );
}
