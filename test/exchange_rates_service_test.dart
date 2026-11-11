import 'package:billing_app/features/dashboard/data/exchange_rates_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('maps official, parallel, and euro quotes to calculator sources', () {
    final rates = ExchangeRatesService.parseResponses(
      dollars: [
        {
          'fuente': 'oficial',
          'promedio': 900.5,
          'fechaActualizacion': '2026-11-10T12:00:00-04:00',
        },
        {
          'fuente': 'paralelo',
          'promedio': 1080.25,
          'fechaActualizacion': '2026-11-10T12:30:00Z',
        },
      ],
      euros: [
        {
          'fuente': 'oficial',
          'promedio': 1005.75,
          'fechaActualizacion': '2026-11-10T12:00:00-04:00',
        },
      ],
    );

    expect(rates.keys, containsAll(['BCV', 'Paralelo', 'Euro']));
    expect(rates['BCV']!.vesPerUnit, 900.5);
    expect(rates['Paralelo']!.vesPerUnit, 1080.25);
    expect(rates['Euro']!.vesPerUnit, 1005.75);
    expect(rates['BCV']!.source, 'DolarApi');
  });

  test('rejects incomplete or malformed rate responses', () {
    expect(
      () => ExchangeRatesService.parseResponses(
        dollars: [
          {'fuente': 'oficial', 'promedio': 0, 'fechaActualizacion': 'invalid'},
        ],
        euros: const [],
      ),
      throwsFormatException,
    );
  });

  test(
    'calculates the Binance P2P midpoint from median buy and sell offers',
    () {
      final rate = ExchangeRatesService.parseBinanceResponses(
        buy: {
          'code': '000000',
          'data': [
            {
              'adv': {'price': '100'},
            },
            {
              'adv': {'price': '102'},
            },
            {
              'adv': {'price': '104'},
            },
          ],
        },
        sell: {
          'code': '000000',
          'data': [
            {
              'adv': {'price': '110'},
            },
            {
              'adv': {'price': '112'},
            },
            {
              'adv': {'price': '114'},
            },
          ],
        },
      );

      expect(rate.source, 'Binance P2P');
      expect(rate.vesPerUnit, 107);
    },
  );

  test('rejects Binance P2P responses without valid USDT/VES offers', () {
    expect(
      () => ExchangeRatesService.parseBinanceResponses(
        buy: {
          'code': '000000',
          'data': [
            {
              'adv': {'price': '0'},
            },
          ],
        },
        sell: {'code': '000000', 'data': []},
      ),
      throwsFormatException,
    );
  });
}
