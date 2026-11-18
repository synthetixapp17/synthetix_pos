import 'dart:convert';
import 'dart:math';

import 'package:uuid/uuid.dart';

import '../../../core/utils/app_currency.dart';
import '../../../core/data/hive_database.dart';
import '../../product/data/models/product_model.dart';
import 'virtual_store_identity_storage.dart';

const virtualStoreSettingsKey = 'virtual_store_settings';
const virtualStoreWorkerUrl =
    'https://synthetix-pos.synthetixapp17.workers.dev/';
const virtualStoreRateStorageKey = 'multi_rate_calculator_rates';
const _businessIdStorageKey = 'virtual_store_business_id';
const _clientSecretStorageKey = 'virtual_store_client_secret';

String _newBusinessId() => const Uuid().v4();

String _newClientSecret() {
  final random = Random.secure();
  return base64Url
      .encode(List<int>.generate(32, (_) => random.nextInt(256)))
      .replaceAll('=', '');
}

(String, String) _getOrCreateIdentity(String businessId, String clientSecret) {
  final storedBusinessId = readVirtualStoreIdentity(_businessIdStorageKey);
  final storedClientSecret = readVirtualStoreIdentity(_clientSecretStorageKey);
  final resolvedBusinessId = storedBusinessId ?? businessId;
  final resolvedClientSecret = storedClientSecret ?? clientSecret;
  final hasValidBusinessId = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    caseSensitive: false,
  ).hasMatch(resolvedBusinessId);
  final hasValidClientSecret = RegExp(
    r'^[A-Za-z0-9_-]{43}$',
  ).hasMatch(resolvedClientSecret);
  final identity = hasValidBusinessId && hasValidClientSecret
      ? (resolvedBusinessId.toLowerCase(), resolvedClientSecret)
      : (_newBusinessId(), _newClientSecret());
  writeVirtualStoreIdentity(_businessIdStorageKey, identity.$1);
  writeVirtualStoreIdentity(_clientSecretStorageKey, identity.$2);
  return identity;
}

class VirtualStoreSettings {
  final String businessName;
  final String slogan;
  final String whatsappNumber;
  final String whatsappMessage;
  final String logo;
  final String banner;
  final int primaryColor;
  final int accentColor;
  final bool showUsdReference;
  final String exchangeRateSource;
  final String businessId;
  final String clientSecret;
  final DateTime? lastPublishedAt;
  final String publishedUrl;

  const VirtualStoreSettings({
    this.businessName = '',
    this.slogan = '',
    this.whatsappNumber = '',
    this.whatsappMessage = '',
    this.logo = '',
    this.banner = '',
    this.primaryColor = 0xFF00695C,
    this.accentColor = 0xFFFFB300,
    this.showUsdReference = false,
    this.exchangeRateSource = 'USDT',
    this.businessId = '',
    this.clientSecret = '',
    this.lastPublishedAt,
    this.publishedUrl = '',
  });

  factory VirtualStoreSettings.load() {
    final stored = HiveDatabase.settingsBox.get(virtualStoreSettingsKey);
    if (stored is String) {
      final decoded = jsonDecode(stored);
      if (decoded is! Map || decoded.keys.any((key) => key is! String)) {
        throw const FormatException(
          'La configuración de la tienda virtual está dañada.',
        );
      }
      return VirtualStoreSettings.fromJson(decoded.cast<String, dynamic>());
    }

    final shop = HiveDatabase.shopBox.get('shop_details');
    final (businessId, clientSecret) = _getOrCreateIdentity('', '');
    return VirtualStoreSettings(
      businessName: shop?.name ?? '',
      whatsappNumber: shop?.phoneNumber ?? '',
      businessId: businessId,
      clientSecret: clientSecret,
    );
  }

  factory VirtualStoreSettings.fromJson(Map<String, dynamic> json) {
    final primaryColor = json['primaryColor'];
    final accentColor = json['accentColor'];
    final showUsdReference = json['showUsdReference'];
    final lastPublishedAt = json['lastPublishedAt'];
    if ((primaryColor != null && primaryColor is! int) ||
        (accentColor != null && accentColor is! int) ||
        (showUsdReference != null && showUsdReference is! bool) ||
        (lastPublishedAt != null && lastPublishedAt is! String)) {
      throw const FormatException(
        'Hay valores inválidos en la configuración de la tienda virtual.',
      );
    }
    final identity = _getOrCreateIdentity(
      _stringValue(json, 'businessId'),
      _stringValue(json, 'clientSecret'),
    );
    return VirtualStoreSettings(
      businessName: _stringValue(json, 'businessName'),
      slogan: _stringValue(json, 'slogan'),
      whatsappNumber: _stringValue(json, 'whatsappNumber'),
      whatsappMessage: _stringValue(json, 'whatsappMessage'),
      logo: _stringValue(json, 'logo'),
      banner: _stringValue(json, 'banner'),
      primaryColor: primaryColor as int? ?? 0xFF00695C,
      accentColor: accentColor as int? ?? 0xFFFFB300,
      showUsdReference: showUsdReference as bool? ?? false,
      exchangeRateSource: _stringValue(json, 'exchangeRateSource').isEmpty
          ? 'USDT'
          : _stringValue(json, 'exchangeRateSource'),
      businessId: identity.$1,
      clientSecret: identity.$2,
      lastPublishedAt: lastPublishedAt == null
          ? null
          : DateTime.tryParse(lastPublishedAt as String),
      publishedUrl: _stringValue(json, 'publishedUrl'),
    );
  }

