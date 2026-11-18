import 'dart:convert';

import 'package:billing_app/features/settings/data/virtual_store_publisher.dart';
import 'package:billing_app/features/settings/data/virtual_store_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const businessId = '4dd7c859-9c2a-4f4f-9479-ec7ef08a6b0a';
  const clientSecret = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';

  test('requires a valid per-store identity', () async {
    await expectLater(
      VirtualStorePublisher().publish(
        settings: const VirtualStoreSettings(businessName: 'Tienda Central'),
        catalog: const {'schemaVersion': 1},
      ),
      throwsFormatException,
    );
  });

  test(
    'posts the store identity and catalog without GitHub credentials',
    () async {
      final client = MockClient((request) async {
        expect(
          request.url.toString(),
          'https://synthetix-pos.synthetixapp17.workers.dev/',
        );
        expect(request.method, 'POST');
        expect(request.headers.containsKey('Authorization'), isFalse);
        expect(request.headers['Content-Type'], 'application/json');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['businessId'], businessId);
        expect(body['clientSecret'], clientSecret);
        expect(body['catalog'], {'schemaVersion': 1, 'products': []});
        return http.Response(
          '{"ok":true,"url":"https://owner.github.io/tienda-id/tienda.html"}',
          200,
        );
      });

      final url = await VirtualStorePublisher(client: client).publish(
        settings: const VirtualStoreSettings(
          businessName: 'Tienda Central',
          businessId: businessId,
          clientSecret: clientSecret,
        ),
        catalog: const {'schemaVersion': 1, 'products': []},
      );
      expect(url, 'https://owner.github.io/tienda-id/tienda.html');
      client.close();
    },
  );

  test('shows the Worker authentication error', () async {
    final client = MockClient(
      (_) async => http.Response(
        '{"error":"La clave secreta no corresponde a esta tienda."}',
        401,
      ),
    );

    await expectLater(
      VirtualStorePublisher(client: client).publish(
        settings: const VirtualStoreSettings(
          businessName: 'Tienda Central',
          businessId: businessId,
          clientSecret: clientSecret,
        ),
        catalog: const {'schemaVersion': 1},
      ),
      throwsA(
        isA<VirtualStorePublishException>().having(
          (error) => error.message,
          'message',
          'La clave secreta no corresponde a esta tienda.',
        ),
      ),
    );
    client.close();
  });

  test('explains when the browser blocks the Worker request', () async {
    final client = MockClient(
      (_) async => throw http.ClientException('Failed to fetch'),
    );

    await expectLater(
      VirtualStorePublisher(client: client).publish(
        settings: const VirtualStoreSettings(
          businessName: 'Tienda Central',
          businessId: businessId,
          clientSecret: clientSecret,
        ),
        catalog: const {'schemaVersion': 1},
      ),
      throwsA(
        isA<VirtualStorePublishException>().having(
          (error) => error.message,
          'message',
          allOf(contains('CORS'), contains('Failed to fetch')),
        ),
      ),
    );
    client.close();
  });
}
