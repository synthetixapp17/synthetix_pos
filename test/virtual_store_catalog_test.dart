import 'package:billing_app/features/product/data/models/product_model.dart';
import 'package:billing_app/features/product/domain/entities/product.dart';
import 'package:billing_app/features/settings/data/virtual_store_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('builds a public catalog with store branding and product variants', () {
    const settings = VirtualStoreSettings(
      businessName: 'Café Central',
      slogan: 'Café recién molido',
      whatsappNumber: '584120000000',
      primaryColor: 0xFF008C95,
      accentColor: 0xFFFFB300,
    );
    final catalog = VirtualStoreCatalogBuilder().build(settings, [
      ProductModel.fromEntity(
        const Product(
          id: 'coffee',
          name: 'Café',
          barcode: '123',
          price: 4.5,
          stock: 8,
          currencyCode: 'USD',
          category: 'Bebidas',
          variants: [
            ProductVariant(
              id: 'small',
              attributes: {'Tamaño': 'Pequeño'},
              price: 4.5,
              stock: 3,
            ),
          ],
        ),
      ),
    ], updatedAt: DateTime.utc(2026, 11, 15));

    expect(catalog['schemaVersion'], 1);
    expect(catalog['updatedAt'], '2026-11-15T00:00:00.000Z');
    expect(catalog['business'], {
      'id': 'Café Central',
      'name': 'Café Central',
      'slogan': 'Café recién molido',
      'whatsapp': '584120000000',
      'logo': null,
      'colors': {'primary': '#008c95', 'accent': '#ffb300'},
    });
    final products = catalog['products'] as List<Map<String, Object?>>;
    expect(products.single['name'], 'Café');
    expect((products.single['variants'] as List).single['id'], 'small');
  });

  test('migrates legacy identity fields without retaining credentials', () {
    final settings = VirtualStoreSettings.fromJson({
      'businessName': 'Mi tienda',
      'businessId': 'legacy-business-id',
      'clientSecret': 'legacy-client-secret',
    });

    final restored = VirtualStoreSettings.fromJson(settings.toJson());
    expect(restored.businessName, settings.businessName);
    expect(settings.toJson().containsKey('businessId'), isFalse);
    expect(settings.toJson().containsKey('clientSecret'), isFalse);
  });
}
