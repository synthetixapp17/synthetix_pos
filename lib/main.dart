import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'config/routes/app_routes.dart';
import 'core/data/hive_database.dart';
import 'core/service_locator.dart' as di;
import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';
import 'core/utils/app_currency.dart';
import 'features/billing/presentation/bloc/billing_bloc.dart';
import 'features/product/presentation/bloc/product_bloc.dart';
import 'features/shop/presentation/bloc/shop_bloc.dart';
import 'features/settings/presentation/bloc/printer_bloc.dart';
import 'features/settings/presentation/bloc/printer_event.dart';
import 'features/customer/presentation/bloc/customer_bloc.dart';
import 'features/dashboard/presentation/bloc/dashboard_bloc.dart';
import 'features/reports/presentation/bloc/reports_bloc.dart';
import 'features/reports/domain/usecases/reports_usecases.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('es');
  await HiveDatabase.init();
  AppCurrency.loadSavedCurrency();
  AppThemeController.loadSavedMode();
  await di.init();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<ProductBloc>(
          create: (context) => di.sl<ProductBloc>()..add(LoadProducts()),
        ),
        BlocProvider<ShopBloc>(
          create: (context) => di.sl<ShopBloc>()..add(LoadShopEvent()),
        ),
        BlocProvider<BillingBloc>(
          create: (context) => BillingBloc(
            getProductByBarcodeUseCase: di.sl(),
            recordSaleUseCase: di.sl<RecordSaleUseCase>(),
          ),
        ),
        BlocProvider<PrinterBloc>(
          create: (context) => di.sl<PrinterBloc>()..add(InitPrinterEvent()),
        ),
        BlocProvider<CustomerBloc>(
          create: (context) =>
              di.sl<CustomerBloc>()..add(const LoadCustomersEvent()),
        ),
        BlocProvider<DashboardBloc>(
          create: (context) => di.sl<DashboardBloc>(),
        ),
        BlocProvider<ReportsBloc>(create: (context) => di.sl<ReportsBloc>()),
      ],
      child: ValueListenableBuilder<ThemeMode>(
        valueListenable: AppThemeController.mode,
        builder: (context, themeMode, _) => ValueListenableBuilder<Color>(
          valueListenable: AppThemeController.primaryColor,
          builder: (context, _, _) => ValueListenableBuilder<String>(
            valueListenable: AppCurrency.selectedCode,
            builder: (context, currencyCode, _) => AppCurrencyScope(
              currencyCode: currencyCode,
              child: MaterialApp.router(
                title: 'Gestión de ventas',
                theme: AppTheme.lightTheme,
                darkTheme: AppTheme.darkTheme,
                themeMode: themeMode,
                routerConfig: router,
                debugShowCheckedModeBanner: false,
                locale: const Locale('es'),
                supportedLocales: const [Locale('es'), Locale('en')],
                localizationsDelegates: GlobalMaterialLocalizations.delegates,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
