import 'package:billing_app/features/dashboard/presentation/utils/dashboard_greeting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('greets the user according to the local time of day', () {
    expect(dashboardGreeting(DateTime(2026, 11, 9, 5)), 'Buenos días');
    expect(dashboardGreeting(DateTime(2026, 11, 9, 11, 59)), 'Buenos días');
    expect(dashboardGreeting(DateTime(2026, 11, 9, 12)), 'Buenas tardes');
    expect(dashboardGreeting(DateTime(2026, 11, 9, 19, 59)), 'Buenas tardes');
    expect(dashboardGreeting(DateTime(2026, 11, 9, 20)), 'Buenas noches');
    expect(dashboardGreeting(DateTime(2026, 11, 9, 4, 59)), 'Buenas noches');
  });
}
