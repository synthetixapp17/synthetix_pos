import '../data/hive_database.dart';

class ReceiptPreferences {
  static const showAddressKey = 'receipt_show_address';
  static const showPhoneKey = 'receipt_show_phone';
  static const showDateKey = 'receipt_show_date';
  static const showBarcodeKey = 'receipt_show_barcode';
  static const showUnitPricesKey = 'receipt_show_unit_prices';
  static const showRifKey = 'receipt_show_rif';
  static const showInvoiceQrKey = 'receipt_show_invoice_qr';
  static const footerTextKey = 'receipt_footer_text';

  static bool get showAddress =>
      HiveDatabase.settingsBox.get(showAddressKey, defaultValue: true) as bool;
  static bool get showPhone =>
      HiveDatabase.settingsBox.get(showPhoneKey, defaultValue: true) as bool;
  static bool get showDate =>
      HiveDatabase.settingsBox.get(showDateKey, defaultValue: true) as bool;
  static bool get showBarcode =>
      HiveDatabase.settingsBox.get(showBarcodeKey, defaultValue: false) as bool;
  static bool get showUnitPrices =>
      HiveDatabase.settingsBox.get(showUnitPricesKey, defaultValue: true)
          as bool;
  static bool get showRif =>
      HiveDatabase.settingsBox.get(showRifKey, defaultValue: true) as bool;
  static bool get showInvoiceQr =>
      HiveDatabase.settingsBox.get(showInvoiceQrKey, defaultValue: true)
          as bool;
  static String? get footerText =>
      HiveDatabase.settingsBox.get(footerTextKey) as String?;
}
