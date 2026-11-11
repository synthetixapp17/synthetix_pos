import 'dart:convert';

import 'package:http/http.dart' as http;

class LiveExchangeRate {
  final String source;
  final double vesPerUnit;
  final DateTime updatedAt;

  const LiveExchangeRate({
    required this.source,
    required this.vesPerUnit,
    required this.updatedAt,
  });
}

class ExchangeRatesService {
  final http.Client _client;
  final bool _ownsClient;

  static const _binanceP2pUrl =
      'https://p2p.binance.com/bapi/c2c/v2/friendly/c2c/adv/search';

  ExchangeRatesService({http.Client? client})
    : _client = client ?? http.Client(),
      _ownsClient = client == null;

  Future<Map<String, LiveExchangeRate>> fetchRates() async {
    final responses = await Future.wait([
      _fetchJson('https://ve.dolarapi.com/v1/dolares'),
      _fetchJson('https://ve.dolarapi.com/v1/euros'),
    ]);
    return parseResponses(dollars: responses[0], euros: responses[1]);
  }

  Future<LiveExchangeRate> fetchBinanceRate() async {
    final responses = await Future.wait([
      _fetchBinanceSide('BUY'),
      _fetchBinanceSide('SELL'),
    ]);
    return parseBinanceResponses(buy: responses[0], sell: responses[1]);
  }

  Future<List<dynamic>> _fetchJson(String url) async {
    final response = await _client
        .get(Uri.parse(url))
        .timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) {
      throw Exception(
        'El servicio de tasas respondió con el código ${response.statusCode}.',
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! List) {
      throw const FormatException(
        'El servicio de tasas devolvió un formato inválido.',
      );
    }
    return decoded;
  }

  Future<Object?> _fetchBinanceSide(String tradeType) async {
    final response = await _client
        .post(
          Uri.parse(_binanceP2pUrl),
          headers: const {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'asset': 'USDT',
            'fiat': 'VES',
            'tradeType': tradeType,
            'page': 1,
            'rows': 10,
            'payTypes': [],
            'countries': [],
            'proMerchantAds': false,
            'shieldMerchantAds': false,
            'filterType': 'all',
            'periods': [],
            'additionalKycVerifyFilter': 0,
            'publisherType': null,
          }),
        )
        .timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) {
      throw Exception(
        'Binance P2P respondió con el código ${response.statusCode}.',
      );
    }
    return jsonDecode(response.body);
  }

  static Map<String, LiveExchangeRate> parseResponses({
    required List<dynamic> dollars,
    required List<dynamic> euros,
  }) {
    final result = <String, LiveExchangeRate>{};
    for (final item in dollars) {
      final quote = _parseQuote(item);
      if (quote == null) continue;
      final source = switch (quote.source.toLowerCase()) {
        'oficial' => 'BCV',
        'paralelo' => 'Paralelo',
        _ => null,
      };
      if (source != null) result[source] = quote.rate;
    }
    for (final item in euros) {
      final quote = _parseQuote(item);
      if (quote != null && quote.source.toLowerCase() == 'oficial') {
        result['Euro'] = quote.rate;
      }
    }
    if (!result.containsKey('BCV') ||
        !result.containsKey('Paralelo') ||
        !result.containsKey('Euro')) {
      throw const FormatException(
        'No se recibieron todas las tasas oficiales esperadas.',
      );
    }
    return result;
  }

  static LiveExchangeRate parseBinanceResponses({
    required Object? buy,
    required Object? sell,
  }) {
    final buyMedian = _parseBinanceMedian(buy);
    final sellMedian = _parseBinanceMedian(sell);
    return LiveExchangeRate(
      source: 'Binance P2P',
      vesPerUnit: (buyMedian + sellMedian) / 2,
      updatedAt: DateTime.now(),
    );
  }

  static double _parseBinanceMedian(Object? response) {
    if (response is! Map ||
        (response['code'] != null && response['code'] != '000000') ||
        response['data'] is! List) {
      throw const FormatException(
        'Binance P2P devolvió una respuesta inválida.',
      );
    }
    final prices = <double>[];
    for (final item in response['data'] as List) {
      if (item is! Map || item['adv'] is! Map) continue;
      final price = double.tryParse(
        (item['adv'] as Map)['price']?.toString() ?? '',
      );
      if (price != null && price.isFinite && price > 0) prices.add(price);
    }
    if (prices.isEmpty) {
      throw const FormatException(
        'Binance P2P no devolvió ofertas válidas para USDT/VES.',
      );
    }
    prices.sort();
    final middle = prices.length ~/ 2;
    return prices.length.isOdd
        ? prices[middle]
        : (prices[middle - 1] + prices[middle]) / 2;
  }

  static ({String source, LiveExchangeRate rate})? _parseQuote(Object? item) {
    if (item is! Map) return null;
    final source = item['fuente'];
    final rate = item['promedio'];
    final updatedAt = DateTime.tryParse(
      item['fechaActualizacion']?.toString() ?? '',
    );
    if (source is! String ||
        rate is! num ||
        !rate.toDouble().isFinite ||
        rate <= 0 ||
        updatedAt == null) {
      return null;
    }
    return (
      source: source,
      rate: LiveExchangeRate(
        source: 'DolarApi',
        vesPerUnit: rate.toDouble(),
        updatedAt: updatedAt,
      ),
    );
  }

  void close() {
    if (_ownsClient) _client.close();
  }
}
