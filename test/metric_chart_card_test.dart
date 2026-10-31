import 'package:billing_app/core/widgets/metric_chart_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders the modern metric badge and value', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 340,
            child: MetricChartCard(
              title: 'Ingresos del periodo',
              value: '\$240.00',
              badgeLabel: 'En el periodo',
              color: Color(0xFF18A873),
              trend: [10, 15, 12, 24],
            ),
          ),
        ),
      ),
    );

    expect(find.text('Ingresos del periodo'), findsOneWidget);
    expect(find.text('\$240.00'), findsOneWidget);
    expect(find.text('En el periodo'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders its metric and paints the trend', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 340,
              child: MetricChartCard(
                title: 'Ventas del día',
                value: '\$60',
                color: const Color(0xFF00E676),
                legacyDashboardStyle: true,
                subtitle: '2 transacciones',
                trend: const [2, 8, 4, 10, 6],
                onTap: () => tapped = true,
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Ventas del día'), findsOneWidget);
    expect(find.text('\$60'), findsOneWidget);
    expect(find.text('2 transacciones'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(MetricChartCard),
        matching: find.byWidgetPredicate(
          (widget) => widget is CustomPaint && widget.painter != null,
        ),
      ),
      findsWidgets,
    );
    expect(tester.takeException(), isNull);

    await tester.tap(find.byType(MetricChartCard));
    expect(tapped, isTrue);
  });
}