  Map<String, Object?> toJson() => {
    'businessName': businessName,
    'slogan': slogan,
    'whatsappNumber': whatsappNumber,
    'whatsappMessage': whatsappMessage,
    'logo': logo,
    'banner': banner,
    'primaryColor': primaryColor,
    'accentColor': accentColor,
    'showUsdReference': showUsdReference,
    'exchangeRateSource': exchangeRateSource,
    'businessId': businessId,
    'clientSecret': clientSecret,
    'lastPublishedAt': lastPublishedAt?.toIso8601String(),
    'publishedUrl': publishedUrl,
  };

  static double? platformVesPerUsd(String source) {
    final rates = HiveDatabase.settingsBox.get(virtualStoreRateStorageKey);
    if (rates is Map) {
      final savedRate = rates[source];
      if (savedRate is Map) {
        final value = savedRate['value'];
        if (value is num && value.isFinite && value > 0) {
          return value.toDouble();
        }
      }
    }

    if (source == 'App') {
      try {
        final rate = AppCurrency.rateFor('VES');
        return rate.isFinite && rate > 0 ? rate : null;
      } on StateError {
        return null;
      }
    }
    return null;
  }

  static String _stringValue(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value == null) return '';
    if (value is! String) {
      throw FormatException('El campo "$key" no es válido.');
    }
    return value;
  }
}

class VirtualStoreCatalogBuilder {
  static const maxCatalogBytes = 4 * 1024 * 1024;

  Map<String, Object?> build(
    VirtualStoreSettings settings,
    Iterable<ProductModel> products, {
    DateTime? updatedAt,
  }) {
    return {
      'schemaVersion': 1,
      'updatedAt': (updatedAt ?? DateTime.now()).toUtc().toIso8601String(),
      'business': {
        'id': settings.businessId,
        'name': settings.businessName,
        'slogan': settings.slogan,
        'whatsapp': settings.whatsappNumber,
        'whatsappMessage': settings.whatsappMessage.trim(),
        'logo': _imageDataUrl(settings.logo),
        'banner': _imageDataUrl(settings.banner),
        'showUsdReference': settings.showUsdReference,
        'vesPerUsd': settings.showUsdReference
            ? _requiredVesRate(settings)
            : null,
        'colors': {
          'primary': colorToHex(settings.primaryColor),
          'accent': colorToHex(settings.accentColor),
        },
      },
      'products': [
        for (final product in products)
          {
            'id': product.id,
            'name': product.name,
            'description': product.description,
            'category': product.category,
            'price': settings.showUsdReference
                ? _convertToUsd(product.price, product.currencyCode)
                : product.price,
            'currencyCode': settings.showUsdReference
                ? AppCurrency.baseCode
                : product.currencyCode,
            'stock': product.stock,
            'unitLabel': product.unitLabel,
            'image': _imageDataUrl(product.imageData),
            'variants': product.variants
                .map(
                  (variant) => {
                    ...variant.toJson(),
                    if (settings.showUsdReference)
                      'price': _convertToUsd(
                        variant.price,
                        product.currencyCode,
                      ),
                  },
                )
                .toList(),
          },
      ],
    };
  }

  static double _requiredVesRate(VirtualStoreSettings settings) {
    final rate = VirtualStoreSettings.platformVesPerUsd(
      settings.exchangeRateSource,
    );
    if (rate == null) {
      throw FormatException(
        'No hay una tasa VES válida guardada para ${settings.exchangeRateSource}. '
        'Actualízala en la calculadora de tasas e inténtalo de nuevo.',
      );
    }
    return rate;
  }

  static double _convertToUsd(double amount, String currencyCode) {
    if (currencyCode == AppCurrency.baseCode) return amount;
    try {
      final rate = AppCurrency.rateFor(currencyCode);
      final converted = amount / rate;
      if (!converted.isFinite) throw const FormatException();
      return converted;
    } on StateError {
      throw FormatException(
        'No se puede convertir $currencyCode a USD con las tasas configuradas.',
      );
    }
  }

  static String colorToHex(int color) =>
      '#${color.toRadixString(16).padLeft(8, '0').substring(2)}';

  static String? _imageDataUrl(String? source) {
    if (source == null || source.isEmpty) return null;
    if (source.startsWith('data:image/')) return source;
    if (Uri.tryParse(source)?.scheme == 'https') return source;

    final bytes = base64Decode(source);
    final mimeType = _imageMimeType(bytes);
    return 'data:$mimeType;base64,$source';
  }

  static String _imageMimeType(List<int> bytes) {
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return 'image/png';
    }
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return 'image/jpeg';
    }
    if (bytes.length >= 6 && String.fromCharCodes(bytes.take(3)) == 'GIF') {
      return 'image/gif';
    }
    if (bytes.length >= 12 &&
        String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
        String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP') {
      return 'image/webp';
    }
    throw const FormatException('Hay una imagen de producto inválida.');
  }
}
