class ReceiptQr {
  static const _salePrefix = 'synthetix-sale:';

  static const privateReceiptData =
      'Comprobante privado. La información de la venta solo está disponible '
      'en el dispositivo donde se guardó.';

  static String saleQrData(String saleId) =>
      '$_salePrefix${Uri.encodeComponent(saleId)}';

  static String? saleIdFromData(String data) {
    final value = data.trim();
    if (value.isEmpty || value == privateReceiptData) return null;

    if (value.toLowerCase().startsWith(_salePrefix)) {
      try {
        return Uri.decodeComponent(value.substring(_salePrefix.length));
      } on FormatException {
        return null;
      }
    }

    final uri = Uri.tryParse(value);
    if (uri != null) {
      final querySaleId = uri.queryParameters['saleId'];
      if (querySaleId != null && querySaleId.isNotEmpty) return querySaleId;

      final fragmentQueryIndex = uri.fragment.indexOf('?');
      if (fragmentQueryIndex >= 0) {
        final fragmentQuery = uri.fragment.substring(fragmentQueryIndex + 1);
        try {
          final fragmentSaleId = Uri.splitQueryString(fragmentQuery)['saleId'];
          if (fragmentSaleId != null && fragmentSaleId.isNotEmpty) {
            return fragmentSaleId;
          }
        } on FormatException {
          return null;
        }
      }

      if (uri.hasScheme || value.startsWith('#/')) return null;
    }

    return value;
  }
}
