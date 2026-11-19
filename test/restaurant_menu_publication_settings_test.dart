import 'dart:io';

import 'package:billing_app/core/data/hive_database.dart';
import 'package:billing_app/features/restaurant/data/restaurant_menu_publication_settings.dart';
import 'package:billing_app/features/restaurant/domain/entities/restaurant_menu.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'restaurant-menu-publication-test-',
    );
    Hive.init(directory.path);
    await Hive.openBox(HiveDatabase.settingsBoxName);
  });

  tearDown(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  test('serializes restaurant menu publication settings', () async {
    final settings = RestaurantMenuPublicationSettings.fromJson({
      'restaurantName': 'Casa Verde',
      'slogan': 'Cocina de temporada',
      'whatsappNumber': '+58 412-1234567',
      'whatsappMessage': 'Hola, deseo pedir.',
      'businessId': '4dd7c859-9c2a-4f4f-9479-ec7ef08a6b0a',
      'clientSecret': List.filled(43, 'A').join(),
      'publishedUrl': 'https://owner.github.io/menu/menu.html',
    });
    await settings.save();

    final loaded = RestaurantMenuPublicationSettings.load();

    expect(loaded.restaurantName, 'Casa Verde');
    expect(loaded.whatsappNumber, '584121234567');
    expect(loaded.businessId, settings.businessId);
    expect(loaded.clientSecret, settings.clientSecret);
    expect(loaded.publishedUrl, settings.publishedUrl);
  });

  test('builds a separate public menu and omits the publishing secret', () {
    final settings = RestaurantMenuPublicationSettings.fromJson({
      'restaurantName': 'Casa Verde',
      'businessId': '4dd7c859-9c2a-4f4f-9479-ec7ef08a6b0a',
      'clientSecret': List.filled(43, 'A').join(),
      'whatsappNumber': '584121234567',
    });
    const menu = RestaurantMenuState(
      categories: [
        RestaurantMenuCategory(
          id: 'mains',
          name: 'Platos principales',
          description: 'De la casa',
        ),
      ],
      products: [
        RestaurantMenuProduct(
          id: 'soup',
          categoryId: 'mains',
          name: 'Sopa',
          description: 'Del día',
          price: 4.5,
          currencyCode: 'USD',
          isAvailable: false,
          imageData:
              'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+j+ioAAAAASUVORK5CYII=',
        ),
      ],
    );

    final payload = RestaurantMenuCatalogBuilder().build(settings, menu);
    final business = payload['business'] as Map<String, Object?>;
    final products = payload['products'] as List<Map<String, Object?>>;

    expect(payload['schemaVersion'], 1);
    expect(business['id'], settings.businessId);
    expect(business['whatsapp'], '584121234567');
    expect(business.containsKey('clientSecret'), isFalse);
    expect(payload['categories'], hasLength(1));
    expect(products.single['isAvailable'], isFalse);
    expect(products.single['image'], startsWith('data:image/'));
    expect(payload.containsKey('clientSecret'), isFalse);
  });
}
