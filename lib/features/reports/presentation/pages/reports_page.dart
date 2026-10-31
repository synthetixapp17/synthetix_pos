import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../../core/utils/app_currency.dart';
import '../../domain/entities/sale_record.dart';
import '../bloc/reports_bloc.dart';

enum _Grouping { day, week, month }

class ReportsPage extends StatefulWidget {
  final bool showToday;

  const ReportsPage({super.key, this.showToday = false});

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  late DateTime _from;
  late DateTime _to;
  _Grouping _grouping = _Grouping.day;
  final _dateFormat = DateFormat('d MMM', 'es');
  final _monthFormat = DateFormat('MMM yy', 'es');

  @override
  void initState() {
    super.initState();
    final today = DateTime.now();
    _to = DateTime(today.year, today.month, today.day, 23, 59, 59, 999);
    final start = widget.showToday
        ? today
        : today.subtract(const Duration(days: 29));
    _from = DateTime(start.year, start.month, start.day);
    _load();
  }

  void _load() =>
      context.read<ReportsBloc>().add(LoadReportsEvent(from: _from, to: _to));

  @override
  Widget build(BuildContext context) {
    AppCurrencyScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Reportes de ventas')),
      body: BlocConsumer<ReportsBloc, ReportsState>(
        listener: (context, state) {
          if (state.status == ReportsStatus.failure && state.message != null) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(state.message!)));
          }
        },
        builder: (context, state) {
          final groupedSales = _groupSales(state.sales);
          final products = _topProducts(state.sales);
          final categoryStats = _categoryStats(state.sales);
          final maxCategoryUnits = categoryStats.isEmpty
              ? 1
              : categoryStats.first.units;
          final currencyCodes =
              state.sales.map((sale) => sale.currencyCode).toSet().toList()
                ..sort();
          final totalsByCurrency = <String, double>{};
          for (final sale in state.sales) {
            totalsByCurrency.update(
              sale.currencyCode,
              (total) => total + sale.total,
              ifAbsent: () => sale.total,
            );
          }
          final totalLabel = totalsByCurrency.isEmpty
              ? AppCurrency.formatConfigured(0)
              : totalsByCurrency.entries
                    .map(
                      (entry) =>
                          AppCurrency.format(entry.value, code: entry.key),
                    )
                    .join('\n');
          final averageLabel = totalsByCurrency.isEmpty || state.sales.isEmpty
              ? AppCurrency.formatConfigured(0)
              : totalsByCurrency.entries
                    .map((entry) {
                      final currencyTransactions = state.sales
                          .where((sale) => sale.currencyCode == entry.key)
                          .length;
                      return AppCurrency.format(
                        entry.value / currencyTransactions,
                        code: entry.key,
                      );
                    })
                    .join('\n');
          final unitsSold = state.sales.fold<int>(
            0,
            (total, sale) =>
                total +
                sale.lines.fold<int>(
                  0,
                  (saleUnits, line) => saleUnits + line.quantity,
                ),
          );
          return RefreshIndicator(
            onRefresh: () async => _load(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              children: [
                    _ReportsHeader(
                      dateLabel:
                          '${_dateFormat.format(_from)} – ${_dateFormat.format(_to)}',
                      transactionCount: state.sales.length,
                    ),
                    const SizedBox(height: 16),
                    _FilterCard(
                      from: _from,
                      to: _to,
                      grouping: _grouping,
                      dateLabel:
                          '${_dateFormat.format(_from)} – ${_dateFormat.format(_to)}',
                      onChooseDates: _chooseDates,
                      onGroupingChanged: (grouping) =>
                          setState(() => _grouping = grouping),
                    ),
                    const SizedBox(height: 16),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final tileWidth = constraints.maxWidth >= 900
                            ? (constraints.maxWidth - 36) / 4
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
                                icon: Icons.account_balance_wallet_outlined,
                                accent: const Color(0xFF1E9B72),
                              ),
                            ),
                            SizedBox(
                              width: tileWidth,
                              child: _SummaryTile(
                                title: 'Transacciones',
                                value: '${state.sales.length}',
                                icon: Icons.receipt_long_outlined,
                                accent: const Color(0xFF3977D5),
                              ),
                            ),
                            SizedBox(
                              width: tileWidth,
                              child: _SummaryTile(
                                title: 'Unidades vendidas',
                                value: '$unitsSold',
                                icon: Icons.inventory_2_outlined,
                                accent: const Color(0xFF8A61C9),
                              ),
                            ),
                            SizedBox(
                              width: tileWidth,
                              child: _SummaryTile(
                                title: 'Ticket promedio',
                                value: averageLabel,
                                icon: Icons.trending_up_rounded,
                                accent: const Color(0xFFE59B36),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 18),
                    _ReportCard(
                      title: 'Ventas por ${_groupLabel(_grouping)}',
                      child: Column(
                        children: [
                          if (state.status == ReportsStatus.loading &&
                              state.sales.isEmpty)
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
                                                final bucketIndex = spot.x
                                                    .toInt();
                                                final currencyIndex =
                                                    spot.barIndex;
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
                                            getDrawingHorizontalLine: (_) =>
                                                FlLine(
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
                                                          groupedSales.length -
                                                              1) {
                                                    return const SizedBox.shrink();
                                                  }
                                                  return Padding(
                                                    padding:
                                                        const EdgeInsets.only(
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
                                                  show:
                                                      groupedSales.length == 1,
                                                  getDotPainter:
                                                      (
                                                        spot,
                                                        percent,
                                                        barData,
                                                        index,
                                                      ) => FlDotCirclePainter(
                                                        radius: 4,
                                                        color: _chartColor(
                                                          series,
                                                        ),
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
                                for (final category in categoryStats)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 9,
                                    ),
                                    child: Row(
                                      children: [
                                        CircleAvatar(
                                          backgroundColor: Theme.of(
                                            context,
                                          ).colorScheme.primaryContainer,
                                          child: Icon(
                                            Icons.category_outlined,
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onPrimaryContainer,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                category.name,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                              const SizedBox(height: 3),
                                              Text(
                                                '${category.units} unidades · ${category.transactions.length} ventas',
                                                style: Theme.of(
                                                  context,
                                                ).textTheme.bodySmall,
                                              ),
                                              const SizedBox(height: 10),
                                              ClipRRect(
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                child: LinearProgressIndicator(
                                                  value:
                                                      category.units /
                                                      maxCategoryUnits,
                                                  minHeight: 7,
                                                  backgroundColor:
                                                      Theme.of(context)
                                                          .colorScheme
                                                          .surfaceContainerHighest,
                                                  color: Theme.of(
                                                    context,
                                                  ).colorScheme.primary,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Flexible(
                                          child: Text(
                                            category.amounts.entries
                                                .map(
                                                  (entry) => AppCurrency.format(
                                                    entry.value,
                                                    code: entry.key,
                                                  ),
                                                )
                                                .join('\n'),
                                            textAlign: TextAlign.end,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
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

  List<_SalesBucket> _groupSales(List<SaleRecord> sales) {
    final totals = <DateTime, Map<String, double>>{};
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
          ),
        )
        .toList();
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
  final String dateLabel;
  final VoidCallback onChooseDates;
  final ValueChanged<_Grouping> onGroupingChanged;

  const _FilterCard({
    required this.from,
    required this.to,
    required this.grouping,
    required this.dateLabel,
    required this.onChooseDates,
    required this.onGroupingChanged,
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
  final IconData icon;
  final Color accent;

  const _SummaryTile({
    required this.title,
    required this.value,
    required this.icon,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) => Card(
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
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: accent, size: 20),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
        ],
      ),
    ),
  );
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
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
      side: BorderSide(
        color: Theme.of(context).dividerColor.withValues(alpha: 0.6),
      ),
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
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '$rank',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
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
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '$quantity uds.',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: quantity / maximum,
                  minHeight: 7,
                  backgroundColor: colors.surfaceContainerHighest,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ],
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
  const _SalesBucket({required this.label, required this.amounts});
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

  _CategoryTotal(this.name);
}
