import 'package:hive/hive.dart';

part 'app_settings.g.dart';

@HiveType(typeId: 4)
class CurrencyConfig {
  @HiveField(0)
  final String code;
  @HiveField(1)
  final String symbol;
  @HiveField(2)
  final bool isBase;
  @HiveField(3)
  final double rate;

  const CurrencyConfig({
    required this.code,
    required this.symbol,
    required this.isBase,
    required this.rate,
  });

  CurrencyConfig copyWith({
    String? code,
    String? symbol,
    bool? isBase,
    double? rate,
  }) => CurrencyConfig(
    code: code ?? this.code,
    symbol: symbol ?? this.symbol,
    isBase: isBase ?? this.isBase,
    rate: rate ?? this.rate,
  );
}

@HiveType(typeId: 5)
class AppSettings {
  @HiveField(0)
  final List<CurrencyConfig> currencies;

  const AppSettings({required this.currencies});
}
