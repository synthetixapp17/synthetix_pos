import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:zxing2/zxing2.dart' show NotFoundException;

import '../../../../core/data/hive_database.dart';
import '../../../../core/utils/app_currency.dart';
import '../../../../core/utils/printer_helper.dart';
import '../../../../core/utils/receipt_preferences.dart';
import '../../../../core/utils/receipt_qr.dart';
import '../../../../core/utils/receipt_qr_image_decoder.dart';
import '../../../../core/widgets/metric_chart_card.dart';
import '../../../shop/data/repositories/shop_repository_impl.dart';
import '../../../billing/data/whatsapp_sale_receipt_message.dart';
import '../../../billing/data/receipt_image.dart';
import '../../../shop/domain/entities/shop.dart';
import '../../domain/entities/sale_record.dart';
import '../bloc/reports_bloc.dart';

enum _Grouping { day, week, month }

class ReportsPage extends StatefulWidget {
  final bool showToday;
  final String? saleId;

  const ReportsPage({super.key, this.showToday = false, this.saleId});

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  late DateTime _from;
  late DateTime _to;
  _Grouping _grouping = _Grouping.day;
  String? _currencyFilterCode;
  final _dateFormat = DateFormat('d MMM', 'es');
  final _monthFormat = DateFormat('MMM yy', 'es');
  final _saleIdController = TextEditingController();
  String? _saleId;
  bool _isPrinting = false;

  @override
  void initState() {
    super.initState();
    _saleId = widget.saleId;
    _saleIdController.text = widget.saleId ?? '';
    final today = DateTime.now();
    _to = DateTime(today.year, today.month, today.day, 23, 59, 59, 999);
    final start = widget.saleId != null
        ? DateTime(1970)
        : widget.showToday
        ? today
        : today.subtract(const Duration(days: 29));
    _from = DateTime(start.year, start.month, start.day);
    _load();
  }

  @override
  void dispose() {
    _saleIdController.dispose();
    super.dispose();
  }

  void _load() {
    if (_saleId != null) {
      final today = DateTime.now();
      _from = DateTime(1970);
      _to = DateTime(today.year, today.month, today.day, 23, 59, 59, 999);
    }
    context.read<ReportsBloc>().add(LoadReportsEvent(from: _from, to: _to));
  }

  void _searchSale(String value) {
    final saleId = ReceiptQr.saleIdFromData(value);
    if (saleId == null || saleId.isEmpty) return;
    _saleIdController.text = saleId;
    setState(() => _saleId = saleId);
    _load();
  }

  Future<void> _scanSaleQr() async {
    final data = await context.push<String>('/scan-code');
    if (!mounted || data == null) return;
    _searchScannedQr(data);
  }

