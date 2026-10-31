import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/theme_controller.dart';
import '../../../../core/utils/app_currency.dart';
import '../../../../core/widgets/metric_chart_card.dart';
import '../bloc/dashboard_bloc.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  static final _date = DateFormat('EEE d', 'es');

  @override
  void initState() {
    super.initState();
    context.read<DashboardBloc>().add(const LoadDashboardEvent());
  }

  @override
  Widget build(BuildContext context) {
    AppCurrencyScope.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('Resumen'),
        actions: [
          IconButton(
            tooltip: 'Cambiar tema',
            onPressed: AppThemeController.toggle,
            icon: ValueListenableBuilder<ThemeMode>(
              valueListenable: AppThemeController.mode,
              builder: (_, mode, _) => Icon(
                mode == ThemeMode.dark ? Icons.light_mode : Icons.dark_mode,
              ),
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Navegación',
            onSelected: (route) => context.push(route),
            itemBuilder: (_) => const [
              PopupMenuItem(value: '/customers', child: Text('Clientes')),
              PopupMenuItem(value: '/reports', child: Text('Reportes')),
              PopupMenuItem(value: '/products', child: Text('Productos')),
              PopupMenuItem(value: '/settings', child: Text('Configuración')),
            ],
          ),
        ],
      ),
      body: BlocConsumer<DashboardBloc, DashboardState>(
        listener: (context, state) {
          if (state.status == DashboardStatus.failure &&
              state.message != null) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(state.message!)));
          }
        },
        builder: (context, state) {
          final summary = state.summary;
          if (state.status == DashboardStatus.loading && summary == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (summary == null) {
            return Center(
              child: FilledButton.icon(
                onPressed: () => context.read<DashboardBloc>().add(
                  const LoadDashboardEvent(),
                ),
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
            );
          }
          final chartCurrencies =
              summary.lastSevenDays
                  .map((day) => day.currencyCode)
                  .toSet()
                  .toList()
                ..sort();
          return RefreshIndicator(
            onRefresh: () async => context.read<DashboardBloc>().add(
              LoadDashboardEvent(threshold: state.threshold),
            ),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
              children: [
                _WelcomeCard(onNewSale: () => context.push('/new-sale')),
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final dailyTrend = summary.lastSevenDays
                        .where(
                          (day) => day.currencyCode == AppCurrency.currentCode,
                        )
                        .map((day) => day.amount)
                        .toList();
                    final metricCards = <Widget>[
                      MetricChartCard(
                        title: 'Ventas del día',
                        value: summary.dailyTotals.isEmpty
                            ? AppCurrency.formatConfigured(0)
                            : summary.dailyTotals.entries
                                  .map(
                                    (entry) => AppCurrency.format(
                                      entry.value,
                                      code: entry.key,
                                    ),
                                  )
                                  .join('\n'),
                        trend: dailyTrend,
                        subtitle: '${summary.transactionCount} transacciones',
                        color: const Color(0xFF00E676),
                        legacyDashboardStyle: true,
                        onTap: () => context.push('/reports?period=today'),
                      ),
                      MetricChartCard(
                        title: 'Stock bajo',
                        value: '${summary.lowStock.length}',
                        trend: summary.lowStock
                            .map((product) => product.stock.toDouble())
                            .toList(),
                        subtitle:
                            '${summary.lowStock.where((product) => product.stock == 0).length} agotados · umbral ${state.threshold}',
                        color: const Color(0xFFFF5252),
                        backgroundColors: const [
                          Color(0xFF4A1D20),
                          Color(0xFF170E10),
                        ],
                        borderColor: const Color(0xFF6B2B30),
                        legacyDashboardStyle: true,
                        onTap: () => context.push(
                          '/products?lowStock=1&threshold=${state.threshold}',
                        ),
                      ),
                    ];
                    if (constraints.maxWidth < 380) {
                      return Column(
                        children: [
                          for (
                            var index = 0;
                            index < metricCards.length;
                            index++
                          )
                            Padding(
                              padding: EdgeInsets.only(
                                bottom: index == metricCards.length - 1
                                    ? 0
                                    : 12,
                              ),
                              child: metricCards[index],
                            ),
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: metricCards[0]),
                        const SizedBox(width: 12),
                        Expanded(child: metricCards[1]),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 18),
                _SectionCard(
                  title: 'Ventas de los últimos 7 días',
                  trailing: TextButton(
                    onPressed: () => context.push('/reports'),
                    child: const Text('Ver reportes'),
                  ),
                  child: SizedBox(
                    height: 230,
                    child: LineChart(
                      LineChartData(
                        minY: 0,
                        gridData: FlGridData(
                          show: true,
                          drawVerticalLine: false,
                          getDrawingHorizontalLine: (_) => FlLine(
                            color: Theme.of(
                              context,
                            ).dividerColor.withValues(alpha: 0.35),
                            strokeWidth: 1,
                          ),
                        ),
                        borderData: FlBorderData(show: false),
                        titlesData: FlTitlesData(
                          topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 44,
                              getTitlesWidget: (value, _) => Text(
                                '${chartCurrencies.length == 1 ? AppCurrency.optionFor(chartCurrencies.first).symbol : ''} ${_compactAmount(value)}',
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                            ),
                          ),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 30,
                              getTitlesWidget: (value, _) {
                                final index = value.toInt();
                                if (index < 0 ||
                                    index >= summary.lastSevenDays.length) {
                                  return const SizedBox.shrink();
                                }
                                return Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(
                                    _date.format(
                                      summary.lastSevenDays[index].date,
                                    ),
                                    style: Theme.of(
                                      context,
                                    ).textTheme.labelSmall,
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                        lineBarsData: [
                          for (
                            var series = 0;
                            series < (chartCurrencies.length);
                            series++
                          )
                            LineChartBarData(
                              spots: [
                                for (var index = 0; index < 7; index++)
                                  FlSpot(
                                    index.toDouble(),
                                    summary.lastSevenDays
                                        .where(
                                          (day) =>
                                              day.date ==
                                                  summary
                                                      .lastSevenDays
                                                      .first
                                                      .date
                                                      .add(
                                                        Duration(days: index),
                                                      ) &&
                                              day.currencyCode ==
                                                  chartCurrencies[series],
                                        )
                                        .fold<double>(
                                          0,
                                          (total, day) => total + day.amount,
                                        ),
                                  ),
                              ],
                              isCurved: true,
                              color: _chartColor(series),
                              barWidth: 3,
                              dotData: const FlDotData(show: true),
                              belowBarData: BarAreaData(
                                show: series == 0,
                                color: _chartColor(
                                  series,
                                ).withValues(alpha: 0.10),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                _SectionCard(
                  title: 'Productos más vendidos',
                  child: summary.bestSellers.isEmpty
                      ? const _EmptyMessage(
                          'Las ventas registradas aparecerán aquí.',
                        )
                      : Column(
                          children: [
                            for (
                              var index = 0;
                              index < summary.bestSellers.length;
                              index++
                            )
                              ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                leading: CircleAvatar(
                                  radius: 16,
                                  backgroundColor: Theme.of(
                                    context,
                                  ).colorScheme.primary.withValues(alpha: 0.1),
                                  child: Text('${index + 1}'),
                                ),
                                title: Text(summary.bestSellers[index].name),
                                trailing: Text(
                                  '${summary.bestSellers[index].quantity} u.',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                          ],
                        ),
                ),
                const SizedBox(height: 18),
                _SectionCard(
                  title: 'Productos con stock bajo',
                  trailing: PopupMenuButton<int>(
                    tooltip: 'Configurar umbral',
                    initialValue: state.threshold,
                    onSelected: (value) => context.read<DashboardBloc>().add(
                      UpdateLowStockThresholdEvent(value),
                    ),
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 3,
                        child: Text('Menos de 3 unidades'),
                      ),
                      PopupMenuItem(
                        value: 5,
                        child: Text('Menos de 5 unidades'),
                      ),
                      PopupMenuItem(
                        value: 10,
                        child: Text('Menos de 10 unidades'),
                      ),
                      PopupMenuItem(
                        value: 20,
                        child: Text('Menos de 20 unidades'),
                      ),
                    ],
                    child: Chip(
                      label: Text('Umbral: ${state.threshold}'),
                      avatar: const Icon(Icons.tune, size: 16),
                    ),
                  ),
                  child: summary.lowStock.isEmpty
                      ? const _EmptyMessage('Todo el inventario está al día.')
                      : Column(
                          children: summary.lowStock
                              .map(
                                (product) => ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: const Icon(
                                    Icons.warning_amber_rounded,
                                    color: Colors.orange,
                                  ),
                                  title: Text(product.name),
                                  subtitle: Text('Código: ${product.barcode}'),
                                  trailing: Text(
                                    '${product.stock} u.',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.orange,
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  String _compactAmount(double amount) {
    if (amount >= 100000) return '${(amount / 1000).toStringAsFixed(0)} mil';
    if (amount >= 1000) return '${(amount / 1000).toStringAsFixed(1)} mil';
    return amount.toStringAsFixed(0);
  }

  Color _chartColor(int index) {
    final colors = [
      Theme.of(context).colorScheme.primary,
      const Color(0xFF00897B),
      const Color(0xFF8E24AA),
      const Color(0xFFEF6C00),
      const Color(0xFF1976D2),
    ];
    return colors[index % colors.length];
  }
}

class _WelcomeCard extends StatelessWidget {
  final VoidCallback onNewSale;
  const _WelcomeCard({required this.onNewSale});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tu negocio, en una mirada',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Indicadores actualizados desde tu almacenamiento local.',
                  style: TextStyle(
                    color: Theme.of(
                      context,
                    ).colorScheme.onPrimary.withValues(alpha: 0.75),
                  ),
                ),
                const SizedBox(height: 18),
                FilledButton.tonalIcon(
                  onPressed: onNewSale,
                  icon: const Icon(Icons.add_shopping_cart),
                  label: const Text('Nueva venta'),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            Icons.insights_outlined,
            size: 48,
            color: Theme.of(
              context,
            ).colorScheme.onPrimary.withValues(alpha: 0.8),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget? trailing;

  const _SectionCard({required this.title, required this.child, this.trailing});

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (trailing case final Widget trailingWidget) trailingWidget,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    ),
  );
}

class _EmptyMessage extends StatelessWidget {
  final String message;
  const _EmptyMessage(this.message);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 18),
    child: Center(child: Text(message, textAlign: TextAlign.center)),
  );
}
