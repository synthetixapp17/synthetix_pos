import 'dart:convert';

import '../../../core/data/hive_database.dart';
import '../domain/entities/credit_record.dart';

class CreditRepository {
  static List<CreditRecord> getAll() {
    final records =
        HiveDatabase.creditBox.values
            .map(
              (source) => CreditRecord.fromJson(
                jsonDecode(source) as Map<String, dynamic>,
              ),
            )
            .toList()
          ..sort(
            (first, second) => second.createdAt.compareTo(first.createdAt),
          );
    return records;
  }

  static CreditRecord? getById(String id) {
    final source = HiveDatabase.creditBox.get(id);
    if (source == null) return null;
    return CreditRecord.fromJson(jsonDecode(source) as Map<String, dynamic>);
  }

  static Future<void> save(CreditRecord record) =>
      HiveDatabase.creditBox.put(record.id, jsonEncode(record.toJson()));

  static Future<void> addPayment(String id, CreditPayment payment) async {
    final record = getById(id);
    if (record == null) {
      throw StateError('No se encontró la compra a crédito.');
    }
    if (payment.amount <= 0 || payment.amount > record.balance) {
      throw ArgumentError(
        'El abono debe ser mayor que cero y no superar el saldo.',
      );
    }
    await save(record.copyWith(payments: [...record.payments, payment]));
  }
}
