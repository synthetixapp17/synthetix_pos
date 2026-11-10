import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/data/hive_database.dart';
import '../../../../core/data/models/app_settings.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/theme_controller.dart';
import '../../../../core/utils/app_currency.dart';
import '../../../billing/presentation/bloc/billing_bloc.dart';
import '../../../customer/presentation/bloc/customer_bloc.dart';
import '../../../dashboard/presentation/bloc/dashboard_bloc.dart';
import '../../../product/presentation/bloc/product_bloc.dart';
import '../../../reports/presentation/bloc/reports_bloc.dart';
import '../../../shop/presentation/bloc/shop_bloc.dart';
import '../../data/csv_backup_exporter.dart';
import '../../data/csv_backup_importer.dart';
import '../../../splash/data/splash_preferences.dart';
import '../bloc/printer_bloc.dart';
import '../bloc/printer_event.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

enum _BackupScopeChoice {
  complete,
  products,
  categories,
  customers,
  sales,
  credits,
  configuration,
}

extension on _BackupScopeChoice {
  String get label => switch (this) {
    _BackupScopeChoice.complete => 'Copia completa (ZIP)',
    _BackupScopeChoice.products => 'Productos',
    _BackupScopeChoice.categories => 'Categorías',
    _BackupScopeChoice.customers => 'Clientes',
    _BackupScopeChoice.sales => 'Ventas',
    _BackupScopeChoice.credits => 'Créditos',
    _BackupScopeChoice.configuration => 'Tienda y configuración',
  };

  CsvBackupScope? get csvScope => switch (this) {
    _BackupScopeChoice.complete => null,
    _BackupScopeChoice.products => CsvBackupScope.products,
    _BackupScopeChoice.categories => CsvBackupScope.categories,
    _BackupScopeChoice.customers => CsvBackupScope.customers,
    _BackupScopeChoice.sales => CsvBackupScope.sales,
    _BackupScopeChoice.credits => CsvBackupScope.credits,
    _BackupScopeChoice.configuration => CsvBackupScope.configuration,
  };

  String get filePrefix => switch (this) {
    _BackupScopeChoice.complete => '',
    _BackupScopeChoice.products => 'respaldo_productos_',
    _BackupScopeChoice.categories => 'respaldo_categorias_',
    _BackupScopeChoice.customers => 'respaldo_clientes_',
    _BackupScopeChoice.sales => 'respaldo_ventas_',
    _BackupScopeChoice.credits => 'respaldo_creditos_',
    _BackupScopeChoice.configuration => 'respaldo_tienda_configuracion_',
  };
}

class _SettingsPageState extends State<SettingsPage> {
  final _generalSectionKey = GlobalKey();
  final _catalogSectionKey = GlobalKey();
  final _analyticsSectionKey = GlobalKey();
  final _documentsSectionKey = GlobalKey();
  final _preferencesSectionKey = GlobalKey();
  final _devicesSectionKey = GlobalKey();
  final _backupSectionKey = GlobalKey();
  late String _currencyCode;
  late int _stockThreshold;
  int _currencyDropdownVersion = 0;
  int _selectedSection = 0;
  bool _isExportingBackup = false;
  bool _isRestoringBackup = false;

  static const _settingsSections = [
    ('General', Icons.storefront_outlined),
    ('Catálogo', Icons.inventory_2_outlined),
    ('Análisis', Icons.bar_chart_outlined),
    ('Documentos', Icons.description_outlined),
    ('Preferencias', Icons.tune_rounded),
    ('Dispositivos', Icons.print_outlined),
    ('Respaldo', Icons.backup_outlined),
  ];

  List<GlobalKey> get _sectionKeys => [
    _generalSectionKey,
    _catalogSectionKey,
    _analyticsSectionKey,
    _documentsSectionKey,
    _preferencesSectionKey,
    _devicesSectionKey,
    _backupSectionKey,
  ];

  @override
  void initState() {
    super.initState();
    _currencyCode = AppCurrency.currentCode;
    _stockThreshold =
        HiveDatabase.settingsBox.get('low_stock_threshold', defaultValue: 5)
            as int;
    context.read<ShopBloc>().add(LoadShopEvent());
  }

  Future<void> _navigateToSection(int index) async {
    setState(() => _selectedSection = index);
    final targetContext = _sectionKeys[index].currentContext;
    if (targetContext == null) return;
    await Scrollable.ensureVisible(
      targetContext,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
      alignment: 0.06,
    );
  }

