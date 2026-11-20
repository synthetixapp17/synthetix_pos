import 'dart:convert';
import 'dart:math';

import 'package:uuid/uuid.dart';

import '../../../core/data/hive_database.dart';
import '../../../features/settings/data/virtual_store_identity_storage.dart';
import '../../../features/settings/data/virtual_store_settings.dart';
import '../domain/entities/restaurant_menu.dart';

const restaurantMenuPublicationSettingsKey =
    'restaurant_menu_publication_settings_v1';
const restaurantMenuWorkerUrl = virtualStoreWorkerUrl;
const _restaurantMenuBusinessIdStorageKey =
    'restaurant_menu_publication_business_id';
const _restaurantMenuClientSecretStorageKey =
    'restaurant_menu_publication_client_secret';

class RestaurantMenuPublicationSettings {
  final String restaurantName;
  final String slogan;
  final String whatsappNumber;
  final String whatsappMessage;
  final String? logoData;
  final int primaryColor;
  final int accentColor;
  final String businessId;
  final String clientSecret;
  final DateTime? lastPublishedAt;
  final String publishedUrl;

  const RestaurantMenuPublicationSettings({
    this.restaurantName = '',
    this.slogan = '',
    this.whatsappNumber = '',
    this.whatsappMessage = '',
    this.logoData,
    this.primaryColor = 0xFF315C46,
    this.accentColor = 0xFFD8A15D,
    this.businessId = '',
    this.clientSecret = '',
    this.lastPublishedAt,
    this.publishedUrl = '',
  });

  factory RestaurantMenuPublicationSettings.load() {
    final stored = HiveDatabase.settingsBox.get(
      restaurantMenuPublicationSettingsKey,
    );
    if (stored != null) {
      if (stored is! String) {
        throw const FormatException(
          'La configuración del menú digital no es válida.',
        );
      }
      final decoded = jsonDecode(stored);
      if (decoded is! Map || decoded.keys.any((key) => key is! String)) {
        throw const FormatException(
          'La configuración del menú digital está dañada.',
        );
      }
      return RestaurantMenuPublicationSettings.fromJson(
        decoded.cast<String, dynamic>(),
      );
    }

    final shop = HiveDatabase.shopBox.get('shop_details');
    final identity = _getOrCreateIdentity('', '');
    return RestaurantMenuPublicationSettings(
      restaurantName: shop?.name ?? '',
      whatsappNumber: _digitsOnly(shop?.phoneNumber ?? ''),
      logoData: shop?.logoData,
      businessId: identity.$1,
      clientSecret: identity.$2,
    );
  }

  factory RestaurantMenuPublicationSettings.fromJson(
    Map<String, dynamic> json,
  ) {
    final primaryColor = json['primaryColor'];
    final accentColor = json['accentColor'];
    final lastPublishedAt = json['lastPublishedAt'];
    final logoData = json['logoData'];
    if ((primaryColor != null && primaryColor is! int) ||
        (accentColor != null && accentColor is! int) ||
        (lastPublishedAt != null && lastPublishedAt is! String) ||
        (logoData != null && logoData is! String)) {
      throw const FormatException(
        'Hay valores inválidos en la configuración del menú digital.',
      );
    }
    final parsedPublishedAt = lastPublishedAt == null
        ? null
        : DateTime.tryParse(lastPublishedAt as String);
    if (lastPublishedAt != null && parsedPublishedAt == null) {
      throw const FormatException(
        'La fecha de publicación guardada no es válida.',
      );
    }
    final identity = _getOrCreateIdentity(
      _stringValue(json, 'businessId'),
      _stringValue(json, 'clientSecret'),
    );
    return RestaurantMenuPublicationSettings(
      restaurantName: _stringValue(json, 'restaurantName'),
      slogan: _stringValue(json, 'slogan'),
      whatsappNumber: _digitsOnly(_stringValue(json, 'whatsappNumber')),
      whatsappMessage: _stringValue(json, 'whatsappMessage'),
      logoData: logoData as String?,
      primaryColor: primaryColor as int? ?? 0xFF315C46,
      accentColor: accentColor as int? ?? 0xFFD8A15D,
      businessId: identity.$1,
      clientSecret: identity.$2,
      lastPublishedAt: parsedPublishedAt,
      publishedUrl: _stringValue(json, 'publishedUrl'),
    );
  }

