import 'package:flutter/foundation.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/theme_controller.dart';
import '../../../../core/utils/app_currency.dart';
import '../../../../core/widgets/metric_chart_card.dart';
import '../../../reports/domain/entities/sale_record.dart';
import '../bloc/dashboard_bloc.dart';
import '../../domain/entities/dashboard_summary.dart';
import '../utils/dashboard_greeting.dart';

final _dashboardDateFormat = DateFormat('EEE d', 'es');

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  late String _metricCurrencyCode;

  @override
  void initState() {
    super.initState();
    _metricCurrencyCode = AppCurrency.currentCode;
    context.read<DashboardBloc>().add(const LoadDashboardEvent());
  }

  @override
  Widget build(BuildContext context) {
    AppCurrencyScope.of(context);
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isWebDesktop = kIsWeb && screenWidth >= 900;
    final showBottomNavigation = !kIsWeb || screenWidth < 800;
    final webColors = _WebDashboardColors.of(context);
    return Scaffold(
      backgroundColor: isWebDesktop
          ? webColors.canvas
          : const Color(0xFFF5F7FA),
      appBar: isWebDesktop
          ? null
          : AppBar(
              title: const Text('Resumen'),
              actions: [
                IconButton(
                  tooltip: 'Cambiar tema',
                  onPressed: AppThemeController.toggle,
                  icon: Icon(
                    Theme.of(context).brightness == Brightness.dark
                        ? Icons.light_mode
                        : Icons.dark_mode,
                  ),
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
          return RefreshIndicator(
            onRefresh: () async => context.read<DashboardBloc>().add(
              LoadDashboardEvent(threshold: state.threshold),
            ),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
              children: [
                _WelcomeCard(
                  onNewSale: () => context.push('/new-sale'),
                  onOpenScale: () => context.push('/scale'),
                ),
                const SizedBox(height: 16),
                InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Mostrar métricas en',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 2,
                    ),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: metricCurrencyCode,
                      isExpanded: true,
                      items: [
                        for (final code in configuredCurrencies)
                          DropdownMenuItem(
                            value: code,
                            child: Text(
                              '$code - ${AppCurrency.optionFor(code).symbol}',
                            ),
                          ),
                      ],
                      onChanged: (code) {
                        if (code != null) {
                          setState(() => _metricCurrencyCode = code);
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (context, _) {
                    final dailyTrend = chartDays
                        .map((day) => day.amount)
                        .toList();
                    final metricCards = <Widget>[
                      MetricChartCard(
                        title: 'Ventas del día',
                        value: AppCurrency.format(
                          dailyTotal,
                          code: metricCurrencyCode,
                        ),
                        trend: dailyTrend,
                        subtitle:
                            '${summary.transactionCount} transacciones hoy · $metricCurrencyCode',
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
          ? NavigationBar(
              height: 72,
              selectedIndex: 0,
              labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
              indicatorColor: Theme.of(context).colorScheme.secondaryContainer,
              onDestinationSelected: (index) {
                const destinations = [
                  '/',
                  '/new-sale',
                  '/products',
                  '/customers',
                  '/settings',
                ];
                context.go(destinations[index]);
              },
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.space_dashboard_outlined),
                  selectedIcon: Icon(Icons.space_dashboard_rounded),
                  label: 'Inicio',
                ),
                NavigationDestination(
                  icon: Icon(Icons.point_of_sale_outlined),
                  selectedIcon: Icon(Icons.point_of_sale_rounded),
                  label: 'Venta',
                ),
                NavigationDestination(
                  icon: Icon(Icons.inventory_2_outlined),
                  selectedIcon: Icon(Icons.inventory_2_rounded),
                  label: 'Productos',
                ),
                NavigationDestination(
                  icon: Icon(Icons.people_outline_rounded),
                  selectedIcon: Icon(Icons.people_rounded),
                  label: 'Clientes',
                ),
                NavigationDestination(
                  icon: Icon(Icons.settings_outlined),
                  selectedIcon: Icon(Icons.settings_rounded),
                  label: 'Ajustes',
                ),
              ],
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

class _WelcomeCard extends StatelessWidget {
  final VoidCallback onNewSale;
  final VoidCallback onOpenScale;

  const _WelcomeCard({
    required this.onNewSale,
    required this.onOpenScale,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colors.primary,
            Color.lerp(colors.primary, const Color(0xFF102A43), 0.38)!,
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: colors.primary.withValues(alpha: 0.2),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(
            right: -14,
            top: -25,
            child: Icon(
              Icons.insights_rounded,
              size: 150,
              color: colors.onPrimary.withValues(alpha: 0.08),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.onPrimary.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 6,
                    ),
                    child: Text(
                      'PANEL DE CONTROL',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colors.onPrimary,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.1,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '¡${dashboardGreeting(DateTime.now())}!',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: colors.onPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'Bienvenido a tu panel de negocio. Revisa tus resultados y gestiona tus ventas desde aquí.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.onPrimary.withValues(alpha: 0.82),
                  ),
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    FilledButton.icon(
                      onPressed: onNewSale,
                      style: FilledButton.styleFrom(
                        backgroundColor: colors.onPrimary,
                        foregroundColor: colors.primary,
                        minimumSize: const Size(170, 48),
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      icon: const Icon(Icons.add_shopping_cart_rounded),
                      label: const Text(
                        'Nueva venta',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: onOpenScale,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: colors.onPrimary,
                        side: BorderSide(
                          color: colors.onPrimary.withValues(alpha: .55),
                        ),
                        minimumSize: const Size(180, 48),
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      icon: const Icon(Icons.scale_rounded),
                      label: const Text(
                        'Balanza digital',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WebDashboardColors {
  final bool isDark;

  const _WebDashboardColors(this.isDark);

  factory _WebDashboardColors.of(BuildContext context) =>
      _WebDashboardColors(Theme.of(context).brightness == Brightness.dark);

  Color get primary => AppThemeController.primaryColor.value;
  Color get onPrimary =>
      primary.computeLuminance() > 0.179 ? Colors.black : Colors.white;
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

  const _WebDashboardHeader({
    required this.lowStockCount,
    required this.lowStockThreshold,
    required this.onNavigate,
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

    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: colors.outlineVariant),
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
                        'Ventas de los últimos 7 días',
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
                      ? const Color(0xFFFFF1D6)
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