  Future<void> _saveCurrency(String? code) async {
    if (code == null) return;
    if (code == _currencyCode) return;
    if (context.read<BillingBloc>().state.cartItems.isNotEmpty) {
      setState(() => _currencyDropdownVersion++);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Finaliza o vacía la venta actual antes de cambiar la moneda.',
          ),
        ),
      );
      return;
    }

    try {
      await AppCurrency.setCurrentCode(code);
      if (mounted) {
        setState(() {
          _currencyCode = code;
          _currencyDropdownVersion++;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _currencyDropdownVersion++);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se pudo actualizar la moneda de cobro: $error'),
          ),
        );
      }
      return;
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Moneda de cobro predeterminada actualizada. Los precios del catálogo y su referencia permanecen en USD.',
          ),
        ),
      );
    }
  }

  Future<void> _saveThreshold(int? value) async {
    if (value == null) return;
    await HiveDatabase.settingsBox.put('low_stock_threshold', value);
    if (mounted) setState(() => _stockThreshold = value);
  }

  Future<_BackupScopeChoice?> _chooseBackupScope(String title) {
    const choices = _BackupScopeChoice.values;
    return showModalBottomSheet<_BackupScopeChoice>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      barrierColor: Colors.black54,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
              child: Text(title, style: Theme.of(context).textTheme.titleLarge),
            ),
            for (final choice in choices)
              ListTile(
                leading: Icon(
                  choice == _BackupScopeChoice.complete
                      ? Icons.folder_zip_outlined
                      : Icons.table_chart_outlined,
                ),
                title: Text(choice.label),
                subtitle: Text(
                  choice == _BackupScopeChoice.complete
                      ? 'Todos los datos en un solo archivo ZIP'
                      : 'Un archivo CSV; los demás datos se conservan',
                ),
                onTap: () => Navigator.pop(context, choice),
              ),
          ],
        ),
      ),
    );
  }

  String _scopeName(CsvBackupScope scope) => switch (scope) {
    CsvBackupScope.all => 'la copia completa',
    CsvBackupScope.products => 'productos',
    CsvBackupScope.categories => 'categorías',
    CsvBackupScope.customers => 'clientes',
    CsvBackupScope.sales => 'ventas',
    CsvBackupScope.credits => 'créditos',
    CsvBackupScope.configuration => 'tienda y configuración',
  };

  Future<void> _exportCsvBackup() async {
    if (_isExportingBackup) return;
    final choice = await _chooseBackupScope('¿Qué datos deseas exportar?');
    if (choice == null || !mounted) return;
    setState(() => _isExportingBackup = true);
    try {
      final exporter = CsvBackupExporter();
      final backup = choice == _BackupScopeChoice.complete
          ? exporter.createBackupPackage()
          : exporter.createBackup().singleWhere(
              (file) => file.name.startsWith(choice.filePrefix),
            );
      final isPackage = choice == _BackupScopeChoice.complete;
      await SharePlus.instance.share(
        ShareParams(
          title: isPackage
              ? 'Copia completa de seguridad'
              : 'Respaldo de ${choice.label.toLowerCase()}',
          text: isPackage
              ? 'Paquete ZIP con todos los datos del negocio.'
              : 'Archivo CSV de ${choice.label.toLowerCase()}.',
          files: [
            XFile.fromData(
              backup.bytes,
              mimeType: isPackage ? 'application/zip' : 'text/csv',
            ),
          ],
          fileNameOverrides: [backup.name],
          downloadFallbackEnabled: true,
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo exportar la copia: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _isExportingBackup = false);
    }
  }

  Future<void> _restoreCsvBackup() async {
    if (_isRestoringBackup) return;
    final billingBloc = context.read<BillingBloc>();
    final customerBloc = context.read<CustomerBloc>();
    final dashboardBloc = context.read<DashboardBloc>();
    final productBloc = context.read<ProductBloc>();
    final reportsBloc = context.read<ReportsBloc>();
    final shopBloc = context.read<ShopBloc>();
    final printerBloc = context.read<PrinterBloc>();
    final reportsFrom = reportsBloc.state.from;
    final reportsTo = reportsBloc.state.to;
    final messenger = ScaffoldMessenger.of(context);
    if (billingBloc.state.cartItems.isNotEmpty) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Finaliza o vacía la venta actual antes de restaurar una copia.',
          ),
        ),
      );
      return;
    }
    final choice = await _chooseBackupScope('¿Qué datos deseas restaurar?');
    if (choice == null || !mounted) return;

    try {
      final selectedFile = await FilePicker.pickFile(
        dialogTitle: choice == _BackupScopeChoice.complete
            ? 'Seleccionar CSV o paquete ZIP'
            : 'Seleccionar CSV de ${choice.label.toLowerCase()}',
        type: FileType.custom,
        allowedExtensions: choice == _BackupScopeChoice.complete
            ? ['csv', 'zip']
            : ['csv'],
      );
      if (selectedFile == null) return;
      final bytes = await selectedFile.readAsBytes();
      final importer = CsvBackupImporter();
      final plan = switch (selectedFile.extension?.toLowerCase()) {
        'csv' => importer.parseCsvFile(selectedFile.name, bytes),
        'zip' when choice == _BackupScopeChoice.complete =>
          importer.parsePackage(bytes),
        _ => throw const FormatException(
          'Selecciona un archivo CSV o ZIP de respaldo.',
        ),
      };
      final expectedScope = choice.csvScope;
      if (expectedScope != null && plan.scope != expectedScope) {
        throw FormatException(
          'El archivo seleccionado contiene ${_scopeName(plan.scope)}, '
          'no ${choice.label.toLowerCase()}.',
        );
      }
      if (!mounted) return;
      final summary = importer.summarize(plan);
      final details = switch (plan.scope) {
        CsvBackupScope.all => [
          '${summary.products} productos',
          '${summary.categories} categorías',
          '${summary.customers} clientes',
          '${summary.sales} ventas',
          '${summary.credits} créditos',
        ],
        CsvBackupScope.products => ['${summary.products} productos'],
        CsvBackupScope.categories => ['${summary.categories} categorías'],
        CsvBackupScope.customers => ['${summary.customers} clientes'],
        CsvBackupScope.sales => ['${summary.sales} ventas'],
        CsvBackupScope.credits => ['${summary.credits} créditos'],
        CsvBackupScope.configuration => [
          'Configuración de la tienda y preferencias',
        ],
      };
      final replacesAllData = plan.scope == CsvBackupScope.all;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(
            replacesAllData
                ? 'Reemplazar datos actuales'
                : 'Restaurar CSV seleccionado',
          ),
          content: Text(
            '${replacesAllData ? 'Se reemplazarán todos los datos locales' : 'Se reemplazarán solo los datos de este archivo; los demás se conservarán'} '
            'usando "${selectedFile.name}":\n\n'
            '${details.map((item) => '• $item').join('\n')}\n\n'
            'Si el archivo o el paquete tiene datos faltantes o inválidos, no se aplicará.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(
                replacesAllData ? 'Reemplazar y restaurar' : 'Restaurar CSV',
              ),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;

      setState(() => _isRestoringBackup = true);
      await importer.restore(plan);
      await AppThemeController.loadSavedMode();
      AppCurrency.loadSavedCurrency();
      await AppCurrency.ensureSettings();
      billingBloc.add(ClearCartEvent());
      customerBloc.add(const LoadCustomersEvent());
      dashboardBloc.add(
        LoadDashboardEvent(
          threshold:
              HiveDatabase.settingsBox.get(
                    'low_stock_threshold',
                    defaultValue: 5,
                  )
                  as int,
        ),
      );
      productBloc.add(LoadProducts());
      if (reportsFrom != null && reportsTo != null) {
        reportsBloc.add(LoadReportsEvent(from: reportsFrom, to: reportsTo));
      }
      shopBloc.add(LoadShopEvent());
      printerBloc.add(InitPrinterEvent());
      if (mounted) {
        setState(() {
          _currencyCode = AppCurrency.currentCode;
          _stockThreshold =
              HiveDatabase.settingsBox.get(
                    'low_stock_threshold',
                    defaultValue: 5,
                  )
                  as int;
          _currencyDropdownVersion++;
        });
        messenger.showSnackBar(
          const SnackBar(content: Text('Copia restaurada correctamente.')),
        );
      }
    } catch (error) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('No se pudo restaurar la copia: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _isRestoringBackup = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Configuración'),
        centerTitle: false,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(58),
          child: SizedBox(
            height: 58,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
              scrollDirection: Axis.horizontal,
              itemCount: _settingsSections.length,
              separatorBuilder: (context, index) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final section = _settingsSections[index];
                final selected = _selectedSection == index;
                return ChoiceChip(
                  avatar: Icon(
                    section.$2,
                    size: 18,
                    color: selected ? colors.onSecondaryContainer : null,
                  ),
                  label: Text(section.$1),
                  selected: selected,
                  showCheckmark: false,
                  onSelected: (_) => _navigateToSection(index),
                  backgroundColor: colors.surface,
                  selectedColor: colors.secondaryContainer,
                  side: BorderSide(
                    color: selected
                        ? colors.secondary.withValues(alpha: .25)
                        : colors.outlineVariant,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  labelStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: selected ? colors.onSecondaryContainer : null,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                );
              },
            ),
          ),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1120),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: [
              Container(
                key: _generalSectionKey,
                margin: const EdgeInsets.only(bottom: 22),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      colors.primaryContainer,
                      Color.lerp(colors.primaryContainer, colors.surface, .3)!,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: colors.primary.withValues(alpha: .1),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                        color: colors.primary.withValues(alpha: .1),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Icon(
                        Icons.tune_rounded,
                        color: colors.primary,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'CENTRO DE ADMINISTRACIÓN',
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: colors.primary,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.1,
                                ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            'Todo tu negocio, bajo control',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Configura tu tienda, personaliza la experiencia y administra tus herramientas.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              _BusinessProfileCard(onTap: () => context.push('/shop')),
              const SizedBox(height: 22),
              _SectionTitle(
                key: _catalogSectionKey,
                title: 'Catálogo y clientes',
                subtitle: 'Administra productos, existencias y contactos.',
              ),
              _SettingsGroup(
                children: [
                  _SettingsTile(
                    icon: Icons.inventory_2_outlined,
                    title: 'Productos',
                    subtitle: 'Imágenes, precios, códigos y existencias',
                    onTap: () => context.push('/products'),
                  ),
                  const _SettingsDivider(),
                  _SettingsTile(
                    icon: Icons.category_outlined,
                    title: 'Categorías',
                    subtitle: 'Crea y organiza categorías para tus productos',
                    onTap: () => context.push('/settings/categories'),
                  ),
                  const _SettingsDivider(),
                  _SettingsTile(
                    icon: Icons.account_balance_wallet_outlined,
                    title: 'Formas de pago',
                    subtitle: 'Crea y edita las opciones que acepta tu negocio',
                    onTap: () => context.push('/settings/payment-methods'),
                  ),
                  const _SettingsDivider(),
                  _SettingsTile(
                    icon: Icons.people_outline,
                    title: 'Clientes',
                    subtitle: 'Directorio y datos de contacto',
                    onTap: () => context.push('/customers'),
                  ),
                  const _SettingsDivider(),
                  _SettingsTile(
                    icon: Icons.account_balance_wallet_outlined,
                    title: 'Compras a crédito',
                    subtitle: 'Saldos, abonos y comprobantes por cliente',
                    onTap: () => context.push('/settings/credits'),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _SectionTitle(
                key: _documentsSectionKey,
                title: 'Documentos y etiquetas',
                subtitle: 'Personaliza lo que compartes e imprimes.',
              ),
              _SettingsGroup(
                children: [
                  _SettingsTile(
                    icon: Icons.storefront_outlined,
                    title: 'Datos de la tienda',
                    subtitle: 'Logotipo, dirección y recibos',
                    onTap: () => context.push('/shop'),
                  ),
                  const _SettingsDivider(),
                  _SettingsTile(
                    icon: Icons.receipt_long_outlined,
                    title: 'Diseño del ticket',
                    subtitle: 'Vista previa y campos impresos',
                    onTap: () => context.push('/settings/receipt'),
                  ),
                  const _SettingsDivider(),
                  _SettingsTile(
                    icon: Icons.request_quote_outlined,
                    title: 'Cotización',
                    subtitle: 'Activa, diseña y consulta cotizaciones PDF',
                    onTap: () => context.push('/settings/quotation'),
                  ),
                  const _SettingsDivider(),
                  _SettingsTile(
                    icon: Icons.description_outlined,
                    title: 'Contrato de crédito',
                    subtitle: 'Diseño, colores y cláusulas del PDF de créditos',
                    onTap: () => context.push('/settings/credit-document'),
                  ),
                  const _SettingsDivider(),
                  _SettingsTile(
                    icon: Icons.qr_code_scanner,
                    title: 'Códigos de barras',
                    subtitle: 'Consulta e imprime etiquetas de productos',
                    onTap: () => context.push('/settings/barcodes'),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _SectionTitle(
                key: _analyticsSectionKey,
                title: 'Análisis del negocio',
                subtitle: 'Revisa ventas y rendimiento de tu operación.',
              ),
              _SettingsGroup(
                children: [
                  _SettingsTile(
                    icon: Icons.bar_chart_outlined,
                    title: 'Reportes y métricas',
                    subtitle: 'Ventas, productos y rendimiento por categoría',
                    onTap: () => context.push('/reports'),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              _SectionTitle(
                key: _preferencesSectionKey,
                title: 'Preferencias del negocio',
                subtitle:
                    'Ajusta moneda, inventario y apariencia de la aplicación.',
              ),
              _SettingsGroup(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                    child: DropdownButtonFormField<String>(
                      key: ValueKey(_currencyDropdownVersion),
                      initialValue: _currencyCode,
                      decoration: const InputDecoration(
                        labelText: 'Moneda predeterminada de cobro',
                        helperText:
                            'Los precios del catálogo siempre usan USD como referencia.',
                        prefixIcon: Icon(Icons.currency_exchange),
                      ),
                      items: AppCurrency.configuredCurrencies
                          .map(
                            (currency) => DropdownMenuItem(
                              value: currency.code,
                              child: Text(
                                '${currency.symbol}  ${currency.code}',
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: _saveCurrency,
                    ),
                  ),
                  const _SettingsDivider(),
                  _CurrencyRatesSection(
                    key: ValueKey(_currencyDropdownVersion),
                  ),
                  const _SettingsDivider(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                    child: DropdownButtonFormField<int>(
                      initialValue: _stockThreshold,
                      decoration: const InputDecoration(
                        labelText: 'Aviso de existencias bajas',
                        helperText:
                            'Los productos por debajo de este número aparecerán en el resumen.',
                        prefixIcon: Icon(Icons.warning_amber_outlined),
                      ),
                      items: const [3, 5, 10, 15, 20].map((value) {
                        return DropdownMenuItem(
                          value: value,
                          child: Text('Menos de $value unidades'),
                        );
                      }).toList(),
                      onChanged: _saveThreshold,
                    ),
                  ),
                  const _SettingsDivider(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 15, 16, 12),
                    child: ValueListenableBuilder<ThemeMode>(
                      valueListenable: AppThemeController.mode,
                      builder: (context, mode, _) =>
                          DropdownButtonFormField<ThemeMode>(
                            initialValue: mode,
                            decoration: const InputDecoration(
                              labelText: 'Apariencia',
                              prefixIcon: Icon(Icons.brightness_6_outlined),
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: ThemeMode.system,
                                child: Text('Seguir el sistema'),
                              ),
                              DropdownMenuItem(
                                value: ThemeMode.light,
                                child: Text('Claro'),
                              ),
                              DropdownMenuItem(
                                value: ThemeMode.dark,
                                child: Text('Oscuro'),
                              ),
                            ],
                            onChanged: (value) {
                              if (value != null) {
                                AppThemeController.setMode(value);
                              }
                            },
                          ),
                    ),
                  ),
                  const _SettingsDivider(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
                    child: ValueListenableBuilder<Color>(
                      valueListenable: AppThemeController.primaryColor,
                      builder: (context, selectedColor, _) => Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.palette_outlined),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Color principal',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleSmall,
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      'Se aplica al menú, botones y elementos principales de toda la plataforma.',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: selectedColor.withValues(alpha: .08),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: selectedColor.withValues(alpha: .2),
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 30,
                                  height: 30,
                                  decoration: BoxDecoration(
                                    color: selectedColor,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: selectedColor.withValues(
                                          alpha: .3,
                                        ),
                                        blurRadius: 8,
                                        offset: const Offset(0, 3),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Color seleccionado',
                                        style: Theme.of(
                                          context,
                                        ).textTheme.labelSmall,
                                      ),
                                      Text(
                                        _colorName(selectedColor),
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleSmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.bold,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(Icons.check_circle, color: selectedColor),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final columns = (constraints.maxWidth / 82)
                                  .floor()
                                  .clamp(3, 5);
                              return GridView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount:
                                    AppThemeController.availableColors.length,
                                gridDelegate:
                                    SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: columns,
                                      mainAxisSpacing: 8,
                                      crossAxisSpacing: 8,
                                      childAspectRatio: 1.15,
                                    ),
                                itemBuilder: (context, index) {
                                  final color =
                                      AppThemeController.availableColors[index];
                                  final selected =
                                      color.toARGB32() ==
                                      selectedColor.toARGB32();
                                  return Semantics(
                                    button: true,
                                    selected: selected,
                                    label: 'Color ${_colorName(color)}',
                                    child: InkWell(
                                      onTap: () =>
                                          AppThemeController.setPrimaryColor(
                                            color,
                                          ),
                                      borderRadius: BorderRadius.circular(12),
                                      child: AnimatedContainer(
                                        duration: const Duration(
                                          milliseconds: 180,
                                        ),
                                        decoration: BoxDecoration(
                                          color: selected
                                              ? color.withValues(alpha: .1)
                                              : Theme.of(
                                                  context,
                                                ).colorScheme.surface,
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          border: Border.all(
                                            color: selected
                                                ? color
                                                : Theme.of(
                                                    context,
                                                  ).dividerColor,
                                            width: selected ? 1.5 : 1,
                                          ),
                                        ),
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Container(
                                              width: 28,
                                              height: 28,
                                              decoration: BoxDecoration(
                                                color: color,
                                                shape: BoxShape.circle,
                                              ),
                                              child: selected
                                                  ? Icon(
                                                      Icons.check,
                                                      color: AppTheme.onColor(
                                                        color,
                                                      ),
                                                      size: 18,
                                                    )
                                                  : null,
                                            ),
                                            const SizedBox(height: 5),
                                            Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 3,
                                                  ),
                                              child: Text(
                                                _colorName(color),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: Theme.of(
                                                  context,
                                                ).textTheme.labelSmall,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  const _SettingsDivider(),
                  const _SplashImageSettings(),
                ],
              ),
              const SizedBox(height: 22),
              _SectionTitle(
                key: _devicesSectionKey,
                title: 'Dispositivos',
                subtitle: 'Gestiona la conexión y el formato de impresión.',
              ),
              _SettingsGroup(
                children: [
                  _SettingsTile(
                    icon: Icons.print_outlined,
                    title: 'Impresora térmica',
                    subtitle:
                        'Tamaño del papel, dispositivos y prueba de impresión',
                    onTap: () => context.push('/settings/printer'),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              _SectionTitle(
                key: _backupSectionKey,
                title: 'Copia de seguridad',
                subtitle:
                    'Exporta tus datos locales para guardarlos o compartirlos.',
              ),
              _SettingsGroup(
                children: [
                  _SettingsTile(
                    icon: Icons.download_outlined,
                    title: 'Exportar datos en CSV',
                    subtitle:
                        'Elige una copia completa o exporta productos, categorías y otros datos por separado.',
                    onTap: _isExportingBackup ? null : _exportCsvBackup,
                    trailing: _isExportingBackup
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.ios_share_outlined),
                  ),
                  const _SettingsDivider(),
                  _SettingsTile(
                    icon: Icons.settings_backup_restore_outlined,
                    title: 'Restaurar copia de seguridad',
                    subtitle:
                        'Restaura un tipo de dato desde su CSV o todos los datos desde un ZIP.',
                    onTap: _isRestoringBackup ? null : _restoreCsvBackup,
                    trailing: _isRestoringBackup
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.upload_file_outlined),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 0, 16, 14),
                    child: Text(
                      'Las imágenes y el logotipo se incluyen codificados en Base64. La restauración reemplaza los datos actuales; conserva una copia antes de continuar.',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              const _SectionTitle(
                title: 'Acceso rápido',
                subtitle: 'Consulta los datos importantes de tu operación.',
              ),
              _SettingsGroup(
                children: [
                  _SettingsTile(
                    icon: Icons.space_dashboard_outlined,
                    title: 'Resumen del negocio',
                    subtitle: 'Ventas del día y estado del inventario',
                    onTap: () => context.go('/'),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Center(
                child: Text(
                  'Gestión de ventas · Datos almacenados en este dispositivo',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _colorName(Color color) {
    final names = {
      0xFF111111: 'negro',
      0xFF263238: 'grafito',
      0xFF37474F: 'pizarra oscuro',
      0xFF0D47A1: 'azul marino',
      0xFF1565C0: 'azul',
      0xFF1976D2: 'azul brillante',
      0xFF0277BD: 'azul océano',
      0xFF00838F: 'turquesa',
      0xFF00695C: 'verde',
      0xFF2E7D32: 'esmeralda',
      0xFF558B2F: 'verde oliva',
      0xFFF9A825: 'dorado',
      0xFF6A1B9A: 'violeta',
      0xFF4527A0: 'índigo',
      0xFF5E35B1: 'amatista',
      0xFFAD1457: 'rosa',
      0xFFC62828: 'rojo',
      0xFFD84315: 'terracota',
      0xFFEF6C00: 'naranja',
      0xFF827717: 'oliva',
      0xFF455A64: 'pizarra',
      0xFF5D4037: 'marrón',
      0xFF795548: 'café',
      0xFF8D6E63: 'arena',
      0xFF607D8B: 'azul grisáceo',
      0xFF00897B: 'jade',
    };
    return names[color.toARGB32()] ?? 'personalizado';
  }
}

class _SplashImageSettings extends StatefulWidget {
  const _SplashImageSettings();

  @override
  State<_SplashImageSettings> createState() => _SplashImageSettingsState();
}

class _SplashImageSettingsState extends State<_SplashImageSettings> {
  Uint8List? _imageBytes;
  bool _isSaving = false;
  bool _hasInvalidImage = false;

  @override
  void initState() {
    super.initState();
    final imageData = SplashPreferences.imageData;
    if (imageData == null) return;
    try {
      _imageBytes = base64Decode(imageData);
    } on FormatException {
      _hasInvalidImage = true;
    }
  }

  Future<void> _pickImage() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    try {
      final selected = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1400,
        maxHeight: 1400,
      );
      if (selected == null || !mounted) return;
      final bytes = await selected.readAsBytes();
      await SplashPreferences.saveImage(base64Encode(bytes));
      if (!mounted) return;
      setState(() {
        _imageBytes = bytes;
        _hasInvalidImage = false;
        _isSaving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Imagen de bienvenida guardada.')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo guardar la imagen: $error')),
      );
    } finally {
      if (mounted && _isSaving) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _removeImage() async {
    setState(() => _isSaving = true);
    try {
      await SplashPreferences.clearImage();
      if (!mounted) return;
      setState(() {
        _imageBytes = null;
        _hasInvalidImage = false;
        _isSaving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Se restauró el logo predeterminado de bienvenida.'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo quitar la imagen: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.image_outlined,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Imagen de bienvenida',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Personaliza el logo que aparece en la pantalla de inicio.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            height: 170,
            width: double.infinity,
            child: _imageBytes == null
                ? Image.asset(
                    'assets/images/logo.png',
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) =>
                        _defaultImagePlaceholder(context),
                  )
                : Image.memory(
                    _imageBytes!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) =>
                        _defaultImagePlaceholder(context),
                  ),
          ),
        ),
        if (_hasInvalidImage) ...[
          const SizedBox(height: 8),
          Text(
            'La imagen guardada no es válida. Selecciona otra imagen.',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 14),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            FilledButton.tonalIcon(
              onPressed: _isSaving ? null : _pickImage,
              icon: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.upload_rounded),
              label: Text(
                _isSaving
                    ? 'Guardando…'
                    : _imageBytes == null
                    ? 'Elegir imagen'
                    : 'Cambiar imagen',
              ),
            ),
            if (_imageBytes != null || _hasInvalidImage)
              OutlinedButton.icon(
                onPressed: _isSaving ? null : _removeImage,
                icon: const Icon(Icons.restore_rounded),
                label: const Text('Usar logo predeterminado'),
              ),
          ],
        ),
      ],
    ),
  );

  Widget _defaultImagePlaceholder(BuildContext context) => ColoredBox(
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    child: Center(
      child: Icon(
        Icons.image_not_supported_outlined,
        size: 38,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}

class _CurrencyRatesSection extends StatefulWidget {
  const _CurrencyRatesSection({super.key});

  @override
  State<_CurrencyRatesSection> createState() => _CurrencyRatesSectionState();
}

class _CurrencyRatesSectionState extends State<_CurrencyRatesSection> {
  late List<CurrencyConfig> _currencies;
  final Map<String, TextEditingController> _rateControllers = {};
  bool _isAdding = false;
  String? _savingCode;

  @override
  void initState() {
    super.initState();
    _currencies = AppCurrency.configuredCurrencies;
    _syncControllers();
  }

  @override
  void dispose() {
    for (final controller in _rateControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _syncControllers() {
    for (final currency in _currencies) {
      _rateControllers.putIfAbsent(
        currency.code,
        () => TextEditingController(text: currency.rate.toString()),
      );
      _rateControllers[currency.code]!.text = currency.rate.toString();
    }
  }

  Future<void> _addCurrency() async {
    final available = AppCurrency.options
        .where(
          (option) =>
              !_currencies.any((currency) => currency.code == option.code),
        )
        .toList();
    if (available.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ya están agregadas todas las monedas.')),
      );
      return;
    }
    final code = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final option in available)
              ListTile(
                leading: const Icon(Icons.currency_exchange_outlined),
                title: Text('${option.code} - ${option.symbol}'),
                subtitle: Text(option.name),
                onTap: () => Navigator.pop(context, option.code),
              ),
          ],
        ),
      ),
    );
    if (code == null || !mounted) return;
    setState(() => _isAdding = true);
    try {
      await AppCurrency.addCurrency(code);
      if (!mounted) return;
      setState(() {
        _currencies = AppCurrency.configuredCurrencies;
        _syncControllers();
        _isAdding = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _isAdding = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo agregar la moneda: $error')),
      );
    }
  }

  Future<void> _saveRate(CurrencyConfig currency) async {
    final rate = double.tryParse(
      _rateControllers[currency.code]!.text.trim().replaceAll(',', '.'),
    );
    if (rate == null || !rate.isFinite || rate <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ingresa una tasa válida mayor que cero.'),
        ),
      );
      return;
    }
    setState(() => _savingCode = currency.code);
    try {
      await AppCurrency.saveCurrencies([
        for (final configured in _currencies)
          configured.code == currency.code
              ? configured.copyWith(rate: rate)
              : configured,
      ]);
      if (!mounted) return;
      setState(() {
        _currencies = AppCurrency.configuredCurrencies;
        _syncControllers();
        _savingCode = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Tasa de ${currency.code} guardada: '
            '${rate.toString()} ${currency.code} por cada '
            'USD.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _savingCode = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo guardar la tasa: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Tasas de cambio', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(
          'Indica cuántas unidades de cada moneda equivalen a 1 USD. '
          'Las tasas se guardan en este dispositivo.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        for (final currency in _currencies) ...[
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _rateControllers[currency.code],
                  enabled: !currency.isBase,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: '${currency.code} - ${currency.symbol}',
                    helperText: currency.isBase
                        ? 'Moneda base fija (1 USD)'
                        : null,
                    prefixIcon: const Icon(Icons.currency_exchange_outlined),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: currency.isBase || _savingCode != null
                    ? null
                    : () => _saveRate(currency),
                child: _savingCode == currency.code
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Guardar'),
              ),
            ],
          ),
          if (currency != _currencies.last) const SizedBox(height: 12),
        ],
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _isAdding ? null : _addCurrency,
          icon: _isAdding
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.add),
          label: const Text('Agregar moneda'),
        ),
      ],
    ),
  );
}

class _BusinessProfileCard extends StatelessWidget {
  final VoidCallback onTap;
  const _BusinessProfileCard({required this.onTap});

  @override
  Widget build(BuildContext context) => BlocBuilder<ShopBloc, ShopState>(
    builder: (context, state) {
      final shop = state is ShopLoaded ? state.shop : null;
      final logo = shop?.logoData;
      return Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Theme.of(context).colorScheme.primary,
                  Theme.of(context).colorScheme.primary.withValues(alpha: .78),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 32,
                  backgroundColor: Colors.white.withValues(alpha: .18),
                  backgroundImage: logo == null
                      ? null
                      : MemoryImage(base64Decode(logo)),
                  child: logo == null
                      ? const Icon(
                          Icons.storefront,
                          color: Colors.white,
                          size: 30,
                        )
                      : null,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        shop?.name.isNotEmpty == true
                            ? shop!.name
                            : 'Configura tu tienda',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        shop?.addressLine1.isNotEmpty == true
                            ? shop!.addressLine1
                            : 'Añade el logotipo y los datos del negocio',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white70),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Editar perfil de la tienda',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: Colors.white),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final String subtitle;
  const _SectionTitle({super.key, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 3),
        Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
      ],
    ),
  );
}

class _SettingsGroup extends StatelessWidget {
  final List<Widget> children;
  const _SettingsGroup({required this.children});

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: Column(children: children),
  );
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;

  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ListTile(
      onTap: onTap,
      minVerticalPadding: 12,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 5),
      leading: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: colors.primaryContainer,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.primary.withValues(alpha: .08)),
        ),
        alignment: Alignment.center,
        child: Icon(icon, color: colors.primary, size: 25),
      ),
      title: Text(
        title,
        style: Theme.of(
          context,
        ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
      ),
      trailing:
          trailing ??
          (onTap == null
              ? null
              : Icon(
                  Icons.chevron_right_rounded,
                  color: colors.onSurfaceVariant,
                )),
    );
  }
}

class _SettingsDivider extends StatelessWidget {
  const _SettingsDivider();

  @override
  Widget build(BuildContext context) => const Divider(height: 1, indent: 72);
}