  RestaurantMenuPublicationSettings copyWith({
    String? restaurantName,
    String? slogan,
    String? whatsappNumber,
    String? whatsappMessage,
    String? logoData,
    bool clearLogo = false,
    int? primaryColor,
    int? accentColor,
    String? businessId,
    String? clientSecret,
    DateTime? lastPublishedAt,
    String? publishedUrl,
  }) => RestaurantMenuPublicationSettings(
    restaurantName: restaurantName ?? this.restaurantName,
    slogan: slogan ?? this.slogan,
    whatsappNumber: whatsappNumber ?? this.whatsappNumber,
    whatsappMessage: whatsappMessage ?? this.whatsappMessage,
    logoData: clearLogo ? null : logoData ?? this.logoData,
    primaryColor: primaryColor ?? this.primaryColor,
    accentColor: accentColor ?? this.accentColor,
    businessId: businessId ?? this.businessId,
    clientSecret: clientSecret ?? this.clientSecret,
    lastPublishedAt: lastPublishedAt ?? this.lastPublishedAt,
    publishedUrl: publishedUrl ?? this.publishedUrl,
  );

  Map<String, Object?> toJson() => {
    'restaurantName': restaurantName,
    'slogan': slogan,
    'whatsappNumber': whatsappNumber,
    'whatsappMessage': whatsappMessage,
    'logoData': logoData,
    'primaryColor': primaryColor,
    'accentColor': accentColor,
    'businessId': businessId,
    'clientSecret': clientSecret,
    'lastPublishedAt': lastPublishedAt?.toIso8601String(),
    'publishedUrl': publishedUrl,
  };

  Future<void> save() => HiveDatabase.settingsBox.put(
    restaurantMenuPublicationSettingsKey,
    jsonEncode(toJson()),
  );

  static (String, String) _getOrCreateIdentity(
    String businessId,
    String clientSecret,
  ) {
    final storedBusinessId = readVirtualStoreIdentity(
      _restaurantMenuBusinessIdStorageKey,
    );
    final storedClientSecret = readVirtualStoreIdentity(
      _restaurantMenuClientSecretStorageKey,
    );
    final resolvedBusinessId = storedBusinessId ?? businessId;
    final resolvedClientSecret = storedClientSecret ?? clientSecret;
    final validBusinessId = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      caseSensitive: false,
    ).hasMatch(resolvedBusinessId);
    final validClientSecret = RegExp(
      r'^[A-Za-z0-9_-]{43}$',
    ).hasMatch(resolvedClientSecret);
    final identity = validBusinessId && validClientSecret
        ? (resolvedBusinessId.toLowerCase(), resolvedClientSecret)
        : (_newBusinessId(), _newClientSecret());
    writeVirtualStoreIdentity(_restaurantMenuBusinessIdStorageKey, identity.$1);
    writeVirtualStoreIdentity(
      _restaurantMenuClientSecretStorageKey,
      identity.$2,
    );
    return identity;
  }

  static String _newBusinessId() => const Uuid().v4();

  static String _newClientSecret() {
    final random = Random.secure();
    return base64Url
        .encode(List<int>.generate(32, (_) => random.nextInt(256)))
        .replaceAll('=', '');
  }

  static String _stringValue(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value == null) return '';
    if (value is! String) {
      throw FormatException('El campo "$key" no es válido.');
    }
    return value;
  }

  static String _digitsOnly(String value) =>
      value.replaceAll(RegExp(r'\D'), '');
}

class RestaurantMenuCatalogBuilder {
  static const maxMenuBytes = 4 * 1024 * 1024;

  Map<String, Object?> build(
    RestaurantMenuPublicationSettings settings,
    RestaurantMenuState menu, {
    DateTime? updatedAt,
  }) {
    return {
      'format': 'synthetix_restaurant_menu',
      'version': 1,
      'restaurantName': settings.restaurantName.trim(),
      'slogan': settings.slogan.trim(),
      'logo': VirtualStoreCatalogBuilder.imageDataUrl(settings.logoData),
      'colors': {
        'primary': VirtualStoreCatalogBuilder.colorToHex(settings.primaryColor),
        'accent': VirtualStoreCatalogBuilder.colorToHex(settings.accentColor),
      },
      'whatsapp': settings.whatsappNumber.replaceAll(RegExp(r'\D'), ''),
      'whatsappMessage': settings.whatsappMessage.trim(),
      'menu': {
        'categories': [
          for (final category in menu.categories)
            {
              'id': category.id,
              'name': category.name.trim(),
              'description': category.description.trim(),
            },
        ],
        'products': [
          for (final product in menu.products)
            {
              'id': product.id,
              'categoryId': product.categoryId,
              'name': product.name.trim(),
              'description': product.description.trim(),
              'price': product.price,
              'currencyCode': product.currencyCode,
              'isAvailable': product.isAvailable,
              'image': VirtualStoreCatalogBuilder.imageDataUrl(
                product.imageData,
              ),
            },
        ],
      },
    };
  }
}
