import 'dart:convert';

import 'package:billing_app/features/credit/data/credit_pdf.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeDateFormatting('es');
  });

  test('builds a credit contract PDF using only the supplied map', () async {
    final bytes = await buildCreditContractPdf({
      'empresa': {
        'nombre': 'Tienda Demo',
        'direccion': 'Av. Principal',
        'telefono': '55512345',
        'rif': 'J-12345678-9',
      },
      'cliente': {
        'nombre': 'José Núñez',
        'cedulaRif': 'V-12345678',
        'telefono': '55567890',
        'direccion': 'Calle 1',
        'correo': 'jose@example.com',
      },
      'productos': [
        {'cantidad': 2, 'descripcion': 'Café molido', 'precioUnitario': 12.5},
      ],
      'totalVenta': 25,
      'abonoInicial': 5,
      'numeroCuotas': 4,
      'diasPlazo': 15,
      'moneda': 'USD',
      'fechaEmision': DateTime(2026, 10, 31, 10),
      'condiciones': 'Condiciones acordadas por las partes.',
      'representanteNombre': 'Ana Pérez',
      'representanteCargo': 'Administradora',
    });

    expect(latin1.decode(bytes.take(5).toList()), '%PDF-');
    expect(bytes.length, greaterThan(1000));
  });

  test('rejects invalid installment terms', () async {
    await expectLater(
      buildCreditContractPdf({
        'empresa': {'nombre': 'Tienda'},
        'cliente': {'nombre': 'Cliente'},
        'productos': [
          {'cantidad': 1, 'descripcion': 'Producto', 'precioUnitario': 10},
        ],
        'abonoInicial': 0,
        'numeroCuotas': 0,
        'diasPlazo': 30,
      }),
      throwsArgumentError,
    );
  });

  test(
    'builds a contract with interest and a multi-payment schedule',
    () async {
      final bytes = await buildCreditContractPdf({
        'empresa': {'nombre': 'Tienda Demo'},
        'cliente': {'nombre': 'Cliente Demo', 'cedulaRif': 'V-12345678'},
        'productos': [
          {'cantidad': 1, 'descripcion': 'Producto', 'precioUnitario': 120},
        ],
        'totalVenta': 120,
        'abonoInicial': 20,
        'numeroCuotas': 4,
        'diasPlazo': 30,
        'porcentajeCredito': 10,
        'moneda': 'USD',
        'fechaEmision': DateTime(2026, 10, 31),
        'condiciones': 'El cliente acepta el cronograma de pagos.',
        'colorPrincipal': 0xFF183153,
        'colorAcento': 0xFF43A5D5,
        'plantilla': 'Profesional',
      });

      expect(latin1.decode(bytes.take(5).toList()), '%PDF-');
      expect(bytes.length, greaterThan(1500));
    },
  );
}
