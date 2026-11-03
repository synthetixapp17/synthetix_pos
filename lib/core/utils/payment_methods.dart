import '../data/hive_database.dart';

const paymentMethodsSettingKey = 'payment_methods';

const paymentMethodOptions = [
  'Efectivo',
  'Transferencia',
  'Pago móvil',
  'Tarjeta',
  'Otro',
];

List<String> loadPaymentMethods() {
  final storedMethods = HiveDatabase.settingsBox.get(paymentMethodsSettingKey);
  if (storedMethods is List) {
    final methods = <String>[];
    final seen = <String>{};
    for (final item in storedMethods) {
      if (item is! String) continue;
      final method = item.trim();
      if (method.isNotEmpty && seen.add(method.toLowerCase())) {
        methods.add(method);
      }
    }
    if (methods.isNotEmpty) return methods;
  }
  return paymentMethodOptions;
}
