import 'dart:convert';

import 'package:billing_app/features/restaurant/data/restaurant_menu_publication_settings.dart';
import 'package:billing_app/features/restaurant/data/restaurant_menu_publisher.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const settings = RestaurantMenuPublicationSettings(
    restaurantName: 'Casa Verde',
  );
  const menu = {
    'format': 'synthetix_restaurant_menu',
    'version': 1,
    'menu': {'categories': <Map<String, Object?>>[], 'products': <Map<String, Object?>>[]},
  };

  test('posts the restaurant menu without an identity or secret', () async {
    final client = MockClient((request) async {
      expect(request.url.toString(), restaurantMenuWorkerUrl);
      expect(request.method, 'POST');
      expect(request.headers.containsKey('Authorization'), isFalse);
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['format'], 'synthetix_restaurant_menu');
      expect(body['version'], 1);
      expect(body['menu'], menu['menu']);
      return http.Response(
        '{"ok":true,"url":"https://owner.github.io/menu-id/menu.html"}',
        200,
      );
    });

    final url = await RestaurantMenuPublisher(
      client: client,
    ).publish(settings: settings, menu: menu);

    expect(url, 'https://owner.github.io/menu-id/menu.html');
    client.close();
  });

  test('surfaces Worker errors', () async {
    final client = MockClient(
      (_) async => http.Response(
        '{"error":"No está configurada la plantilla para el menú del restaurante."}',
        503,
      ),
    );

    await expectLater(
      RestaurantMenuPublisher(
        client: client,
      ).publish(settings: settings, menu: menu),
      throwsA(
        isA<RestaurantMenuPublishException>().having(
          (error) => error.message,
          'message',
          contains('plantilla'),
        ),
      ),
    );
    client.close();
  });

  test('rejects menus that exceed the Worker limit', () async {
    await expectLater(
      RestaurantMenuPublisher().publish(
        settings: settings,
        menu: {'large': 'x' * RestaurantMenuCatalogBuilder.maxMenuBytes},
      ),
      throwsFormatException,
    );
  });
}
