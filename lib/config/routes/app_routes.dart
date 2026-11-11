import 'package:go_router/go_router.dart';

import '../../core/widgets/web_app_shell.dart';
import '../../features/settings/presentation/pages/printer_settings_page.dart';
import '../../features/splash/data/splash_preferences.dart';
import '../../features/splash/presentation/pages/splash_page.dart';
import '../../features/billing/presentation/pages/home_page.dart';
import '../../features/billing/presentation/pages/product_catalog_page.dart';
import '../../features/billing/presentation/pages/scanner_page.dart';
import '../../features/billing/presentation/pages/digital_scale_page.dart';
import '../../features/product/presentation/pages/product_list_page.dart';
import '../../features/product/presentation/pages/add_product_page.dart';
import '../../features/product/presentation/pages/edit_product_page.dart';
import '../../features/shop/presentation/pages/shop_details_page.dart';
import '../../features/settings/presentation/pages/settings_page.dart';
import '../../features/settings/presentation/pages/receipt_settings_page.dart';
import '../../features/settings/presentation/pages/product_barcodes_page.dart';
import '../../features/settings/presentation/pages/quotation_settings_page.dart';
import '../../features/settings/presentation/pages/credit_settings_page.dart';
import '../../features/settings/presentation/pages/category_management_page.dart';
import '../../features/settings/presentation/pages/payment_methods_settings_page.dart';
import '../../features/billing/presentation/pages/checkout_page.dart';
import '../../features/product/domain/entities/product.dart';
import '../../features/dashboard/presentation/pages/dashboard_page.dart';
import '../../features/customer/domain/entities/customer.dart';
import '../../features/customer/presentation/pages/customer_list_page.dart';
import '../../features/customer/presentation/pages/customer_form_page.dart';
import '../../features/credit/presentation/pages/credit_list_page.dart';
import '../../features/credit/presentation/pages/credit_detail_page.dart';
import '../../features/reports/presentation/pages/reports_page.dart';
import '../../features/restaurant/presentation/pages/restaurant_page.dart';
import '../../features/restaurant/presentation/pages/restaurant_menu_page.dart';

final router = GoRouter(
  initialLocation: '/welcome',
  routes: [
    GoRoute(
      path: '/welcome',
      builder: (context, state) => SplashPage(
        imageData: SplashPreferences.imageData,
        onContinue: () => context.go('/'),
      ),
    ),
    ShellRoute(
      builder: (context, state, child) =>
          WebAppShell(location: state.uri.path, child: child),
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const DashboardPage(),
          routes: [
            GoRoute(
              path: 'checkout',
              builder: (context, state) {
                final extra = state.extra;
                final tableId = extra is Map
                    ? extra['tableId'] as String?
                    : null;
                final tableName = extra is Map
                    ? extra['tableName'] as String?
                    : null;
                return CheckoutPage(tableId: tableId, tableName: tableName);
              },
            ),
          ],
        ),
        GoRoute(
          path: '/new-sale',
          builder: (context, state) => const HomePage(),
          routes: [
            GoRoute(
              path: 'products',
              builder: (context, state) => const ProductCatalogPage(),
            ),
          ],
        ),
        GoRoute(
          path: '/restaurant',
          builder: (context, state) => const RestaurantPage(),
          routes: [
            GoRoute(
              path: 'menu',
              builder: (context, state) => const RestaurantMenuPage(),
            ),
          ],
        ),
        GoRoute(
          path: '/scan-code',
          builder: (context, state) => const ScannerPage(),
        ),
        GoRoute(
          path: '/scale',
          builder: (context, state) => const DigitalScalePage(),
        ),
        GoRoute(
          path: '/customers',
          builder: (context, state) => const CustomerListPage(),
        ),
        GoRoute(
          path: '/customers/new',
          builder: (context, state) => CustomerFormPage(
            quickCreate: state.uri.queryParameters['quick'] == '1',
            initialPhone: state.uri.queryParameters['phone'] ?? '',
          ),
        ),
        GoRoute(
          path: '/customers/edit',
          builder: (context, state) {
            final customer = state.extra as Customer?;
            if (customer == null) return const CustomerListPage();
            return CustomerFormPage(customer: customer);
          },
        ),
        GoRoute(
          path: '/reports',
          builder: (context, state) => ReportsPage(
            showToday: state.uri.queryParameters['period'] == 'today',
            saleId: state.uri.queryParameters['saleId'],
          ),
        ),
        GoRoute(
          path: '/settings',
          builder: (context, state) => const SettingsPage(),
        ),
        GoRoute(
          path: '/settings/receipt',
          builder: (context, state) => const ReceiptSettingsPage(),
        ),
        GoRoute(
          path: '/settings/printer',
          builder: (context, state) => const PrinterSettingsPage(),
        ),
        GoRoute(
          path: '/settings/barcodes',
          builder: (context, state) => const ProductBarcodesPage(),
        ),
        GoRoute(
          path: '/settings/credits',
          builder: (context, state) => const CreditListPage(),
          routes: [
            GoRoute(
              path: ':id',
              builder: (context, state) =>
                  CreditDetailPage(creditId: state.pathParameters['id']!),
            ),
          ],
        ),
        GoRoute(
          path: '/settings/categories',
          builder: (context, state) => const CategoryManagementPage(),
        ),
        GoRoute(
          path: '/settings/payment-methods',
          builder: (context, state) => const PaymentMethodsSettingsPage(),
        ),
        GoRoute(
          path: '/settings/quotation',
          builder: (context, state) => const QuotationSettingsPage(),
        ),
        GoRoute(
          path: '/settings/credit-document',
          builder: (context, state) => const CreditSettingsPage(),
        ),
        GoRoute(
          path: '/products',
          builder: (context, state) => ProductListPage(
            lowStockThreshold: state.uri.queryParameters['lowStock'] == '1'
                ? int.tryParse(state.uri.queryParameters['threshold'] ?? '')
                : null,
          ),
          routes: [
            GoRoute(
              path: 'add',
              builder: (context, state) => const AddProductPage(),
            ),
            GoRoute(
              path: 'edit/:id',
              builder: (context, state) {
                final product = state.extra as Product?;
                if (product == null) {
                  // If we land here without extra (e.g. deep link), go back to products for now.
                  return const ProductListPage();
                }
                return EditProductPage(product: product);
              },
            ),
          ],
        ),
        GoRoute(
          path: '/shop',
          builder: (context, state) => const ShopDetailsPage(),
        ),
      ],
    ),
  ],
);
