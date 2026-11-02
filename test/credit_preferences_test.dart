import 'dart:io';

import 'package:billing_app/core/data/hive_database.dart';
import 'package:billing_app/features/credit/data/credit_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('credit-preferences-');
    Hive.init(directory.path);
    await Hive.openBox(HiveDatabase.settingsBoxName);
  });

  tearDown(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  test(
    'saves the selected contract template and colors for future PDFs',
    () async {
      await CreditPreferences.save(
        enabled: true,
        template: 'Minimal',
        primaryColor: 0xFF183153,
        accentColor: 0xFF43A5D5,
        terms: 'Condiciones guardadas.',
      );

      expect(CreditPreferences.enabled, isTrue);
      expect(CreditPreferences.template, 'Minimal');
      expect(CreditPreferences.primaryColor, 0xFF183153);
      expect(CreditPreferences.accentColor, 0xFF43A5D5);
      expect(CreditPreferences.terms, 'Condiciones guardadas.');
    },
  );
}
