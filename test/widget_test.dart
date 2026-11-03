import 'package:billing_app/core/widgets/web_app_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders the desktop POS navigation', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: WebAppShell(
          location: '/',
          child: Center(child: Text('Dashboard')),
        ),
      ),
    );

    expect(find.text('Synthetix POS'), findsOneWidget);
    expect(find.text('Resumen'), findsOneWidget);
    expect(find.text('Punto de venta'), findsOneWidget);
    expect(find.text('Inventario'), findsOneWidget);
    expect(find.text('Clientes'), findsOneWidget);
    expect(find.text('Reportes'), findsOneWidget);
    expect(find.text('Configuración'), findsOneWidget);
    expect(find.text('Dashboard'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