  Future<void> _pickSaleQrImage() async {
    try {
      final image = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 2000,
        maxHeight: 2000,
      );
      if (image == null || !mounted) return;
      final data = ReceiptQrImageDecoder.decode(await image.readAsBytes());
      if (!mounted) return;
      _searchScannedQr(data);
    } on NotFoundException {
      _showMessage('No se encontró un código QR legible en la imagen.');
    } on FormatException catch (error) {
      _showMessage('No se pudo leer la imagen: ${error.message}');
    } catch (error) {
      _showMessage('No se pudo leer el QR de la imagen: $error');
    }
  }

  void _searchScannedQr(String data) {
    final saleId = ReceiptQr.saleIdFromData(data);
    if (saleId == null || saleId.isEmpty) {
      _showMessage('El QR no contiene un folio de venta válido.');
      return;
    }
    _searchSale(saleId);
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _ensurePrinterConnected(PrinterHelper printer) async {
    if (await printer.checkConnection()) return;
    final savedMac = HiveDatabase.settingsBox.get('printer_mac');
    if (savedMac is! String || savedMac.isEmpty) {
      throw const PrinterException(
        'La impresora no está conectada y no hay una impresora guardada.',
      );
    }
    if (!await printer.connect(savedMac)) {
      throw const PrinterException(
        'No se pudo conectar automáticamente con la impresora. '
        'Comprueba que esté encendida y vinculada.',
      );
    }
  }

  Future<void> _reprintSale(SaleRecord sale) async {
    final action = await showDialog<_SaleAction>(
      context: context,
      builder: (context) => _SaleDetailsDialog(sale: sale),
    );
    if (!mounted || action == null || _isPrinting) return;
    if (action == _SaleAction.whatsapp) {
      await _shareSaleOnWhatsApp(sale);
      return;
    }

    setState(() => _isPrinting = true);
    try {
      final printer = PrinterHelper();
      await _ensurePrinterConnected(printer);
      final shop = HiveDatabase.shopBox.get(ShopRepositoryImpl.shopKey);
      final printed = await printer.printReceipt(
        shopName: shop == null || shop.name.isEmpty ? 'MI TIENDA' : shop.name,
        address1: shop?.addressLine1 ?? '',
        address2: shop?.addressLine2 ?? '',
        phone: shop?.phoneNumber ?? '',
        rif: shop?.rif ?? '',
        qrData: ReceiptQr.saleQrData(sale.id),
        customerName: sale.customerName,
        logoData: shop?.logoData,
        items: sale.lines
            .map(
              (line) => {
                'name':
                    '${line.productName}${line.variationLabel.isEmpty ? '' : ' · ${line.variationLabel}'}',
                'qty': '${line.displayQuantity} ${line.unitLabel}',
                'price': line.unitPrice,
                'total': line.total,
                'barcode': line.barcode,
              },
            )
            .toList(),
        total: sale.total,
        footer: ReceiptPreferences.footerText ?? shop?.footerText ?? '',
        currencyCode: sale.currencyCode,
        exchangeRate: sale.exchangeRate,
        paymentMethod: sale.paymentMethod,
        amountTendered: sale.amountTendered,
        changeAmount: sale.changeAmount,
        soldAt: sale.soldAt,
        showAddress: ReceiptPreferences.showAddress,
        showPhone: ReceiptPreferences.showPhone,
        showRif: ReceiptPreferences.showRif,
        showInvoiceQr: ReceiptPreferences.showInvoiceQr,
        showDate: ReceiptPreferences.showDate,
        showBarcode: ReceiptPreferences.showBarcode,
        showUnitPrices: ReceiptPreferences.showUnitPrices,
      );
      if (!printed) {
        throw const PrinterException('No se pudo reimprimir el ticket.');
      }
      _showMessage('Ticket de ${sale.id} enviado a la impresora.');
    } catch (error) {
      _showMessage(
        error is PrinterException
            ? error.message
            : 'No se pudo reimprimir el ticket: $error',
      );
    } finally {
      if (mounted) setState(() => _isPrinting = false);
    }
  }

  Future<void> _shareSaleOnWhatsApp(SaleRecord sale) async {
    try {
      final shop = HiveDatabase.shopBox.get(ShopRepositoryImpl.shopKey);
      final image = await ReceiptImage.build(
        sale: sale,
        shopName: shop == null || shop.name.isEmpty ? 'MI TIENDA' : shop.name,
        address: [
          shop?.addressLine1 ?? '',
          shop?.addressLine2 ?? '',
        ].where((line) => line.trim().isNotEmpty).join(', '),
        shopPhone: shop?.phoneNumber ?? '',
        rif: shop?.rif ?? '',
        qrData: ReceiptQr.saleQrData(sale.id),
        logoData: shop?.logoData,
        footer: ReceiptPreferences.footerText ?? shop?.footerText ?? '',
        showAddress: ReceiptPreferences.showAddress,
        showPhone: ReceiptPreferences.showPhone,
        showRif: ReceiptPreferences.showRif,
        showInvoiceQr: ReceiptPreferences.showInvoiceQr,
        showDate: ReceiptPreferences.showDate,
        showBarcode: ReceiptPreferences.showBarcode,
        showUnitPrices: ReceiptPreferences.showUnitPrices,
      );
      final filename =
          'ticket-${sale.id.substring(0, sale.id.length > 8 ? 8 : sale.id.length)}.png';
      final result = await SharePlus.instance.share(
        ShareParams(
          title: 'Comprobante de venta',
          text: buildWhatsappSaleReceiptMessage(
            sale: sale,
            shop: shop ?? const Shop(),
          ),
          files: [XFile.fromData(image, name: filename, mimeType: 'image/png')],
          fileNameOverrides: [filename],
        ),
      );
      if (result.status == ShareResultStatus.unavailable) {
        _showMessage('El sistema no pudo abrir WhatsApp para compartir.');
      }
    } catch (error) {
      _showMessage('No se pudo preparar el ticket para compartir: $error');
    }
  }

  Future<void> _printCashClosing() async {
    final now = DateTime.now();
    final allSales = HiveDatabase.salesBox.values
        .map((sale) => sale.toEntity())
        .toList();
    final closing = await showDialog<_CashClosingSelection>(
      context: context,
      builder: (context) => _CashClosingPreviewDialog(
        sales: allSales,
        initialDate: DateTime(now.year, now.month, now.day),
      ),
    );
    if (!mounted || closing == null || _isPrinting) return;
    final sales = closing.sales;

    setState(() => _isPrinting = true);
    try {
      final printer = PrinterHelper();
      await _ensurePrinterConnected(printer);
      final totalsByCurrency = <String, double>{};
      final salesByCurrency = <String, int>{};
      final totalsByPaymentMethod = <String, double>{};
      final salesByPaymentMethod = <String, int>{};
      var unitsSold = 0.0;
      var totalUsd = 0.0;
      for (final sale in sales) {
        totalsByCurrency.update(
          sale.currencyCode,
          (total) => total + sale.total,
          ifAbsent: () => sale.total,
        );
        salesByCurrency.update(
          sale.currencyCode,
          (count) => count + 1,
          ifAbsent: () => 1,
        );
        unitsSold += sale.lines.fold<double>(
          0.0,
          (total, line) => total + line.quantity,
        );
        totalUsd += sale.total / sale.exchangeRate;
        totalsByPaymentMethod.update(
          sale.paymentMethod,
          (total) => total + sale.total / sale.exchangeRate,
          ifAbsent: () => sale.total / sale.exchangeRate,
        );
        salesByPaymentMethod.update(
          sale.paymentMethod,
          (count) => count + 1,
          ifAbsent: () => 1,
        );
      }

      final shop = HiveDatabase.shopBox.get(ShopRepositoryImpl.shopKey);
      final separator = '-' * ReceiptPreferences.paperColumns;
      final buffer = StringBuffer()
        ..writeln('CIERRE DE CAJA')
        ..writeln(shop == null || shop.name.isEmpty ? 'MI TIENDA' : shop.name)
        ..writeln(DateFormat('dd/MM/yyyy', 'es').format(closing.date))
        ..writeln(separator)
        ..writeln('VENTAS: ${sales.length}  UNIDADES: $unitsSold')
        ..writeln(separator);
      for (final sale in sales) {
        buffer
          ..writeln(
            '${DateFormat('HH:mm', 'es').format(sale.soldAt)} '
            '${sale.id} ${AppCurrency.format(sale.total, code: sale.currencyCode)}',
          )
          ..writeln(
            '  ${sale.paymentMethod} · ${sale.customerName ?? 'Sin cliente'}',
          );
      }
      buffer
        ..writeln(separator)
        ..writeln('TOTALES POR MONEDA');
      for (final entry in totalsByCurrency.entries) {
        buffer.writeln(
          '${AppCurrency.format(entry.value, code: entry.key)} '
          '(${salesByCurrency[entry.key]} ventas)',
        );
      }
      buffer
        ..writeln(separator)
        ..writeln('VENTAS POR METODO DE PAGO (REF. USD)');
      for (final entry in totalsByPaymentMethod.entries) {
        buffer.writeln(
          '${entry.key}: ${AppCurrency.formatReference(entry.value)} '
          '(${salesByPaymentMethod[entry.key]} ventas)',
        );
      }
      buffer
        ..writeln(
          'TOTAL REF. USD: ${AppCurrency.format(totalUsd, code: 'USD')}',
        )
        ..writeln(separator)
        ..writeln();
      await printer.printText(buffer.toString());
      _showMessage('Cierre de caja enviado a la impresora.');
    } catch (error) {
      _showMessage(
        error is PrinterException
            ? error.message
            : 'No se pudo imprimir el cierre de caja: $error',
      );
    } finally {
      if (mounted) setState(() => _isPrinting = false);
    }
  }

  SaleRecord? _findSale(List<SaleRecord> sales) {
    final saleId = _saleId;
    if (saleId == null) return null;
    for (final sale in sales) {
      if (sale.id.toLowerCase() == saleId.toLowerCase()) return sale;
    }
    return null;
  }

  void _showMetricDetails({
    required String title,
    required List<SaleRecord> sales,
    bool showProducts = false,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      barrierColor: Colors.black54,
      elevation: 18,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => _ReportMetricDetailsSheet(
        title: title,
        sales: sales,
        showProducts: showProducts,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    AppCurrencyScope.of(context);
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: const Text('Reportes de ventas'),
        actions: [
          IconButton(
            tooltip: 'Cierre de caja del día',
            onPressed: _isPrinting ? null : _printCashClosing,
            icon: _isPrinting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.point_of_sale_rounded),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: IconButton.filledTonal(
              tooltip: 'Escanear QR de factura',
              onPressed: _scanSaleQr,
              icon: const Icon(Icons.qr_code_scanner_rounded),
            ),
          ),
        ],
      ),
      body: BlocConsumer<ReportsBloc, ReportsState>(
        listener: (context, state) {
          if (state.status == ReportsStatus.failure && state.message != null) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(state.message!)));
          }
        },
        builder: (context, state) {
          final reportSales = _currencyFilterCode == null
              ? state.sales
              : state.sales
                    .where((sale) => sale.currencyCode == _currencyFilterCode)
                    .toList();
          final currencyFilterCodes = <String>{
            ...AppCurrency.configuredCurrencies.map(
              (currency) => currency.code,
            ),
            ...state.sales.map((sale) => sale.currencyCode),
            ?_currencyFilterCode,
          }.toList()..sort();
          final groupedSales = _groupSales(reportSales);
          final products = _topProducts(reportSales);
          final categoryStats = _categoryStats(reportSales);
          final totalCategoryUnits = categoryStats.fold<double>(
            0.0,
            (total, category) => total + category.units,
          );
          final currencyCodes =
              reportSales.map((sale) => sale.currencyCode).toSet().toList()
                ..sort();
          final totalsByCurrency = <String, double>{};
          final usdTotalsByCurrency = <String, double>{};
          for (final sale in reportSales) {
            totalsByCurrency.update(
              sale.currencyCode,
              (total) => total + sale.total,
              ifAbsent: () => sale.total,
            );
            usdTotalsByCurrency.update(
              sale.currencyCode,
              (total) => total + sale.total / sale.exchangeRate,
              ifAbsent: () => sale.total / sale.exchangeRate,
            );
          }
          final totalLabel = totalsByCurrency.isEmpty
              ? _currencyFilterCode == null
                    ? AppCurrency.formatConfigured(0)
                    : AppCurrency.format(0, code: _currencyFilterCode!)
              : totalsByCurrency.entries
                    .map(
                      (entry) =>
                          AppCurrency.format(entry.value, code: entry.key),
                    )
                    .join('\n');
          final averageLabel = totalsByCurrency.isEmpty || reportSales.isEmpty
              ? _currencyFilterCode == null
                    ? AppCurrency.formatConfigured(0)
                    : AppCurrency.format(0, code: _currencyFilterCode!)
              : totalsByCurrency.entries
                    .map((entry) {
                      final currencyTransactions = reportSales
                          .where((sale) => sale.currencyCode == entry.key)
                          .length;
                      return AppCurrency.format(
                        entry.value / currencyTransactions,
                        code: entry.key,
                      );
                    })
                    .join('\n');
          final unitsSold = reportSales.fold<double>(
            0.0,
            (total, sale) =>
                total +
                sale.lines.fold<double>(
                  0.0,
                  (saleUnits, line) => saleUnits + line.quantity,
                ),
          );
          final transactionTrend = _groupTransactionCounts(
            reportSales,
          ).map((count) => count.toDouble()).toList();
          final trendCurrencyCode =
              _currencyFilterCode ?? AppCurrency.currentCode;
          final currencyTransactionTrend = _groupCurrencyTransactionCounts(
            reportSales,
            trendCurrencyCode,
          );
          final unitsTrend = _groupUnitCounts(
            reportSales,
          ).map((count) => count.toDouble()).toList();
          final revenueTrend = groupedSales
              .map((bucket) => bucket.amounts[trendCurrencyCode] ?? 0.0)
              .toList();
          final averageTrend = List.generate(groupedSales.length, (index) {
            final count = currencyTransactionTrend[index].toDouble();
            return count == 0 ? 0.0 : revenueTrend[index] / count;
          });
          return RefreshIndicator(
            onRefresh: () async => _load(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              children: [
                _ReportsHeader(
                  dateLabel:
                      '${_dateFormat.format(_from)} – ${_dateFormat.format(_to)}',
                  transactionCount: reportSales.length,
                ),
                const SizedBox(height: 16),
                _SaleLookupCard(
                  controller: _saleIdController,
                  saleId: _saleId,
                  sale: _findSale(state.sales),
                  isLoading: state.status == ReportsStatus.loading,
                  onSearch: _searchSale,
                  onScan: _scanSaleQr,
                  onPickImage: _pickSaleQrImage,
                  onReprint: _reprintSale,
                  isPrinting: _isPrinting,
                ),
                const SizedBox(height: 16),
                _SalesHistoryCard(
                  sales: reportSales,
                  onSaleTap: _reprintSale,
                  isPrinting: _isPrinting,
                ),
                const SizedBox(height: 16),
                _FilterCard(
                  from: _from,
                  to: _to,
                  grouping: _grouping,
                  dateLabel:
                      '${_dateFormat.format(_from)} – ${_dateFormat.format(_to)}',
                  currencyCode: _currencyFilterCode,
                  currencyCodes: currencyFilterCodes,
                  onChooseDates: _chooseDates,
                  onGroupingChanged: (grouping) =>
                      setState(() => _grouping = grouping),
                  onCurrencyChanged: (currencyCode) =>
                      setState(() => _currencyFilterCode = currencyCode),
                ),
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = constraints.maxWidth < 300 ? 1 : 2;
                    final tileWidth = columns == 1
                        ? constraints.maxWidth
                        : (constraints.maxWidth - 12) / 2;
                    return Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        SizedBox(
                          width: tileWidth,
                          child: _SummaryTile(
                            title: 'Ingresos del periodo',
                            value: totalLabel,
                            accent: const Color(0xFF1E9B72),
                            badgeLabel: 'En el periodo',
                            trend: revenueTrend,
                            onTap: () => _showMetricDetails(
                              title: 'Ventas que componen los ingresos',
                              sales: reportSales,
                            ),
                          ),
                        ),
                        SizedBox(
                          width: tileWidth,
                          child: _SummaryTile(
                            title: 'Transacciones',
                            value: '${reportSales.length}',
                            accent: const Color(0xFF3977D5),
                            badgeLabel: 'En el periodo',
                            trend: transactionTrend,
                            onTap: () => _showMetricDetails(
                              title: 'Transacciones del periodo',
                              sales: reportSales,
                            ),
                          ),
                        ),
                        SizedBox(
                          width: tileWidth,
                          child: _SummaryTile(
                            title: 'Unidades vendidas',
                            value: '$unitsSold',
                            accent: const Color(0xFF8A61C9),
                            badgeLabel: 'En el periodo',
                            trend: unitsTrend,
                            onTap: () => _showMetricDetails(
                              title: 'Productos vendidos',
                              sales: reportSales,
                              showProducts: true,
                            ),
                          ),
                        ),
                        SizedBox(
                          width: tileWidth,
                          child: _SummaryTile(
                            title: 'Ticket promedio',
                            value: averageLabel,
                            accent: const Color(0xFFE59B36),
                            badgeLabel: 'Por venta',
                            trend: averageTrend,
                            onTap: () => _showMetricDetails(
                              title: 'Ventas y ticket promedio',
                              sales: reportSales,
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 18),
                if (totalsByCurrency.isNotEmpty)
                  _ReportCard(
                    title: 'Aporte por moneda y tipo de cambio',
                    child: Column(
                      children: [
                        for (final code in currencyCodes)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              '${AppCurrency.symbolFor(code)} $code',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            subtitle: Text(
                              '${reportSales.where((sale) => sale.currencyCode == code).length} ventas · '
                              'Tasa promedio: ${_averageExchangeRate(reportSales, code).toStringAsFixed(2)}',
                            ),
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  AppCurrency.format(
                                    totalsByCurrency[code]!,
                                    code: code,
                                  ),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                Text(
                                  AppCurrency.formatReference(
                                    usdTotalsByCurrency[code]!,
                                  ),
                                  style: Theme.of(context).textTheme.labelSmall,
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                if (totalsByCurrency.isNotEmpty) const SizedBox(height: 18),
                _ReportCard(
                  title:
                      'Total acumulado por ${_groupLabel(_grouping)} y moneda',
                  child: groupedSales.isEmpty
                      ? const _NoData()
                      : Column(
                          children: [
                            for (final bucket in groupedSales)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 9,
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Text(
                                      _grouping == _Grouping.week
                                          ? 'Semana del ${bucket.label}'
                                          : bucket.label,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 5),
                                    for (final code
                                        in bucket.amounts.keys.toList()..sort())
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 2,
                                        ),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                '$code · ${AppCurrency.format(bucket.amounts[code]!, code: code)}',
                                              ),
                                            ),
                                            Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.end,
                                              children: [
                                                Text(
                                                  AppCurrency.formatReference(
                                                    bucket.usdAmounts[code] ??
                                                        0,
                                                  ),
                                                  style: Theme.of(
                                                    context,
                                                  ).textTheme.labelSmall,
                                                ),
                                                Text(
                                                  'TC prom. 1 USD = '
                                                  '${bucket.averageRates[code]?.toStringAsFixed(2) ?? '1.00'} $code',
                                                  style: Theme.of(
                                                    context,
                                                  ).textTheme.labelSmall,
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                ),
                const SizedBox(height: 18),
                _ReportCard(
                  title: 'Ventas por ${_groupLabel(_grouping)}',
                  child: Column(
                    children: [
                      if (state.status == ReportsStatus.loading &&
                          reportSales.isEmpty)
                        const SizedBox(
                          height: 220,
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (groupedSales.isEmpty)
                        const _NoData()
                      else
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final chartWidth = groupedSales.length > 12
                                ? (groupedSales.length * 42.0)
                                      .clamp(constraints.maxWidth, 1400.0)
                                      .toDouble()
                                : constraints.maxWidth;
                            final hasMultipleCurrencies =
                                currencyCodes.length > 1;
                            final maxY = hasMultipleCurrencies
                                ? 110.0
                                : _maxAmount(groupedSales);
                            final interval = maxY / 4;
                            return SizedBox(
                              height: 286,
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: SizedBox(
                                  width: chartWidth,
                                  child: LineChart(
                                    LineChartData(
                                      minX: 0,
                                      maxX: (groupedSales.length - 1)
                                          .clamp(1, double.infinity)
                                          .toDouble(),
                                      minY: 0,
                                      maxY: maxY,
                                      lineTouchData: LineTouchData(
                                        handleBuiltInTouches: true,
                                        touchTooltipData: LineTouchTooltipData(
                                          getTooltipItems: (spots) => spots.map((
                                            spot,
                                          ) {
                                            final bucketIndex = spot.x.toInt();
                                            final currencyIndex = spot.barIndex;
                                            if (bucketIndex < 0 ||
                                                bucketIndex >=
                                                    groupedSales.length ||
                                                currencyIndex >=
                                                    currencyCodes.length) {
                                              return null;
                                            }
                                            final currencyCode =
                                                currencyCodes[currencyIndex];
                                            final amount =
                                                groupedSales[bucketIndex]
                                                    .amounts[currencyCode] ??
                                                0;
                                            return LineTooltipItem(
                                              '${groupedSales[bucketIndex].label}\n${AppCurrency.format(amount, code: currencyCode)}',
                                              TextStyle(
                                                color: _chartColor(
                                                  currencyIndex,
                                                ),
                                                fontWeight: FontWeight.w700,
                                              ),
                                            );
                                          }).toList(),
                                        ),
                                      ),
                                      gridData: FlGridData(
                                        show: true,
                                        drawVerticalLine: false,
                                        horizontalInterval: interval,
                                        getDrawingHorizontalLine: (_) => FlLine(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .outlineVariant
                                              .withValues(alpha: 0.65),
                                          strokeWidth: 1,
                                          dashArray: [4, 4],
                                        ),
                                      ),
                                      borderData: FlBorderData(show: false),
                                      titlesData: FlTitlesData(
                                        topTitles: const AxisTitles(
                                          sideTitles: SideTitles(
                                            showTitles: false,
                                          ),
                                        ),
                                        rightTitles: const AxisTitles(
                                          sideTitles: SideTitles(
                                            showTitles: false,
                                          ),
                                        ),
                                        leftTitles: AxisTitles(
                                          sideTitles: SideTitles(
                                            showTitles: true,
                                            reservedSize: 52,
                                            interval: interval,
                                            getTitlesWidget: (value, _) => Text(
                                              hasMultipleCurrencies
                                                  ? '${value.toInt()}%'
                                                  : '${AppCurrency.optionFor(currencyCodes.first).symbol}${_shortAmount(value)}',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .labelSmall
                                                  ?.copyWith(
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .onSurfaceVariant,
                                                  ),
                                            ),
                                          ),
                                        ),
                                        bottomTitles: AxisTitles(
                                          sideTitles: SideTitles(
                                            showTitles: true,
                                            reservedSize: 34,
                                            interval: 1,
                                            getTitlesWidget: (value, _) {
                                              final index = value.toInt();
                                              if (index < 0 ||
                                                  index >=
                                                      groupedSales.length) {
                                                return const SizedBox.shrink();
                                              }
                                              final step =
                                                  groupedSales.length > 14
                                                  ? 4
                                                  : groupedSales.length > 8
                                                  ? 2
                                                  : 1;
                                              if (index % step != 0 &&
                                                  index !=
                                                      groupedSales.length - 1) {
                                                return const SizedBox.shrink();
                                              }
                                              return Padding(
                                                padding: const EdgeInsets.only(
                                                  top: 10,
                                                ),
                                                child: Text(
                                                  groupedSales[index].label,
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .labelSmall
                                                      ?.copyWith(
                                                        color: Theme.of(context)
                                                            .colorScheme
                                                            .onSurfaceVariant,
                                                      ),
                                                ),
                                              );
                                            },
                                          ),
                                        ),
                                      ),
                                      lineBarsData: [
                                        for (
                                          var series = 0;
                                          series < currencyCodes.length;
                                          series++
                                        )
                                          LineChartBarData(
                                            spots: [
                                              for (
                                                var index = 0;
                                                index < groupedSales.length;
                                                index++
                                              )
                                                FlSpot(
                                                  index.toDouble(),
                                                  _chartValue(
                                                    groupedSales[index]
                                                            .amounts[currencyCodes[series]] ??
                                                        0,
                                                    groupedSales,
                                                    currencyCodes[series],
                                                    normalized:
                                                        hasMultipleCurrencies,
                                                  ),
                                                ),
                                            ],
                                            isCurved: true,
                                            curveSmoothness: 0.22,
                                            color: _chartColor(series),
                                            barWidth: 3,
                                            isStrokeCapRound: true,
                                            dotData: FlDotData(
                                              show: groupedSales.length == 1,
                                              getDotPainter:
                                                  (
                                                    spot,
                                                    percent,
                                                    barData,
                                                    index,
                                                  ) => FlDotCirclePainter(
                                                    radius: 4,
                                                    color: _chartColor(series),
                                                    strokeWidth: 2,
                                                    strokeColor: Theme.of(
                                                      context,
                                                    ).colorScheme.surface,
                                                  ),
                                            ),
                                            belowBarData: BarAreaData(
                                              show: true,
                                              gradient: LinearGradient(
                                                begin: Alignment.topCenter,
                                                end: Alignment.bottomCenter,
                                                colors: [
                                                  _chartColor(
                                                    series,
                                                  ).withValues(alpha: 0.18),
                                                  _chartColor(
                                                    series,
                                                  ).withValues(alpha: 0.01),
                                                ],
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      if (groupedSales.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 14,
                          runSpacing: 8,
                          children: currencyCodes
                              .asMap()
                              .entries
                              .map(
                                (entry) => Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 9,
                                      height: 9,
                                      decoration: BoxDecoration(
                                        color: _chartColor(entry.key),
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 5),
                                    Text(
                                      entry.value,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.labelSmall,
                                    ),
                                  ],
                                ),
                              )
                              .toList(),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                _ReportCard(
                  title: 'Productos más vendidos',
                  child: products.isEmpty
                      ? const _NoData()
                      : Column(
                          children: [
                            for (
                              var index = 0;
                              index < products.length;
                              index++
                            )
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                ),
                                child: _RankedProductBar(
                                  rank: index + 1,
                                  name: products[index].name,
                                  quantity: products[index].quantity,
                                  maximum: products.first.quantity,
                                  color: _chartColor(index),
                                ),
                              ),
                          ],
                        ),
                ),
                const SizedBox(height: 18),
                _ReportCard(
                  title: 'Rendimiento por categoría',
                  child: categoryStats.isEmpty
                      ? const _NoData()
                      : Column(
                          children: [
                            for (
                              var index = 0;
                              index < categoryStats.length;
                              index++
                            )
                              _CategoryMetricTile(
                                category: categoryStats[index],
                                share: totalCategoryUnits == 0
                                    ? 0
                                    : categoryStats[index].units /
                                          totalCategoryUnits,
                                color: _chartColor(index),
                              ),
                          ],
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _chooseDates() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(
        start: DateTime(_from.year, _from.month, _from.day),
        end: DateTime(_to.year, _to.month, _to.day),
      ),
      helpText: 'Selecciona el rango del reporte',
      saveText: 'Aplicar',
      cancelText: 'Cancelar',
      confirmText: 'Aplicar',
    );
    if (range == null || !mounted) return;
    setState(() {
      _from = DateTime(range.start.year, range.start.month, range.start.day);
      _to = DateTime(
        range.end.year,
        range.end.month,
        range.end.day,
        23,
        59,
        59,
        999,
      );
    });
    _load();
  }

  double _averageExchangeRate(List<SaleRecord> sales, String currencyCode) {
    final matchingSales = sales
        .where((sale) => sale.currencyCode == currencyCode)
        .toList();
    if (matchingSales.isEmpty) return 1;
    return matchingSales.fold<double>(
          0,
          (total, sale) => total + sale.exchangeRate,
        ) /
        matchingSales.length;
  }

  List<_SalesBucket> _groupSales(List<SaleRecord> sales) {
    final totals = <DateTime, Map<String, double>>{};
    final usdTotals = <DateTime, Map<String, double>>{};
    final rateTotals = <DateTime, Map<String, double>>{};
    final rateCounts = <DateTime, Map<String, int>>{};
    for (final sale in sales) {
      var date = DateTime(sale.soldAt.year, sale.soldAt.month, sale.soldAt.day);
      if (_grouping == _Grouping.week) {
        date = date.subtract(Duration(days: date.weekday - 1));
      } else if (_grouping == _Grouping.month) {
        date = DateTime(date.year, date.month);
      }
      totals.putIfAbsent(date, () => {});
      totals[date]!.update(
        sale.currencyCode,
        (amount) => amount + sale.total,
        ifAbsent: () => sale.total,
      );
      usdTotals.putIfAbsent(date, () => {});
      usdTotals[date]!.update(
        sale.currencyCode,
        (amount) => amount + sale.total / sale.exchangeRate,
        ifAbsent: () => sale.total / sale.exchangeRate,
      );
      rateTotals.putIfAbsent(date, () => {});
      rateTotals[date]!.update(
        sale.currencyCode,
        (amount) => amount + sale.exchangeRate,
        ifAbsent: () => sale.exchangeRate,
      );
      rateCounts.putIfAbsent(date, () => {});
      rateCounts[date]!.update(
        sale.currencyCode,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }
    final ordered = totals.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return ordered
        .map(
          (entry) => _SalesBucket(
            label: _grouping == _Grouping.month
                ? _monthFormat.format(entry.key)
                : _dateFormat.format(entry.key),
            amounts: entry.value,
            usdAmounts: usdTotals[entry.key]!,
            averageRates: {
              for (final code in entry.value.keys)
                code:
                    rateTotals[entry.key]![code]! /
                    rateCounts[entry.key]![code]!,
            },
          ),
        )
        .toList();
  }

  List<int> _groupTransactionCounts(List<SaleRecord> sales) {
    final counts = <DateTime, int>{};
    for (final sale in sales) {
      final date = _bucketDate(sale.soldAt);
      counts.update(date, (count) => count + 1, ifAbsent: () => 1);
    }
    final dates = counts.keys.toList()..sort();
    return [for (final date in dates) counts[date]!];
  }

  List<int> _groupCurrencyTransactionCounts(
    List<SaleRecord> sales,
    String currencyCode,
  ) {
    final counts = <DateTime, int>{};
    for (final sale in sales) {
      final date = _bucketDate(sale.soldAt);
      counts.putIfAbsent(date, () => 0);
      if (sale.currencyCode == currencyCode) {
        counts[date] = counts[date]! + 1;
      }
    }
    final dates = counts.keys.toList()..sort();
    return [for (final date in dates) counts[date]!];
  }

  List<double> _groupUnitCounts(List<SaleRecord> sales) {
    final counts = <DateTime, double>{};
    for (final sale in sales) {
      final date = _bucketDate(sale.soldAt);
      final units = sale.lines.fold<double>(
        0.0,
        (total, line) => total + line.quantity,
      );
      counts.update(date, (count) => count + units, ifAbsent: () => units);
    }
    final dates = counts.keys.toList()..sort();
    return [for (final date in dates) counts[date]!];
  }

  DateTime _bucketDate(DateTime source) {
    var date = DateTime(source.year, source.month, source.day);
    if (_grouping == _Grouping.week) {
      date = date.subtract(Duration(days: date.weekday - 1));
    } else if (_grouping == _Grouping.month) {
      date = DateTime(date.year, date.month);
    }
    return date;
  }

  List<_ProductTotal> _topProducts(List<SaleRecord> sales) {
    final quantities = <String, double>{};
    final names = <String, String>{};
    for (final sale in sales) {
      for (final line in sale.lines) {
        quantities.update(
          line.productId,
          (quantity) => quantity + line.quantity,
          ifAbsent: () => line.quantity,
        );
        names[line.productId] = line.productName;
      }
    }
    final products =
        quantities.entries
            .map(
              (entry) => _ProductTotal(
                name: names[entry.key] ?? 'Producto',
                quantity: entry.value,
              ),
            )
            .toList()
          ..sort((a, b) => b.quantity.compareTo(a.quantity));
    return products.take(5).toList();
  }

  List<_CategoryTotal> _categoryStats(List<SaleRecord> sales) {
    final categories = <String, _CategoryTotal>{};
    for (final sale in sales) {
      for (final line in sale.lines) {
        final categoryName = line.category.trim().isEmpty
            ? 'Sin categoría'
            : line.category.trim();
        final category = categories.putIfAbsent(
          categoryName,
          () => _CategoryTotal(categoryName),
        );
        category.units += line.quantity;
        category.transactions.add(sale.id);
        category.amounts.update(
          sale.currencyCode,
          (amount) => amount + line.total,
          ifAbsent: () => line.total,
        );
        category.usdAmount += line.total / sale.exchangeRate;
      }
    }
    return categories.values.toList()
      ..sort((first, second) => second.units.compareTo(first.units));
  }

  double _maxAmount(List<_SalesBucket> buckets) {
    final max = buckets.fold<double>(0, (value, item) {
      final itemMax = item.amounts.values.fold<double>(
        0,
        (current, amount) => amount > current ? amount : current,
      );
      return itemMax > value ? itemMax : value;
    });
    return max == 0 ? 1 : max * 1.2;
  }

  double _chartValue(
    double amount,
    List<_SalesBucket> buckets,
    String currencyCode, {
    required bool normalized,
  }) {
    if (!normalized) return amount;
    final seriesMaximum = buckets.fold<double>(0, (maximum, bucket) {
      final bucketAmount = bucket.amounts[currencyCode] ?? 0;
      return bucketAmount > maximum ? bucketAmount : maximum;
    });
    return seriesMaximum == 0 ? 0 : amount / seriesMaximum * 100;
  }

  String _shortAmount(double amount) =>
      NumberFormat.compact(locale: 'es').format(amount);

  Color _chartColor(int index) {
    final colors = [
      Theme.of(context).colorScheme.primary,
      const Color(0xFF00897B),
      const Color(0xFF8E24AA),
      const Color(0xFFEF6C00),
      const Color(0xFF1976D2),
      const Color(0xFFC62828),
    ];
    return colors[index % colors.length];
  }

  String _groupLabel(_Grouping grouping) => switch (grouping) {
    _Grouping.day => 'día',
    _Grouping.week => 'semana',
    _Grouping.month => 'mes',
  };
}

class _FilterCard extends StatelessWidget {
  final DateTime from;
  final DateTime to;
  final _Grouping grouping;
  final String? currencyCode;
  final List<String> currencyCodes;
  final String dateLabel;
  final VoidCallback onChooseDates;
  final ValueChanged<_Grouping> onGroupingChanged;
  final ValueChanged<String?> onCurrencyChanged;

  const _FilterCard({
    required this.from,
    required this.to,
    required this.grouping,
    required this.currencyCode,
    required this.currencyCodes,
    required this.dateLabel,
    required this.onChooseDates,
    required this.onGroupingChanged,
    required this.onCurrencyChanged,
  });

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: BorderSide(
        color: Theme.of(context).dividerColor.withValues(alpha: 0.6),
      ),
    ),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.tune_rounded,
                size: 19,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                'Filtros del informe',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onChooseDates,
            icon: const Icon(Icons.date_range_outlined),
            label: Text(
              dateLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: currencyCode,
            decoration: const InputDecoration(labelText: 'Filtrar por moneda'),
            items: [
              const DropdownMenuItem<String>(
                value: null,
                child: Text('Todas las monedas'),
              ),
              for (final code in currencyCodes)
                DropdownMenuItem<String>(
                  value: code,
                  child: Text('${AppCurrency.symbolFor(code)} $code'),
                ),
            ],
            onChanged: onCurrencyChanged,
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<_Grouping>(
            initialValue: grouping,
            decoration: const InputDecoration(labelText: 'Agrupar ventas'),
            items: const [
              DropdownMenuItem(value: _Grouping.day, child: Text('Por día')),
              DropdownMenuItem(
                value: _Grouping.week,
                child: Text('Por semana'),
              ),
              DropdownMenuItem(value: _Grouping.month, child: Text('Por mes')),
            ],
            onChanged: (value) {
              if (value != null) onGroupingChanged(value);
            },
          ),
        ],
      ),
    ),
  );
}

class _SummaryTile extends StatelessWidget {
  final String title;
  final String value;
  final Color accent;
  final String badgeLabel;
  final List<double> trend;
  final VoidCallback onTap;

  const _SummaryTile({
    required this.title,
    required this.value,
    required this.accent,
    required this.badgeLabel,
    required this.trend,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => MetricChartCard(
    title: title,
    value: value,
    color: accent,
    trend: trend,
    badgeLabel: badgeLabel,
    onTap: onTap,
  );
}

class _ReportMetricDetailsSheet extends StatelessWidget {
  final String title;
  final List<SaleRecord> sales;
  final bool showProducts;

  const _ReportMetricDetailsSheet({
    required this.title,
    required this.sales,
    required this.showProducts,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final products = <String, _DetailedProduct>{};
    for (final sale in sales) {
      for (final line in sale.lines) {
        final key = '${sale.currencyCode}:${line.productId}';
        final product = products.putIfAbsent(
          key,
          () => _DetailedProduct(
            name: line.productName,
            currencyCode: sale.currencyCode,
          ),
        );
        product
          ..quantity += line.quantity
          ..amount += line.total
          ..usdAmount += line.total / sale.exchangeRate;
      }
    }
    final sortedProducts = products.values.toList()
      ..sort((first, second) => second.quantity.compareTo(first.quantity));
    final sortedSales = sales.toList()
      ..sort((first, second) => second.soldAt.compareTo(first.soldAt));

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .84,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              showProducts
                  ? 'Unidades e importes agrupados por producto'
                  : '${sales.length} ventas · toca una venta para ver sus productos',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 14),
            Expanded(
              child: showProducts
                  ? sortedProducts.isEmpty
                        ? const _NoData()
                        : ListView.separated(
                            itemCount: sortedProducts.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final product = sortedProducts[index];
                              return ListTile(
                                tileColor: theme.colorScheme.surface,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  side: BorderSide(
                                    color: theme.colorScheme.outlineVariant,
                                  ),
                                ),
                                leading: CircleAvatar(
                                  backgroundColor:
                                      theme.colorScheme.primaryContainer,
                                  foregroundColor: theme.colorScheme.primary,
                                  child: Text('${index + 1}'),
                                ),
                                title: Text(
                                  product.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                subtitle: Text('${product.quantity} unidades'),
                                trailing: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      AppCurrency.format(
                                        product.amount,
                                        code: product.currencyCode,
                                      ),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    Text(
                                      AppCurrency.formatReference(
                                        product.usdAmount,
                                      ),
                                      style: theme.textTheme.labelSmall,
                                    ),
                                  ],
                                ),
                              );
                            },
                          )
                  : sortedSales.isEmpty
                  ? const _NoData()
                  : ListView.separated(
                      itemCount: sortedSales.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final sale = sortedSales[index];
                        return Card(
                          margin: EdgeInsets.zero,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: BorderSide(
                              color: theme.colorScheme.outlineVariant,
                            ),
                          ),
                          child: ExpansionTile(
                            title: Text(
                              AppCurrency.formatWithUsdReference(
                                sale.total,
                                code: sale.currencyCode,
                                exchangeRate: sale.exchangeRate,
                              ),
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            subtitle: Text(
                              '${DateFormat('dd/MM/yyyy HH:mm', 'es').format(sale.soldAt)} · '
                              '${sale.customerName ?? 'Venta sin cliente'} · '
                              '${sale.paymentMethod} · '
                              '${sale.lines.length} productos · '
                              'Tasa 1 USD = ${sale.exchangeRate} ${sale.currencyCode}',
                            ),
                            children: [
                              for (final line in sale.lines)
                                ListTile(
                                  dense: true,
                                  title: Text(line.productName),
                                  subtitle: Text(
                                    '${line.displayQuantity} ${line.unitLabel} × '
                                    '${AppCurrency.format(line.unitPrice, code: sale.currencyCode)} · '
                                    '${AppCurrency.formatReference(line.unitPrice / sale.exchangeRate)}',
                                  ),
                                  trailing: Text(
                                    AppCurrency.formatWithUsdReference(
                                      line.total,
                                      code: sale.currencyCode,
                                      exchangeRate: sale.exchangeRate,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SaleLookupCard extends StatelessWidget {
  final TextEditingController controller;
  final String? saleId;
  final SaleRecord? sale;
  final bool isLoading;
  final ValueChanged<String> onSearch;
  final VoidCallback onScan;
  final VoidCallback onPickImage;
  final ValueChanged<SaleRecord> onReprint;
  final bool isPrinting;

  const _SaleLookupCard({
    required this.controller,
    required this.saleId,
    required this.sale,
    required this.isLoading,
    required this.onSearch,
    required this.onScan,
    required this.onPickImage,
    required this.onReprint,
    required this.isPrinting,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Buscar venta por folio',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Escanea el QR del recibo o selecciónalo desde una foto. '
              'La búsqueda se realiza en este dispositivo.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              textInputAction: TextInputAction.search,
              onSubmitted: onSearch,
              decoration: InputDecoration(
                labelText: 'Folio de la venta',
                prefixIcon: const Icon(Icons.qr_code_scanner),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Escanear QR',
                      onPressed: onScan,
                      icon: const Icon(Icons.qr_code_scanner),
                    ),
                    IconButton(
                      tooltip: 'Leer QR desde una foto',
                      onPressed: onPickImage,
                      icon: const Icon(Icons.image_search_outlined),
                    ),
                    IconButton(
                      tooltip: 'Buscar venta',
                      onPressed: () => onSearch(controller.text),
                      icon: const Icon(Icons.search),
                    ),
                  ],
                ),
                border: const OutlineInputBorder(),
              ),
            ),
            if (isLoading && saleId != null) ...[
              const SizedBox(height: 14),
              const LinearProgressIndicator(),
            ] else if (saleId != null && sale == null) ...[
              const SizedBox(height: 12),
              Text(
                'No se encontró el folio indicado en las ventas guardadas.',
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ] else if (sale != null) ...[
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withValues(
                    alpha: .35,
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Venta localizada · ${sale!.id}',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${DateFormat('dd/MM/yyyy HH:mm', 'es').format(sale!.soldAt)}'
                      ' · ${sale!.customerName ?? 'Venta sin cliente'}'
                      ' · ${sale!.paymentMethod}'
                      ' · Tasa 1 USD = ${sale!.exchangeRate} ${sale!.currencyCode}',
                    ),
                    const Divider(height: 18),
                    for (final line in sale!.lines)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${line.displayQuantity} ${line.unitLabel} × ${line.productName}',
                              ),
                            ),
                            Text(
                              AppCurrency.formatWithUsdReference(
                                line.total,
                                code: sale!.currencyCode,
                                exchangeRate: sale!.exchangeRate,
                              ),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    const Divider(height: 18),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'TOTAL',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          AppCurrency.formatWithUsdReference(
                            sale!.total,
                            code: sale!.currencyCode,
                            exchangeRate: sale!.exchangeRate,
                          ),
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: isPrinting ? null : () => onReprint(sale!),
                        icon: const Icon(Icons.print_outlined),
                        label: const Text('Reimprimir ticket'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

enum _SaleAction { reprint, whatsapp }

class _SalesHistoryCard extends StatelessWidget {
  final List<SaleRecord> sales;
  final ValueChanged<SaleRecord> onSaleTap;
  final bool isPrinting;

  const _SalesHistoryCard({
    required this.sales,
    required this.onSaleTap,
    required this.isPrinting,
  });

  @override
  Widget build(BuildContext context) {
    final sortedSales = sales.toList()
      ..sort((first, second) => second.soldAt.compareTo(first.soldAt));
    return _ReportCard(
      title: 'Ventas y reimpresión de tickets',
      child: sortedSales.isEmpty
          ? const _NoData()
          : Column(
              children: [
                for (final sale in sortedSales)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor: Theme.of(
                        context,
                      ).colorScheme.primaryContainer,
                      child: const Icon(Icons.receipt_long_outlined),
                    ),
                    title: Text(
                      sale.customerName?.trim().isNotEmpty == true
                          ? sale.customerName!
                          : 'Venta sin cliente',
                    ),
                    subtitle: Text(
                      '${DateFormat('dd/MM/yyyy HH:mm', 'es').format(sale.soldAt)}'
                      ' · ${sale.id} · ${sale.paymentMethod}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          AppCurrency.format(
                            sale.total,
                            code: sale.currencyCode,
                          ),
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          '${sale.lines.length} productos',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ],
                    ),
                    onTap: isPrinting ? null : () => onSaleTap(sale),
                  ),
              ],
            ),
    );
  }
}

class _SaleDetailsDialog extends StatelessWidget {
  final SaleRecord sale;

  const _SaleDetailsDialog({required this.sale});

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Detalle de la compra'),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(DateFormat('dd/MM/yyyy HH:mm', 'es').format(sale.soldAt)),
            Text('Folio: ${sale.id}'),
            Text('Cliente: ${sale.customerName ?? 'Venta sin cliente'}'),
            Text('Pago: ${sale.paymentMethod}'),
            Text('Tasa: 1 USD = ${sale.exchangeRate} ${sale.currencyCode}'),
            const Divider(height: 24),
            for (final line in sale.lines)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        '${line.displayQuantity} ${line.unitLabel} × ${line.productName}'
                        '${line.variationLabel.isEmpty ? '' : '\n${line.variationLabel}'}',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      AppCurrency.format(line.total, code: sale.currencyCode),
                    ),
                  ],
                ),
              ),
            const Divider(height: 24),
            _InvoiceAmountRow(
              label: 'Total',
              amount: sale.total,
              currencyCode: sale.currencyCode,
              emphasized: true,
            ),
            if (sale.paymentMethod.toLowerCase() == 'efectivo' &&
                sale.amountTendered > 0) ...[
              const SizedBox(height: 8),
              _InvoiceAmountRow(
                label: 'Recibido',
                amount: sale.amountTendered,
                currencyCode: sale.currencyCode,
              ),
              _InvoiceAmountRow(
                label: 'Vuelto',
                amount: sale.changeAmount,
                currencyCode: sale.currencyCode,
              ),
            ],
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cerrar'),
      ),
      OutlinedButton.icon(
        onPressed: () => Navigator.pop(context, _SaleAction.whatsapp),
        icon: const Icon(Icons.chat_outlined),
        label: const Text('WhatsApp'),
      ),
      FilledButton.icon(
        onPressed: () => Navigator.pop(context, _SaleAction.reprint),
        icon: const Icon(Icons.print_outlined),
        label: const Text('Reimprimir'),
      ),
    ],
  );
}

class _InvoiceAmountRow extends StatelessWidget {
  final String label;
  final double amount;
  final String currencyCode;
  final bool emphasized;

  const _InvoiceAmountRow({
    required this.label,
    required this.amount,
    required this.currencyCode,
    this.emphasized = false,
  });

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(
        label,
        style: TextStyle(
          fontWeight: emphasized ? FontWeight.w800 : FontWeight.normal,
        ),
      ),
      Text(
        AppCurrency.format(amount, code: currencyCode),
        style: TextStyle(
          fontWeight: emphasized ? FontWeight.w800 : FontWeight.normal,
        ),
      ),
    ],
  );
}

class _CashClosingSelection {
  final DateTime date;
  final List<SaleRecord> sales;

  const _CashClosingSelection({required this.date, required this.sales});
}

class _CashClosingPreviewDialog extends StatefulWidget {
  final List<SaleRecord> sales;
  final DateTime initialDate;

  const _CashClosingPreviewDialog({
    required this.sales,
    required this.initialDate,
  });

  @override
  State<_CashClosingPreviewDialog> createState() =>
      _CashClosingPreviewDialogState();
}

class _CashClosingPreviewDialogState extends State<_CashClosingPreviewDialog> {
  late DateTime _selectedDate;
  late final DateTime _today;

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.initialDate;
    final now = DateTime.now();
    _today = DateTime(now.year, now.month, now.day);
  }

  List<SaleRecord> get _selectedSales {
    final start = _selectedDate;
    final end = start.add(const Duration(days: 1));
    return widget.sales
        .where(
          (sale) => !sale.soldAt.isBefore(start) && sale.soldAt.isBefore(end),
        )
        .toList()
      ..sort((first, second) => first.soldAt.compareTo(second.soldAt));
  }

  DateTime get _firstDate {
    if (widget.sales.isEmpty) return DateTime(2020);
    final earliest = widget.sales
        .map((sale) => sale.soldAt)
        .reduce((first, second) => first.isBefore(second) ? first : second);
    final date = DateTime(earliest.year, earliest.month, earliest.day);
    return date.isAfter(_today) ? _today : date;
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: _firstDate,
      lastDate: _today,
      helpText: 'Selecciona el día del cierre',
      cancelText: 'Cancelar',
      confirmText: 'Aplicar',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _selectedDate = DateTime(picked.year, picked.month, picked.day);
    });
  }

  void _moveDate(int days) {
    final nextDate = _selectedDate.add(Duration(days: days));
    if (nextDate.isAfter(_today) || nextDate.isBefore(_firstDate)) return;
    setState(() => _selectedDate = nextDate);
  }

  @override
  Widget build(BuildContext context) {
    final sales = _selectedSales;
    final totalsByCurrency = <String, double>{};
    final salesByCurrency = <String, int>{};
    final totalsByPaymentMethod = <String, double>{};
    final salesByPaymentMethod = <String, int>{};
    var unitsSold = 0.0;
    var totalUsd = 0.0;
    for (final sale in sales) {
      totalsByCurrency.update(
        sale.currencyCode,
        (total) => total + sale.total,
        ifAbsent: () => sale.total,
      );
      salesByCurrency.update(
        sale.currencyCode,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
      unitsSold += sale.lines.fold<double>(
        0.0,
        (total, line) => total + line.quantity,
      );
      totalUsd += sale.total / sale.exchangeRate;
      totalsByPaymentMethod.update(
        sale.paymentMethod,
        (total) => total + sale.total / sale.exchangeRate,
        ifAbsent: () => sale.total / sale.exchangeRate,
      );
      salesByPaymentMethod.update(
        sale.paymentMethod,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }

    final colors = Theme.of(context).colorScheme;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(22, 20, 12, 20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    colors.primary,
                    colors.primary.withValues(alpha: .8),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: colors.onPrimary.withValues(alpha: .16),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.point_of_sale_rounded,
                      color: colors.onPrimary,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Cierre de caja',
                          style: TextStyle(
                            color: colors.onPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'Resumen de ventas por día',
                          style: TextStyle(
                            color: colors.onPrimary.withValues(alpha: .72),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cerrar',
                    onPressed: () => Navigator.pop(context),
                    color: colors.onPrimary,
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerHighest.withValues(
                          alpha: .45,
                        ),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          IconButton(
                            tooltip: 'Día anterior',
                            onPressed: _selectedDate.isAfter(_firstDate)
                                ? () => _moveDate(-1)
                                : null,
                            icon: const Icon(Icons.chevron_left_rounded),
                          ),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _selectDate,
                              icon: const Icon(
                                Icons.calendar_month_rounded,
                                size: 18,
                              ),
                              label: Text(
                                DateFormat(
                                  'EEEE d \'de\' MMMM, yyyy',
                                  'es',
                                ).format(_selectedDate),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: colors.onSurface,
                                side: BorderSide(color: colors.outlineVariant),
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Día siguiente',
                            onPressed: _selectedDate.isBefore(_today)
                                ? () => _moveDate(1)
                                : null,
                            icon: const Icon(Icons.chevron_right_rounded),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _CashClosingMetric(
                            icon: Icons.receipt_long_outlined,
                            label: 'VENTAS',
                            value: '${sales.length}',
                            color: colors.primary,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _CashClosingMetric(
                            icon: Icons.inventory_2_outlined,
                            label: 'UNIDADES',
                            value: NumberFormat(
                              '#,##0.##',
                              'es',
                            ).format(unitsSold),
                            color: const Color(0xFF16856B),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Totales por moneda',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (sales.isEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          vertical: 22,
                          horizontal: 16,
                        ),
                        decoration: BoxDecoration(
                          color: colors.surfaceContainerHighest.withValues(
                            alpha: .35,
                          ),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Column(
                          children: [
                            Icon(
                              Icons.event_busy_rounded,
                              size: 28,
                              color: Color(0xFF7C8795),
                            ),
                            SizedBox(height: 8),
                            Text(
                              'No hay ventas registradas para este día.',
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      )
                    else ...[
                      for (final entry in totalsByCurrency.entries)
                        _CashClosingTotalRow(
                          label: '${salesByCurrency[entry.key]} ventas',
                          currencyCode: entry.key,
                          amount: entry.value,
                        ),
                      const SizedBox(height: 4),
                      _CashClosingTotalRow(
                        label: 'Total de referencia',
                        currencyCode: 'USD',
                        amount: totalUsd,
                        emphasized: true,
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'Ventas por método de pago · referencia USD',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      for (final entry in totalsByPaymentMethod.entries)
                        _CashClosingPaymentRow(
                          label: entry.key,
                          count: salesByPaymentMethod[entry.key]!,
                          amount: entry.value,
                        ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Detalle de ventas',
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                          ),
                          Text(
                            '${sales.length} registros',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      for (final sale in sales)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          leading: CircleAvatar(
                            radius: 17,
                            backgroundColor: colors.surfaceContainerHighest,
                            child: Text(
                              DateFormat('HH:mm', 'es').format(sale.soldAt),
                              style: const TextStyle(fontSize: 9),
                            ),
                          ),
                          title: Text(
                            sale.id,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          subtitle: Text(
                            '${sale.paymentMethod} · '
                            '${sale.customerName ?? 'Sin cliente'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Text(
                            AppCurrency.format(
                              sale.total,
                              code: sale.currencyCode,
                            ),
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancelar'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => Navigator.pop(
                        context,
                        _CashClosingSelection(
                          date: _selectedDate,
                          sales: sales,
                        ),
                      ),
                      icon: const Icon(Icons.print_outlined),
                      label: const Text('Imprimir cierre'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CashClosingMetric extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _CashClosingMetric({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .08),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: color.withValues(alpha: .15)),
    ),
    child: Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: .5,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                value,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _CashClosingTotalRow extends StatelessWidget {
  final String label;
  final String currencyCode;
  final double amount;
  final bool emphasized;

  const _CashClosingTotalRow({
    required this.label,
    required this.currencyCode,
    required this.amount,
    this.emphasized = false,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: emphasized ? null : Theme.of(context).hintColor,
              fontWeight: emphasized ? FontWeight.w800 : FontWeight.w500,
            ),
          ),
        ),
        Text(
          AppCurrency.format(amount, code: currencyCode),
          style: TextStyle(
            fontWeight: emphasized ? FontWeight.w900 : FontWeight.w700,
            color: emphasized ? Theme.of(context).colorScheme.primary : null,
          ),
        ),
      ],
    ),
  );
}

class _CashClosingPaymentRow extends StatelessWidget {
  final String label;
  final int count;
  final double amount;

  const _CashClosingPaymentRow({
    required this.label,
    required this.count,
    required this.amount,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        const Icon(Icons.payments_outlined, size: 17, color: Color(0xFF748194)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '$label · $count ${count == 1 ? 'venta' : 'ventas'}',
            style: const TextStyle(fontSize: 12),
          ),
        ),
        Text(
          AppCurrency.formatReference(amount),
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );
}

class _DetailedProduct {
  final String name;
  final String currencyCode;
  double quantity = 0;
  double amount = 0;
  double usdAmount = 0;

  _DetailedProduct({required this.name, required this.currencyCode});
}

class _ReportsHeader extends StatelessWidget {
  final String dateLabel;
  final int transactionCount;

  const _ReportsHeader({
    required this.dateLabel,
    required this.transactionCount,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colors.primary,
            Color.lerp(colors.primary, colors.onPrimary, 0.12)!,
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: colors.primary.withValues(alpha: 0.2),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ANÁLISIS DEL NEGOCIO',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.onPrimary.withValues(alpha: 0.74),
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.3,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Rendimiento de ventas',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: colors.onPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  dateLabel,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.onPrimary.withValues(alpha: 0.82),
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: colors.onPrimary.withValues(alpha: 0.13),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Text(
                    '$transactionCount transacciones registradas',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colors.onPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Icon(
            Icons.query_stats_rounded,
            size: 58,
            color: colors.onPrimary.withValues(alpha: 0.84),
          ),
        ],
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _ReportCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      elevation: 1,
      shadowColor: colors.shadow.withValues(alpha: 0.12),
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 4,
                  height: 22,
                  decoration: BoxDecoration(
                    color: colors.primary,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            child,
          ],
        ),
      ),
    );
  }
}

class _RankedProductBar extends StatelessWidget {
  final int rank;
  final String name;
  final double quantity;
  final double maximum;
  final Color color;

  const _RankedProductBar({
    required this.rank,
    required this.name,
    required this.quantity,
    required this.maximum,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                color.withValues(alpha: 0.18),
                color.withValues(alpha: 0.07),
              ],
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '$rank',
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ).copyWith(color: colors.onSurface),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '$quantity uds.',
                    style: TextStyle(
                      color: color,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 9),
              LayoutBuilder(
                builder: (context, constraints) => Stack(
                  children: [
                    Container(
                      height: 7,
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    Container(
                      width: constraints.maxWidth * (quantity / maximum),
                      height: 7,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [color.withValues(alpha: 0.62), color],
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CategoryMetricTile extends StatelessWidget {
  final _CategoryTotal category;
  final double share;
  final Color color;

  const _CategoryMetricTile({
    required this.category,
    required this.share,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.outlineVariant),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(Icons.category_rounded, color: color, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        category.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${category.units} unidades · ${category.transactions.length} ventas',
                        style: TextStyle(
                          color: colors.onSurfaceVariant,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (final amount in category.amounts.entries)
                      Text(
                        AppCurrency.format(amount.value, code: amount.key),
                        style: TextStyle(
                          color: color,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    Text(
                      AppCurrency.formatReference(category.usdAmount),
                      style: TextStyle(
                        color: colors.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: share,
                      minHeight: 7,
                      backgroundColor: colors.surfaceContainerHighest,
                      color: color,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '${(share * 100).round()}%',
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _NoData extends StatelessWidget {
  const _NoData();

  @override
  Widget build(BuildContext context) => const SizedBox(
    height: 180,
    child: Center(
      child: Text(
        'No hay ventas en el periodo seleccionado.',
        textAlign: TextAlign.center,
      ),
    ),
  );
}

class _SalesBucket {
  final String label;
  final Map<String, double> amounts;
  final Map<String, double> usdAmounts;
  final Map<String, double> averageRates;
  const _SalesBucket({
    required this.label,
    required this.amounts,
    required this.usdAmounts,
    required this.averageRates,
  });
}

class _ProductTotal {
  final String name;
  final double quantity;
  const _ProductTotal({required this.name, required this.quantity});
}

class _CategoryTotal {
  final String name;
  final Map<String, double> amounts = {};
  final Set<String> transactions = {};
  double units = 0;
  double usdAmount = 0;

  _CategoryTotal(this.name);
}
