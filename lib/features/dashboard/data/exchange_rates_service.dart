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
