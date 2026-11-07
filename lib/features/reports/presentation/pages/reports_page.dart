import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:zxing2/zxing2.dart' show NotFoundException;

import '../../../../core/utils/app_currency.dart';
import '../../../../core/utils/receipt_qr.dart';
import '../../../../core/utils/receipt_qr_image_decoder.dart';
import '../../../../core/widgets/metric_chart_card.dart';
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
      _showQrError('No se encontró un código QR legible en la imagen.');
    } on FormatException catch (error) {
      _showQrError('No se pudo leer la imagen: ${error.message}');
    } catch (error) {
      _showQrError('No se pudo leer el QR de la imagen: $error');
    }
  }

  void _searchScannedQr(String data) {
    final saleId = ReceiptQr.saleIdFromData(data);
    if (saleId == null || saleId.isEmpty) {
      _showQrError('El QR no contiene un folio de venta válido.');
      return;
    }
    _searchSale(saleId);
  }

  void _showQrError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
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
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('Reportes de ventas'),
        actions: [
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
          final totalCategoryUnits = categoryStats.fold<int>(
            0,
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
          final unitsSold = reportSales.fold<int>(
            0,
            (total, sale) =>
                total +
                sale.lines.fold<int>(
                  0,
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

  List<int> _groupUnitCounts(List<SaleRecord> sales) {
    final counts = <DateTime, int>{};
    for (final sale in sales) {
      final date = _bucketDate(sale.soldAt);
      final units = sale.lines.fold<int>(
        0,
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
    final quantities = <String, int>{};
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
                                    '${line.quantity} × '
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

  const _SaleLookupCard({
    required this.controller,
    required this.saleId,
    required this.sale,
    required this.isLoading,
    required this.onSearch,
    required this.onScan,
    required this.onPickImage,
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
                                '${line.quantity} × ${line.productName}',
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

class _DetailedProduct {
  final String name;
  final String currencyCode;
  int quantity = 0;
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
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(22),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Theme.of(context).colorScheme.primary,
          Theme.of(context).colorScheme.primary.withValues(alpha: 0.76),
          const Color(0xFF173B4E),
        ],
      ),
      boxShadow: [
        BoxShadow(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
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
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.74),
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.3,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Rendimiento de ventas',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                dateLabel,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.white.withValues(alpha: 0.82),
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Text(
                  '$transactionCount transacciones registradas',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Colors.white,
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
          color: Colors.white.withValues(alpha: 0.84),
        ),
      ],
    ),
  );
}

class _ReportCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _ReportCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) => Card(
    elevation: 1,
    shadowColor: const Color(0xFF172B4D).withValues(alpha: 0.06),
    color: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(22),
      side: const BorderSide(color: Color(0xFFE9EDF2)),
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
                  color: Theme.of(context).colorScheme.primary,
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

class _RankedProductBar extends StatelessWidget {
  final int rank;
  final String name;
  final int quantity;
  final int maximum;
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
                        color: Color(0xFF202938),
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
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
                        color: const Color(0xFFF0F2F5),
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
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE9EDF2)),
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
                      style: const TextStyle(
                        color: Color(0xFF778397),
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
                    style: const TextStyle(
                      color: Color(0xFF778397),
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
                    backgroundColor: const Color(0xFFF0F2F5),
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
  final int quantity;
  const _ProductTotal({required this.name, required this.quantity});
}

class _CategoryTotal {
  final String name;
  final Map<String, double> amounts = {};
  final Set<String> transactions = {};
  int units = 0;
  double usdAmount = 0;

  _CategoryTotal(this.name);
}
