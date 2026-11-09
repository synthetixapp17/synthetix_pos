import 'dart:io';

import 'package:billing_app/core/data/hive_database.dart';
import 'package:billing_app/core/utils/receipt_preferences.dart';
import 'package:billing_app/features/splash/data/splash_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('app-preferences-');
    Hive.init(directory.path);
    await Hive.openBox(HiveDatabase.settingsBoxName);
  });

  tearDown(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  test(
    'saves supported printer paper sizes and their receipt widths',
    () async {
      expect(ReceiptPreferences.paperWidth, 58);
      expect(ReceiptPreferences.paperColumns, 32);

      await ReceiptPreferences.savePaperWidth(80);

      expect(ReceiptPreferences.paperWidth, 80);
      expect(ReceiptPreferences.paperColumns, 48);

      expect(
        () => ReceiptPreferences.savePaperWidth(76),
        throwsA(isA<ArgumentError>()),
      );
      expect(ReceiptPreferences.paperWidth, 80);
    },
  );

  test('saves and removes the custom splash image', () async {
    await SplashPreferences.saveImage('aW1hZ2UtZGF0YQ==');

    expect(SplashPreferences.imageData, 'aW1hZ2UtZGF0YQ==');

    await SplashPreferences.clearImage();

    expect(SplashPreferences.imageData, isNull);
  });
}
