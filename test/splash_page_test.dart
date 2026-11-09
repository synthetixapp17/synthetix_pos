import 'package:billing_app/features/splash/presentation/pages/splash_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows the welcome presentation and continues on tap', (
    tester,
  ) async {
    var continued = false;

    await tester.pumpWidget(
      MaterialApp(home: SplashPage(onContinue: () => continued = true)),
    );

    expect(find.text('Synthetix POS'), findsOneWidget);
    expect(find.text('Todo tu negocio, en un solo lugar.'), findsOneWidget);
    expect(find.text('Ingresar a la plataforma'), findsOneWidget);

    await tester.ensureVisible(find.text('Ingresar a la plataforma'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ingresar a la plataforma'));

    expect(continued, isTrue);
    expect(tester.takeException(), isNull);
  });
}
