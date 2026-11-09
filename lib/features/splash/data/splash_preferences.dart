import '../../../../core/data/hive_database.dart';

class SplashPreferences {
  static const imageKey = 'splash_image_base64';

  static String? get imageData =>
      HiveDatabase.settingsBox.get(imageKey) as String?;

  static Future<void> saveImage(String base64Image) =>
      HiveDatabase.settingsBox.put(imageKey, base64Image);

  static Future<void> clearImage() =>
      HiveDatabase.settingsBox.delete(imageKey);
}
