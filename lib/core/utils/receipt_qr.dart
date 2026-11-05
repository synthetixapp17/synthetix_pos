class ReceiptQr {
  static const _host = 'synthetixapp17.github.io';
  static const _basePath = '/synthetix_pos/';

  static String saleUrl(String saleId) =>
      '${Uri.https(_host, _basePath)}'
      '#/reports?saleId=${Uri.encodeQueryComponent(saleId)}';
}
