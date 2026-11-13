import 'package:flutter/foundation.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/theme_controller.dart';
import '../../../../core/utils/app_currency.dart';
import '../../../restaurant/data/restaurant_repository.dart';
import '../../../restaurant/domain/entities/restaurant_state.dart';
import '../../../reports/domain/entities/sale_record.dart';
import '../bloc/dashboard_bloc.dart';
import '../../domain/entities/dashboard_summary.dart';
import '../utils/dashboard_greeting.dart';
import '../widgets/multi_rate_calculator.dart';

final _dashboardDateFormat = DateFormat('EEE d', 'es');

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final _restaurantRepository = RestaurantRepository();
  RestaurantState _restaurantState = const RestaurantState();
  late String _metricCurrencyCode;

  @override
  void initState() {
    super.initState();
    _metricCurrencyCode = AppCurrency.currentCode;
    _loadRestaurantSummary();
    context.read<DashboardBloc>().add(const LoadDashboardEvent());
  }

  void _loadRestaurantSummary() {
    try {
      _restaurantState = _restaurantRepository.load();
    } catch (error) {
      final message = 'No se pudieron cargar las mesas: $error';
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      });
    }
  }

  void _refreshRestaurantSummary() {
    try {
      final nextState = _restaurantRepository.load();
      setState(() => _restaurantState = nextState);
    } catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudieron cargar las mesas: $error')),
      );
    }
  }

  Future<void> _openRestaurant() async {
    await context.push('/restaurant');
    if (mounted) _refreshRestaurantSummary();
  }

  @override
  Widget build(BuildContext context) {
    AppCurrencyScope.of(context);
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isWebDesktop = kIsWeb && screenWidth >= 900;
    final showBottomNavigation = !kIsWeb || screenWidth < 800;
    final webColors = _WebDashboardColors.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: isWebDesktop
          ? webColors.canvas
          : theme.scaffoldBackgroundColor,
      appBar: null,
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
          if (isWebDesktop) {
            return _buildWebDashboard(context, state, summary);
          }
          final configuredCurrencies =
              AppCurrency.configuredCurrencies.map((item) => item.code).toList()
                ..sort();
          final metricCurrencyCode =
              configuredCurrencies.contains(_metricCurrencyCode)
              ? _metricCurrencyCode
              : AppCurrency.baseCode;
          final metricExchangeRate = AppCurrency.rateFor(metricCurrencyCode);
          final chartDays = _dashboardChartDays(
            summary,
            metricExchangeRate,
            metricCurrencyCode,
          );
          final dailyTotal =
              summary.dailyUsdTotals.values.fold<double>(
                0,
                (total, amount) => total + amount,
              ) *
              metricExchangeRate;
          final occupiedTables = _restaurantState.tables
              .where((table) => table.isOpen)
              .length;
          return RefreshIndicator(
            onRefresh: () async {
              _refreshRestaurantSummary();
              context.read<DashboardBloc>().add(
                LoadDashboardEvent(threshold: state.threshold),
              );
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 36),
              children: [
                _MobileDashboardHeader(
                  lowStockCount: summary.lowStock.length,
                  onLowStock: () => context.push(
                    '/products?lowStock=1&threshold=${state.threshold}',
                  ),
                  onOpenRestaurant: _openRestaurant,
                  onOpenCalculator: () => showMultiRateCalculator(context),
                  onOpenScale: () => context.push('/scale'),
                  onToggleTheme: AppThemeController.toggle,
                ),
                const SizedBox(height: 24),
                _DailySalesCard(
                  total: dailyTotal,
                  currencyCode: metricCurrencyCode,
                  transactionCount: summary.transactionCount,
                  days: chartDays,
                  currencies: configuredCurrencies,
                  onCurrencyChanged: (code) {
                    setState(() => _metricCurrencyCode = code);
                  },
                ),
                const SizedBox(height: 24),
                Text(
                  'Métricas de hoy',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  height: 124,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: _PastelMetricCard(
                          title: 'Stock bajo',
                          value: '${summary.lowStock.length}',
                          detail:
                              '${summary.lowStock.where((product) => product.stock == 0).length} agotados',
                          color: theme.colorScheme.error,
                          icon: Icons.inventory_2_rounded,
                          onTap: () => context.push(
                            '/products?lowStock=1&threshold=${state.threshold}',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _PastelMetricCard(
                          title: 'Mesas ocupadas',
                          value:
                              '$occupiedTables / ${_restaurantState.tables.length}',
                          detail: 'en servicio',
                          color: const Color(0xFF2E7D32),
                          icon: Icons.table_restaurant_rounded,
                          onTap: _openRestaurant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                _SalesPerformanceCard(
                  days: chartDays,
                  currencyCode: metricCurrencyCode,
                  onReports: () => context.push('/reports'),
                ),
                const SizedBox(height: 18),
                _SectionCard(
                  title: 'Más vendidos hoy',
                  child: _BestSellerMetrics(products: summary.bestSellers),
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
      bottomNavigationBar: showBottomNavigation
          ? _DashboardBottomNavigation(
              onNavigate: (route) => context.go(route),
              onNewSale: () => context.push('/new-sale'),
            )
          : null,
    );
  }

  List<DailySales> _dashboardChartDays(
    DashboardSummary summary,
    double exchangeRate,
    String currencyCode,
  ) {
    final dates = summary.lastSevenDays.map((day) => day.date).toSet();
    return [
      for (final date in dates)
        DailySales(
          date: date,
          amount:
              summary.lastSevenDays
                  .where((day) => day.date == date)
                  .fold<double>(0, (total, day) => total + day.usdAmount) *
              exchangeRate,
          currencyCode: currencyCode,
        ),
    ];
  }

  Widget _buildWebDashboard(
    BuildContext context,
    DashboardState state,
    DashboardSummary summary,
  ) {
    final availableCurrencies =
        AppCurrency.configuredCurrencies.map((item) => item.code).toList()
          ..sort();
    final currentCurrency = availableCurrencies.contains(_metricCurrencyCode)
        ? _metricCurrencyCode
        : AppCurrency.baseCode;
    final currentRate = AppCurrency.rateFor(currentCurrency);
    final weeklySales = _dashboardChartDays(
      summary,
      currentRate,
      currentCurrency,
    );
    final weeklyTotal = weeklySales.fold<double>(
      0,
      (total, day) => total + day.amount,
    );
    final dailyUsdTotal = summary.dailyUsdTotals.values.fold<double>(
      0,
      (total, amount) => total + amount,
    );
    final dailyBalance = AppCurrency.format(
      dailyUsdTotal * currentRate,
      code: currentCurrency,
    );
    final colors = _WebDashboardColors.of(context);
    final weeklyColors = colors.chartColors;
    final chartMax = weeklySales.fold<double>(
      0,
      (maximum, day) => day.amount > maximum ? day.amount : maximum,
    );
    final recentSales = summary.recentSales;
    final lowStockCount = summary.lowStock.length;

    return RefreshIndicator(
      onRefresh: () async => context.read<DashboardBloc>().add(
        LoadDashboardEvent(threshold: state.threshold),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _WebDashboardHeader(
                  lowStockCount: lowStockCount,
                  lowStockThreshold: state.threshold,
                  onNavigate: (route) => context.go(route),
                  onOpenCalculator: () => showMultiRateCalculator(context),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  height: 330,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        flex: 6,
                        child: _WebBalanceCard(
                          currencies: availableCurrencies,
                          selectedCurrency: currentCurrency,
                          balance: dailyBalance,
                          onCurrencyChanged: (code) {
                            if (code != null) {
                              setState(() => _metricCurrencyCode = code);
                            }
                          },
                          onNewSale: () => context.push('/new-sale'),
                          onReports: () => context.push('/reports'),
                        ),
                      ),
                      const SizedBox(width: 18),
                      Expanded(
                        flex: 4,
                        child: _WebActivityCard(
                          transactions: summary.transactionCount,
                          lowStockCount: lowStockCount,
                          bestSellerUnits: summary.unitsSoldToday,
                          onInventory: () => context.push(
                            '/products?lowStock=1&threshold=${state.threshold}',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  height: 330,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        flex: 1,
                        child: _WebSummaryCard(
                          child: _WebWeeklyDonut(
                            days: weeklySales,
                            total: weeklyTotal,
                            colors: weeklyColors,
                            currencyCode: currentCurrency,
                          ),
                        ),
                      ),
                      const SizedBox(width: 18),
                      Expanded(
                        child: _WebSummaryCard(
                          child: _WebDailyBars(
                            days: weeklySales,
                            maximum: chartMax,
                            currencyCode: currentCurrency,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  height: 330,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: _WebSummaryCard(
                          child: _WebBestSellers(products: summary.bestSellers),
                        ),
                      ),
                      const SizedBox(width: 18),
                      Expanded(
                        child: _WebSummaryCard(
                          child: _WebRecentSales(sales: recentSales),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MobileDashboardHeader extends StatelessWidget {
  final int lowStockCount;
  final VoidCallback onLowStock;
  final VoidCallback onOpenRestaurant;
  final VoidCallback onOpenCalculator;
  final VoidCallback onOpenScale;
  final VoidCallback onToggleTheme;

  const _MobileDashboardHeader({
    required this.lowStockCount,
    required this.onLowStock,
    required this.onOpenRestaurant,
    required this.onOpenCalculator,
    required this.onOpenScale,
    required this.onToggleTheme,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'PANEL DE CONTROL',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                '¡${dashboardGreeting(now)}!',
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -.5,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                DateFormat('EEEE, d MMMM', 'es').format(now),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        Stack(
          clipBehavior: Clip.none,
          children: [
            _RoundHeaderButton(
              tooltip: lowStockCount == 0
                  ? 'Notificaciones'
                  : '$lowStockCount productos con stock bajo',
              icon: Icons.notifications_none_rounded,
              onPressed: onLowStock,
            ),
            if (lowStockCount > 0)
              Positioned(
                right: 0,
                top: 0,
                child: Container(
                  constraints: const BoxConstraints(
                    minWidth: 17,
                    minHeight: 17,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: const BoxDecoration(
                    color: Color(0xFFE24B5B),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '$lowStockCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(width: 8),
        PopupMenuButton<String>(
          tooltip: 'Más opciones',
          onSelected: (action) {
            switch (action) {
              case 'restaurant':
                onOpenRestaurant();
              case 'calculator':
                onOpenCalculator();
              case 'scale':
                onOpenScale();
              case 'theme':
                onToggleTheme();
              case 'low_stock':
                onLowStock();
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'restaurant',
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.table_restaurant_outlined),
                title: Text('Gestión de mesas'),
              ),
            ),
            const PopupMenuItem(
              value: 'calculator',
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.calculate_outlined),
                title: Text('Calculadora Multi-Tasa'),
              ),
            ),
            const PopupMenuItem(
              value: 'scale',
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.scale_outlined),
                title: Text('Balanza digital'),
              ),
            ),
            PopupMenuItem(
              value: 'theme',
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  theme.brightness == Brightness.dark
                      ? Icons.light_mode_outlined
                      : Icons.dark_mode_outlined,
                ),
                title: const Text('Cambiar tema'),
              ),
            ),
            if (lowStockCount > 0)
              PopupMenuItem(
                value: 'low_stock',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.inventory_2_outlined),
                  title: Text('Productos con stock bajo ($lowStockCount)'),
                ),
              ),
          ],
          child: const _RoundHeaderButton(
            tooltip: 'Más opciones',
            icon: Icons.more_horiz_rounded,
          ),
        ),
      ],
    );
  }
}

class _RoundHeaderButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  const _RoundHeaderButton({
    required this.tooltip,
    required this.icon,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surface,
      shape: CircleBorder(side: BorderSide(color: colors.outlineVariant)),
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

class _DailySalesCard extends StatelessWidget {
  final double total;
  final String currencyCode;
  final int transactionCount;
  final List<DailySales> days;
  final List<String> currencies;
  final ValueChanged<String> onCurrencyChanged;

  const _DailySalesCard({
    required this.total,
    required this.currencyCode,
    required this.transactionCount,
    required this.days,
    required this.currencies,
    required this.onCurrencyChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Ventas del día',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
              Container(
                padding: const EdgeInsets.only(left: 10, right: 5),
                decoration: BoxDecoration(
                  color: colors.surface.withValues(alpha: .75),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: currencyCode,
                    isDense: true,
                    icon: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 18,
                    ),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                    items: [
                      for (final code in currencies)
                        DropdownMenuItem(
                          value: code,
                          child: Text(
                            '$code · ${AppCurrency.optionFor(code).symbol}',
                          ),
                        ),
                    ],
                    onChanged: (code) {
                      if (code != null) onCurrencyChanged(code);
                    },
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppCurrency.format(total, code: currencyCode),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 29,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -1,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      '$transactionCount transacciones',
                      style: TextStyle(
                        color: colors.onPrimaryContainer.withValues(alpha: .75),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _MiniSalesBars(days: days),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniSalesBars extends StatelessWidget {
  final List<DailySales> days;

  const _MiniSalesBars({required this.days});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final amounts = days.length > 7
        ? days.sublist(days.length - 7).map((day) => day.amount).toList()
        : days.map((day) => day.amount).toList();
    while (amounts.length < 7) {
      amounts.insert(0, 0);
    }
    final maximum = amounts.fold<double>(
      0,
      (largest, amount) => amount > largest ? amount : largest,
    );
    return SizedBox(
      width: 62,
      height: 54,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var index = 0; index < amounts.length; index++)
            Container(
              width: 6,
              height: maximum == 0
                  ? 8
                  : (8 + 40 * amounts[index] / maximum).clamp(8, 48).toDouble(),
              decoration: BoxDecoration(
                color: index.isEven
                    ? colors.primary
                    : colors.onPrimaryContainer.withValues(alpha: .75),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
        ],
      ),
    );
  }
}

class _PastelMetricCard extends StatelessWidget {
  final String title;
  final String value;
  final String detail;
  final Color color;
  final IconData icon;
  final VoidCallback onTap;

  const _PastelMetricCard({
    required this.title,
    required this.value,
    required this.detail,
    required this.color,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = Color.alphaBlend(
      color.withValues(alpha: isDark ? .2 : .1),
      colors.surface,
    );
    final accent = isDark ? Color.lerp(color, Colors.white, .45)! : color;
    return Material(
      color: cardColor,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: colors.onSurfaceVariant,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerHighest,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, color: accent, size: 15),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.onSurface,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  height: 1,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                detail,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colors.onSurfaceVariant,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashboardBottomNavigation extends StatelessWidget {
  final ValueChanged<String> onNavigate;
  final VoidCallback onNewSale;

  const _DashboardBottomNavigation({
    required this.onNavigate,
    required this.onNewSale,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        child: Container(
          height: 70,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(36),
            border: Border.all(color: colors.outlineVariant),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: .16),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: _DashboardNavItem(
                  label: 'Inicio',
                  icon: Icons.home_filled,
                  selected: true,
                  onTap: () => onNavigate('/'),
                ),
              ),
              Expanded(
                child: _DashboardNavItem(
                  label: 'Productos',
                  icon: Icons.inventory_2_outlined,
                  onTap: () => onNavigate('/products'),
                ),
              ),
              Expanded(
                child: _DashboardNavItem(
                  label: 'Clientes',
                  icon: Icons.people_outline_rounded,
                  onTap: () => onNavigate('/customers'),
                ),
              ),
              Expanded(
                child: _DashboardNavItem(
                  label: 'Ajustes',
                  icon: Icons.settings_outlined,
                  onTap: () => onNavigate('/settings'),
                ),
              ),
              SizedBox(
                width: 58,
                child: IconButton(
                  tooltip: 'Nueva venta',
                  onPressed: onNewSale,
                  style: IconButton.styleFrom(
                    backgroundColor: colors.primary,
                    foregroundColor: colors.onPrimary,
                    fixedSize: const Size(48, 48),
                  ),
                  icon: const Icon(Icons.add_rounded, size: 29),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashboardNavItem extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _DashboardNavItem({
    required this.label,
    required this.icon,
    required this.onTap,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = selected ? colors.primary : colors.onSurfaceVariant;
    return Tooltip(
      message: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(28),
        child: SizedBox(
          height: 62,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(height: 3),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
                  fontSize: 9,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WebDashboardColors {
  final bool isDark;
  final Color primary;
  final Color onPrimary;

  const _WebDashboardColors(this.isDark, this.primary, this.onPrimary);

  factory _WebDashboardColors.of(BuildContext context) {
    final theme = Theme.of(context);
    return _WebDashboardColors(
      theme.brightness == Brightness.dark,
      theme.colorScheme.primary,
      theme.colorScheme.onPrimary,
    );
  }

  Color get selectedSurface =>
      Color.alphaBlend(primary.withValues(alpha: isDark ? .22 : .12), surface);
  List<Color> get chartColors => List.generate(
    7,
    (index) => Color.lerp(
      primary,
      isDark ? Colors.white : const Color(0xFF687386),
      index / 6,
    )!,
  );

  Color get canvas =>
      isDark ? const Color(0xFF10151B) : const Color(0xFFF0F2F5);
  Color get surface => isDark ? const Color(0xFF191F27) : Colors.white;
  Color get surfaceMuted =>
      isDark ? const Color(0xFF232B35) : const Color(0xFFF5F7F9);
  Color get border =>
      isDark ? const Color(0xFF303A46) : const Color(0xFFE9EDF2);
  Color get text => isDark ? const Color(0xFFF3F5F7) : const Color(0xFF1E2933);
  Color get secondary =>
      isDark ? const Color(0xFFB3BECA) : const Color(0xFF647184);
  Color get muted => isDark ? const Color(0xFF8793A3) : const Color(0xFF8490A0);
  Color get chartGrid =>
      isDark ? const Color(0xFF303A46) : const Color(0xFFE8EDF1);
  Color get emptyChart =>
      isDark ? const Color(0xFF2C3540) : const Color(0xFFE9EDF2);
  Color get iconSurface => selectedSurface;
  Color get iconAccent => primary;
  Color get successSurface => selectedSurface;
  Color get success => primary;
}

class _WebDashboardHeader extends StatelessWidget {
  final int lowStockCount;
  final int lowStockThreshold;
  final ValueChanged<String> onNavigate;
  final VoidCallback onOpenCalculator;

  const _WebDashboardHeader({
    required this.lowStockCount,
    required this.lowStockThreshold,
    required this.onNavigate,
    required this.onOpenCalculator,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = _WebDashboardColors.of(context);
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${dashboardGreeting(DateTime.now())}, bienvenido',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: colors.text,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                DateFormat('EEEE, d MMMM', 'es').format(DateTime.now()),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.muted,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          flex: 5,
          child: Center(
            child: Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: colors.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _WebNavigationPill(
                    label: 'Resumen',
                    selected: true,
                    onTap: () => onNavigate('/'),
                  ),
                  _WebNavigationPill(
                    label: 'Ventas',
                    onTap: () => onNavigate('/reports'),
                  ),
                  _WebNavigationPill(
                    label: 'Clientes',
                    onTap: () => onNavigate('/customers'),
                  ),
                  _WebNavigationPill(
                    label: 'Herramientas',
                    onTap: () => onNavigate('/settings'),
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          flex: 2,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _WebHeaderAction(
                tooltip: 'Calculadora Multi-Tasa',
                icon: Icons.calculate_outlined,
                onPressed: onOpenCalculator,
              ),
              const SizedBox(width: 8),
              _WebHeaderAction(
                tooltip: 'Buscar productos',
                icon: Icons.search_rounded,
                onPressed: () => onNavigate('/products'),
              ),
              const SizedBox(width: 8),
              Stack(
                clipBehavior: Clip.none,
                children: [
                  _WebHeaderAction(
                    tooltip: lowStockCount == 0
                        ? 'Notificaciones'
                        : '$lowStockCount productos con stock bajo',
                    icon: Icons.notifications_none_rounded,
                    onPressed: () => onNavigate(
                      lowStockCount == 0
                          ? '/settings'
                          : '/products?lowStock=1&threshold=$lowStockThreshold',
                    ),
                  ),
                  if (lowStockCount > 0)
                    Positioned(
                      right: -3,
                      top: -4,
                      child: Container(
                        constraints: const BoxConstraints(
                          minWidth: 18,
                          minHeight: 18,
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: const BoxDecoration(
                          color: Color(0xFFE24B5B),
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '$lowStockCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 8),
              _WebHeaderAction(
                tooltip: 'Cambiar tema',
                icon: Theme.of(context).brightness == Brightness.dark
                    ? Icons.light_mode_rounded
                    : Icons.dark_mode_rounded,
                onPressed: AppThemeController.toggle,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _WebNavigationPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _WebNavigationPill({
    required this.label,
    required this.onTap,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = _WebDashboardColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          backgroundColor: selected ? colors.primary : Colors.transparent,
          foregroundColor: selected
              ? colors.onPrimary
              : colors.isDark
              ? const Color(0xFFE8EDF2)
              : const Color(0xFF25312C),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          shape: const StadiumBorder(),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _WebHeaderAction extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  const _WebHeaderAction({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final colors = _WebDashboardColors.of(context);
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: colors.surface,
        foregroundColor: colors.secondary,
        fixedSize: const Size(42, 42),
        side: BorderSide(color: colors.border),
      ),
      icon: Icon(icon, size: 20),
    );
  }
}

class _WebBalanceCard extends StatelessWidget {
  final List<String> currencies;
  final String selectedCurrency;
  final String balance;
  final ValueChanged<String?> onCurrencyChanged;
  final VoidCallback onNewSale;
  final VoidCallback onReports;

  const _WebBalanceCard({
    required this.currencies,
    required this.selectedCurrency,
    required this.balance,
    required this.onCurrencyChanged,
    required this.onNewSale,
    required this.onReports,
  });

  @override
  Widget build(BuildContext context) {
    final webColors = _WebDashboardColors.of(context);
    final date = DateFormat('d MMM yyyy', 'es').format(DateTime.now());
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: webColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: webColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: webColors.isDark ? .18 : .045,
            ),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: selectedCurrency,
                    isExpanded: true,
                    onChanged: onCurrencyChanged,
                    style: TextStyle(
                      color: webColors.text,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                    items: [
                      for (final currency in currencies)
                        DropdownMenuItem(
                          value: currency,
                          child: Text(
                            '${AppCurrency.optionFor(currency).symbol} $currency',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'RESUMEN DE HOY',
                    style: TextStyle(
                      color: webColors.muted,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    date,
                    style: TextStyle(
                      color: webColors.secondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Ventas del día',
            style: TextStyle(
              color: webColors.secondary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 5),
          SizedBox(
            width: double.infinity,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                balance,
                maxLines: 1,
                style: TextStyle(
                  color: webColors.text,
                  fontSize: 48,
                  height: 1.08,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -2,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Tasa visualizada: 1 USD = '
            '${AppCurrency.rateFor(selectedCurrency).toStringAsFixed(2)} '
            '$selectedCurrency',
            style: TextStyle(color: webColors.muted, fontSize: 10),
          ),
          const Spacer(),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: onNewSale,
                  style: FilledButton.styleFrom(
                    backgroundColor: webColors.primary,
                    foregroundColor: webColors.onPrimary,
                    minimumSize: const Size(0, 46),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(13),
                    ),
                  ),
                  icon: const Icon(Icons.add_shopping_cart_rounded, size: 18),
                  label: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      'Nueva venta',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onReports,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: webColors.secondary,
                    minimumSize: const Size(0, 46),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    side: BorderSide(color: webColors.border),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(13),
                    ),
                  ),
                  icon: const Icon(Icons.bar_chart_rounded, size: 18),
                  label: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('Ver reportes'),
                  ),
                ),
              ),
              const SizedBox(width: 3),
              PopupMenuButton<String>(
                tooltip: 'Más opciones',
                onSelected: (route) => context.push(route),
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: '/products',
                    child: Text('Abrir inventario'),
                  ),
                  PopupMenuItem(
                    value: '/settings',
                    child: Text('Configuración'),
                  ),
                ],
                icon: Icon(Icons.more_horiz_rounded, color: webColors.primary),
              ),
              const SizedBox(width: 4),
              IconButton(
                tooltip: 'Iniciar nueva venta',
                onPressed: onNewSale,
                style: IconButton.styleFrom(
                  backgroundColor: webColors.primary,
                  foregroundColor: webColors.onPrimary,
                  fixedSize: const Size(46, 46),
                ),
                icon: const Icon(Icons.north_east_rounded, size: 20),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WebActivityCard extends StatelessWidget {
  final int transactions;
  final int lowStockCount;
  final double bestSellerUnits;
  final VoidCallback onInventory;

  const _WebActivityCard({
    required this.transactions,
    required this.lowStockCount,
    required this.bestSellerUnits,
    required this.onInventory,
  });

  @override
  Widget build(BuildContext context) {
    final palette = _WebDashboardColors.of(context);
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: palette.primary,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: palette.primary.withValues(alpha: .2),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: palette.onPrimary.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.bolt_rounded,
                      color: palette.onPrimary,
                      size: 14,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'PRIORIDAD',
                      style: TextStyle(
                        color: palette.onPrimary,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: .7,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Ver inventario',
                onPressed: onInventory,
                style: IconButton.styleFrom(
                  foregroundColor: palette.onPrimary,
                  fixedSize: const Size(36, 36),
                ),
                icon: const Icon(Icons.more_horiz_rounded),
              ),
            ],
          ),
          const Spacer(),
          Text(
            'Pulso del negocio',
            style: TextStyle(
              color: palette.onPrimary.withValues(alpha: .78),
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$transactions ventas',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: palette.onPrimary,
              fontSize: 36,
              height: 1.1,
              fontWeight: FontWeight.w900,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Actividad registrada hoy',
            style: TextStyle(
              color: palette.onPrimary.withValues(alpha: .72),
              fontSize: 12,
            ),
          ),
          const Spacer(),
          Row(
            children: [
              Expanded(
                child: _WebActivityStat(
                  icon: Icons.inventory_2_outlined,
                  label: 'Stock bajo',
                  value: '$lowStockCount',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _WebActivityStat(
                  icon: Icons.shopping_bag_outlined,
                  label: 'Unidades hoy',
                  value: '$bestSellerUnits',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WebActivityStat extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _WebActivityStat({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final palette = _WebDashboardColors.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .18),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, color: palette.onPrimary, size: 19),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    color: palette.onPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.onPrimary.withValues(alpha: .78),
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SalesPerformanceCard extends StatelessWidget {
  final List<DailySales> days;
  final String currencyCode;
  final VoidCallback onReports;

  const _SalesPerformanceCard({
    required this.days,
    required this.currencyCode,
    required this.onReports,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final total = days.fold<double>(0, (sum, day) => sum + day.amount);
    final maximumDay = days.fold<DailySales?>(
      null,
      (maximum, day) =>
          maximum == null || day.amount > maximum.amount ? day : maximum,
    );
    final highestAmount = days.fold<double>(
      0,
      (maximum, day) => day.amount > maximum ? day.amount : maximum,
    );
    final chartMaximum = highestAmount == 0 ? 1.0 : highestAmount * 1.25;
    final axisInterval = chartMaximum / 4;

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: theme.brightness == Brightness.dark ? .12 : .04,
            ),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Tendencia semanal',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Rendimiento diario · $currencyCode',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Ver reportes',
                  onPressed: onReports,
                  icon: const Icon(Icons.arrow_forward_rounded),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              AppCurrency.format(total, code: currencyCode),
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w900,
                letterSpacing: -.5,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                _SalesInsight(
                  icon: Icons.insights_rounded,
                  label: 'Promedio diario',
                  value: AppCurrency.format(
                    total / (days.isEmpty ? 1 : days.length),
                    code: currencyCode,
                  ),
                ),
                if (maximumDay != null)
                  _SalesInsight(
                    icon: Icons.emoji_events_outlined,
                    label:
                        'Mejor día · ${_dashboardDateFormat.format(maximumDay.date)}',
                    value: AppCurrency.format(
                      maximumDay.amount,
                      code: currencyCode,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            SizedBox(
              height: 190,
              child: LineChart(
                LineChartData(
                  minX: 0,
                  maxX: (days.length - 1).clamp(1, double.infinity).toDouble(),
                  minY: 0,
                  maxY: chartMaximum,
                  lineTouchData: LineTouchData(
                    handleBuiltInTouches: true,
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipColor: (_) => colors.inverseSurface,
                      tooltipBorderRadius: BorderRadius.circular(10),
                      getTooltipItems: (spots) => spots.map((spot) {
                        final index = spot.x.toInt();
                        if (index < 0 || index >= days.length) return null;
                        return LineTooltipItem(
                          '${DateFormat('EEE d MMM', 'es').format(days[index].date)}\n'
                          '${AppCurrency.format(spot.y, code: currencyCode)}',
                          TextStyle(
                            color: colors.onInverseSurface,
                            fontWeight: FontWeight.w700,
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: axisInterval,
                    getDrawingHorizontalLine: (_) => FlLine(
                      color: colors.outlineVariant.withValues(alpha: .55),
                      strokeWidth: 1,
                      dashArray: [4, 4],
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
                        interval: axisInterval,
                        getTitlesWidget: (value, _) => Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Text(
                            _compactChartValue(value),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
                        getTitlesWidget: (value, _) {
                          final index = value.toInt();
                          if (index < 0 || index >= days.length) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 7),
                            child: Text(
                              _dashboardDateFormat.format(days[index].date),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: [
                        for (var index = 0; index < days.length; index++)
                          FlSpot(index.toDouble(), days[index].amount),
                      ],
                      isCurved: true,
                      curveSmoothness: .28,
                      color: colors.primary,
                      barWidth: 3,
                      dotData: const FlDotData(show: true),
                      belowBarData: BarAreaData(
                        show: true,
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            colors.primary.withValues(alpha: .2),
                            colors.primary.withValues(alpha: .01),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SalesInsight extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _SalesInsight({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: colors.primary),
          const SizedBox(width: 7),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.labelSmall),
              Text(
                value,
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BestSellerMetrics extends StatelessWidget {
  final List<ProductSales> products;

  const _BestSellerMetrics({required this.products});

  @override
  Widget build(BuildContext context) {
    if (products.isEmpty) {
      return const _EmptyMessage('Las ventas de hoy aparecerán aquí.');
    }

    final theme = Theme.of(context);
    final totalUnits = products.fold<double>(
      0.0,
      (total, product) => total + product.quantity,
    );
    final maxQuantity = products.first.quantity;

    return Column(
      children: [
        for (var index = 0; index < products.length; index++) ...[
          if (index > 0) const SizedBox(height: 14),
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: index == 0
                      ? Color.alphaBlend(
                          const Color(0xFFB7791F).withValues(
                            alpha: theme.brightness == Brightness.dark
                                ? .18
                                : .1,
                          ),
                          theme.colorScheme.surface,
                        )
                      : theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: index == 0
                    ? const Icon(
                        Icons.emoji_events_rounded,
                        size: 18,
                        color: Color(0xFFB7791F),
                      )
                    : Text(
                        '${index + 1}',
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  products[index].name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '${products[index].quantity} u.',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: products[index].quantity / maxQuantity,
              minHeight: 7,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              color: index == 0
                  ? theme.colorScheme.primary
                  : theme.colorScheme.primary.withValues(alpha: .48),
            ),
          ),
          const SizedBox(height: 3),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              '${(products[index].quantity / totalUnits * 100).round()}% del top 5',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _WebSummaryCard extends StatelessWidget {
  final Widget child;

  const _WebSummaryCard({required this.child});

  @override
  Widget build(BuildContext context) {
    final palette = _WebDashboardColors.of(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 330),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: palette.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: palette.isDark ? .2 : .04),
            blurRadius: 22,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _WebWeeklyDonut extends StatelessWidget {
  final List<DailySales> days;
  final double total;
  final List<Color> colors;
  final String currencyCode;

  const _WebWeeklyDonut({
    required this.days,
    required this.total,
    required this.colors,
    required this.currencyCode,
  });

  @override
  Widget build(BuildContext context) {
    final palette = _WebDashboardColors.of(context);
    final nonZeroDays = days.where((day) => day.amount > 0).toList();
    final sections = nonZeroDays.isEmpty
        ? [
            PieChartSectionData(
              value: 1,
              color: palette.emptyChart,
              radius: 19,
              showTitle: false,
            ),
          ]
        : [
            for (var index = 0; index < nonZeroDays.length; index++)
              PieChartSectionData(
                value: nonZeroDays[index].amount,
                color: colors[days.indexOf(nonZeroDays[index]) % colors.length],
                radius: 19,
                showTitle: false,
              ),
          ];
    final recentDays = days.length > 4 ? days.sublist(days.length - 4) : days;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _WebCardHeading(
          title: 'Ventas de 7 días',
          subtitle: 'Distribución diaria',
          icon: Icons.pie_chart_outline_rounded,
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            SizedBox(
              width: 126,
              height: 144,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  PieChart(
                    PieChartData(
                      sections: sections,
                      centerSpaceRadius: 43,
                      sectionsSpace: 4,
                      pieTouchData: PieTouchData(enabled: false),
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'TOTAL',
                        style: TextStyle(
                          color: palette.muted,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: .8,
                        ),
                      ),
                      const SizedBox(height: 3),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          AppCurrency.format(total, code: currencyCode),
                          style: TextStyle(
                            color: palette.text,
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                children: [
                  for (var index = 0; index < recentDays.length; index++)
                    _WebDailyLegend(
                      day: recentDays[index],
                      color:
                          colors[days.indexOf(recentDays[index]) %
                              colors.length],
                      currencyCode: currencyCode,
                    ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'Total acumulado en $currencyCode',
          style: TextStyle(color: palette.muted, fontSize: 11),
        ),
      ],
    );
  }
}

class _WebBestSellers extends StatelessWidget {
  final List<ProductSales> products;

  const _WebBestSellers({required this.products});

  @override
  Widget build(BuildContext context) {
    final palette = _WebDashboardColors.of(context);
    final totalUnits = products.fold<double>(
      0.0,
      (total, product) => total + product.quantity,
    );
    final maxQuantity = products.isEmpty ? 1 : products.first.quantity;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _WebCardHeading(
          title: 'Más vendidos hoy',
          subtitle: 'Unidades por producto',
          icon: Icons.emoji_events_outlined,
        ),
        const SizedBox(height: 10),
        if (products.isEmpty)
          Expanded(
            child: Center(
              child: Text(
                'Las ventas de hoy aparecerán aquí.',
                textAlign: TextAlign.center,
                style: TextStyle(color: palette.muted, fontSize: 12),
              ),
            ),
          )
        else
          for (var index = 0; index < products.length; index++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        width: 26,
                        height: 26,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: index == 0
                              ? palette.selectedSurface
                              : palette.surfaceMuted,
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Text(
                          '${index + 1}',
                          style: TextStyle(
                            color: index == 0 ? palette.primary : palette.muted,
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          products[index].name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: palette.text,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${products[index].quantity} u. · '
                        '${(products[index].quantity / totalUnits * 100).round()}% del top 5',
                        style: TextStyle(
                          color: palette.text,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: products[index].quantity / maxQuantity,
                      minHeight: 5,
                      backgroundColor: palette.surfaceMuted,
                      color: index == 0 ? palette.primary : palette.success,
                    ),
                  ),
                ],
              ),
            ),
      ],
    );
  }
}

class _WebDailyLegend extends StatelessWidget {
  final DailySales day;
  final Color color;
  final String currencyCode;

  const _WebDailyLegend({
    required this.day,
    required this.color,
    required this.currencyCode,
  });

  @override
  Widget build(BuildContext context) {
    final palette = _WebDashboardColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              DateFormat('EEE d', 'es').format(day.date),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: palette.secondary,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 3),
          Flexible(
            child: Text(
              AppCurrency.format(day.amount, code: currencyCode),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: palette.text,
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WebDailyBars extends StatelessWidget {
  final List<DailySales> days;
  final double maximum;
  final String currencyCode;

  const _WebDailyBars({
    required this.days,
    required this.maximum,
    required this.currencyCode,
  });

  @override
  Widget build(BuildContext context) {
    final palette = _WebDashboardColors.of(context);
    final total = days.fold<double>(0, (sum, day) => sum + day.amount);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _WebCardHeading(
          title: 'Ventas diarias',
          subtitle: 'Últimos 7 días',
          icon: Icons.bar_chart_rounded,
        ),
        const SizedBox(height: 12),
        Text(
          AppCurrency.format(total, code: currencyCode),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: palette.text,
            fontSize: 25,
            fontWeight: FontWeight.w900,
            letterSpacing: -.7,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'Acumulado en $currencyCode',
          style: TextStyle(color: palette.muted, fontSize: 11),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 154,
          child: BarChart(
            BarChartData(
              maxY: maximum <= 0 ? 1 : maximum * 1.2,
              minY: 0,
              alignment: BarChartAlignment.spaceAround,
              barTouchData: BarTouchData(
                enabled: days.isNotEmpty,
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (_) => palette.surfaceMuted,
                  tooltipBorderRadius: BorderRadius.circular(10),
                  getTooltipItem: (group, _, rod, _) {
                    if (group.x < 0 || group.x >= days.length) return null;
                    final date = DateFormat(
                      'EEEE d MMM',
                      'es',
                    ).format(days[group.x].date);
                    return BarTooltipItem(
                      '$date\n${AppCurrency.format(rod.toY, code: currencyCode)}',
                      TextStyle(
                        color: palette.text,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    );
                  },
                ),
              ),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: maximum <= 0 ? 1 : maximum * 1.2 / 3,
                getDrawingHorizontalLine: (_) =>
                    FlLine(color: palette.chartGrid, strokeWidth: 0.8),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 36,
                    interval: maximum <= 0 ? 1 : maximum * 1.2 / 3,
                    getTitlesWidget: (value, _) => Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Text(
                        _compactChartValue(value),
                        style: TextStyle(color: palette.muted, fontSize: 9),
                      ),
                    ),
                  ),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 24,
                    getTitlesWidget: (value, _) {
                      final index = value.toInt();
                      if (index < 0 || index >= days.length) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 7),
                        child: Text(
                          DateFormat('EE', 'es').format(days[index].date),
                          style: TextStyle(color: palette.muted, fontSize: 9),
                        ),
                      );
                    },
                  ),
                ),
              ),
              barGroups: [
                for (var index = 0; index < days.length; index++)
                  BarChartGroupData(
                    x: index,
                    barRods: [
                      BarChartRodData(
                        toY: days[index].amount,
                        width: 18,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(8),
                        ),
                        gradient: LinearGradient(
                          colors: days[index].amount == 0
                              ? [palette.emptyChart, palette.emptyChart]
                              : [palette.primary, palette.chartColors.last],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

String _compactChartValue(double value) => value >= 1000
    ? '${(value / 1000).toStringAsFixed(value >= 10000 ? 0 : 1)}k'
    : value.toStringAsFixed(0);

class _WebRecentSales extends StatelessWidget {
  final List<SaleRecord> sales;

  const _WebRecentSales({required this.sales});

  @override
  Widget build(BuildContext context) {
    final palette = _WebDashboardColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _WebCardHeading(
          title: 'Transacciones',
          subtitle: 'Ventas recientes',
          icon: Icons.receipt_long_outlined,
        ),
        const SizedBox(height: 12),
        if (sales.isEmpty)
          SizedBox(
            height: 150,
            child: Center(
              child: Text(
                'Las ventas registradas aparecerán aquí.',
                textAlign: TextAlign.center,
                style: TextStyle(color: palette.muted, fontSize: 12),
              ),
            ),
          )
        else
          for (final sale in sales) _WebRecentSaleRow(sale: sale),
      ],
    );
  }
}

class _WebRecentSaleRow extends StatelessWidget {
  final SaleRecord sale;

  const _WebRecentSaleRow({required this.sale});

  @override
  Widget build(BuildContext context) {
    final palette = _WebDashboardColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: palette.successSurface,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(
              Icons.shopping_bag_outlined,
              color: palette.success,
              size: 17,
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sale.customerName?.trim().isNotEmpty == true
                      ? sale.customerName!
                      : 'Venta sin cliente',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.text,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${DateFormat('d MMM · HH:mm', 'es').format(sale.soldAt)} · '
                  '${sale.lines.length} prod.',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: palette.muted, fontSize: 9),
                ),
              ],
            ),
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              '+${AppCurrency.format(sale.total, code: sale.currencyCode)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: palette.success,
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WebCardHeading extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;

  const _WebCardHeading({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final palette = _WebDashboardColors.of(context);
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: palette.iconSurface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: palette.iconAccent, size: 19),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: palette.text,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: palette.muted, fontSize: 10),
              ),
            ],
          ),
        ),
      ],
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
