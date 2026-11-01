import 'dart:convert';

import 'package:app_settings/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/data/hive_database.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/theme_controller.dart';
import '../../../../core/utils/app_currency.dart';
import '../../../billing/presentation/bloc/billing_bloc.dart';
import '../../../product/data/models/product_model.dart';
import '../../../product/domain/entities/product.dart';
import '../../../product/presentation/bloc/product_bloc.dart';
import '../../../shop/presentation/bloc/shop_bloc.dart';
import '../../data/csv_backup_exporter.dart';
import '../bloc/printer_bloc.dart';
import '../bloc/printer_event.dart';
import '../bloc/printer_state.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late String _currencyCode;
  late int _stockThreshold;
  int _currencyDropdownVersion = 0;
  bool _isExportingBackup = false;

  @override
  void initState() {
    super.initState();
    _currencyCode = AppCurrency.currentCode;
    _stockThreshold =
        HiveDatabase.settingsBox.get('low_stock_threshold', defaultValue: 5)
            as int;
    context.read<ShopBloc>().add(LoadShopEvent());
  }

  Future<void> _saveCurrency(String? code) async {
    if (code == null) return;
    if (code == _currencyCode) return;
    final productBloc = context.read<ProductBloc>();
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

    final productsBox = HiveDatabase.productBox;
    final previousProducts = productsBox.toMap();
    try {
      final replacements = <dynamic, ProductModel>{};
      for (final entry in previousProducts.entries) {
        final product = entry.value;
        replacements[entry.key] = ProductModel.fromEntity(
          Product(
            id: product.id,
            name: product.name,
            barcode: product.barcode,
            price: product.price,
            stock: product.stock,
            description: product.description,
            imageData: product.imageData,
            currencyCode: code,
            category: product.category,
          ),
        );
      }

      await productsBox.putAll(replacements);
      await AppCurrency.setCurrentCode(code);
      productBloc.add(LoadProducts());
      if (mounted) {
        setState(() {
          _currencyCode = code;
          _currencyDropdownVersion++;
        });
      }
    } catch (error) {
      String? rollbackError;
      try {
        await productsBox.putAll(previousProducts);
        await AppCurrency.setCurrentCode(_currencyCode);
      } catch (error) {
        rollbackError = error.toString();
      }
      productBloc.add(LoadProducts());
      if (mounted) {
        setState(() => _currencyDropdownVersion++);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              rollbackError == null
                  ? 'No se pudo actualizar la moneda. Se conservaron los datos anteriores: $error'
                  : 'No se pudo actualizar la moneda ($error) ni restaurar todos los datos ($rollbackError).',
            ),
          ),
        );
      }
      return;
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Moneda actualizada. Se aplicó a los productos sin convertir sus precios. Los importes históricos mantienen su valor y se muestran con el símbolo seleccionado.',
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

  Future<void> _exportCsvBackup() async {
    if (_isExportingBackup) return;
    setState(() => _isExportingBackup = true);
    try {
      final backup = CsvBackupExporter().createBackup();
      await SharePlus.instance.share(
        ShareParams(
          title: 'Copia de seguridad en CSV',
          text:
              'Respaldo de productos, clientes, ventas y configuración de la tienda.',
          files: [
            for (final file in backup)
              XFile.fromData(file.bytes, mimeType: 'text/csv'),
          ],
          fileNameOverrides: [for (final file in backup) file.name],
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Configuración'), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
        children: [
          _BusinessProfileCard(onTap: () => context.push('/shop')),
          const SizedBox(height: 22),
          const _SectionTitle(
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
          const _SectionTitle(
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
          const _SectionTitle(
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
          const _SectionTitle(
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
                    labelText: 'Moneda predeterminada',
                    helperText:
                        'Se aplica a los productos existentes sin convertir precios. Los importes históricos mantienen su valor y usan el símbolo seleccionado.',
                    prefixIcon: Icon(Icons.currency_exchange),
                  ),
                  items: AppCurrency.options
                      .map(
                        (option) => DropdownMenuItem(
                          value: option.code,
                          child: Text(
                            '${option.symbol}  ${option.name} (${option.code})',
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: _saveCurrency,
                ),
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
                  builder: (context, mode, _) => SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    secondary: const Icon(Icons.dark_mode_outlined),
                    title: const Text('Apariencia oscura'),
                    subtitle: Text(
                      mode == ThemeMode.dark
                          ? 'Modo oscuro activado'
                          : 'Modo claro activado',
                    ),
                    value: mode == ThemeMode.dark,
                    onChanged: (dark) => AppThemeController.setMode(
                      dark ? ThemeMode.dark : ThemeMode.light,
                    ),
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
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  'Se aplica al menú, botones y elementos principales de toda la plataforma.',
                                  style: Theme.of(context).textTheme.bodySmall,
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
                                    color: selectedColor.withValues(alpha: .3),
                                    blurRadius: 8,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
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
                                        ?.copyWith(fontWeight: FontWeight.bold),
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
                                  color.toARGB32() == selectedColor.toARGB32();
                              return Semantics(
                                button: true,
                                selected: selected,
                                label: 'Color ${_colorName(color)}',
                                child: InkWell(
                                  onTap: () =>
                                      AppThemeController.setPrimaryColor(color),
                                  borderRadius: BorderRadius.circular(12),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 180),
                                    decoration: BoxDecoration(
                                      color: selected
                                          ? color.withValues(alpha: .1)
                                          : Theme.of(
                                              context,
                                            ).colorScheme.surface,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: selected
                                            ? color
                                            : Theme.of(context).dividerColor,
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
                                                  color: AppTheme.onColor(color),
                                                  size: 18,
                                                )
                                              : null,
                                        ),
                                        const SizedBox(height: 5),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
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
            ],
          ),
          const SizedBox(height: 22),
          const _SectionTitle(
            title: 'Dispositivos',
            subtitle: 'Conecta la impresora térmica para emitir recibos.',
          ),
          BlocConsumer<PrinterBloc, PrinterState>(
            listener: (context, state) {
              if (state.errorMessage != null) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(state.errorMessage!)));
              }
            },
            builder: (context, state) {
              final connected = state.status == PrinterStatus.connected;
              final canManageConnection =
                  connected || state.status == PrinterStatus.testPrintFailure;
              final busy =
                  state.status == PrinterStatus.scanning ||
                  state.status == PrinterStatus.connecting ||
                  state.status == PrinterStatus.testPrinting;
              final shopState = context.read<ShopBloc>().state;
              final shopName =
                  shopState is ShopLoaded && shopState.shop.name.isNotEmpty
                  ? shopState.shop.name
                  : 'Prueba de impresión';
              return _SettingsGroup(
                children: [
                  _SettingsTile(
                    icon: Icons.print_outlined,
                    title: 'Impresora térmica',
                    subtitle: connected
                        ? 'Conectada: ${state.connectedName ?? 'impresora seleccionada'}'
                        : state.status == PrinterStatus.testPrintFailure
                        ? 'No se pudo completar la prueba de impresión'
                        : state.connectedMac == null
                        ? 'No hay impresora conectada'
                        : 'Impresora guardada sin conexión',
                    trailing: busy
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : IconButton(
                            tooltip: 'Buscar impresoras vinculadas',
                            onPressed: () => context.read<PrinterBloc>().add(
                              RefreshPrinterEvent(),
                            ),
                            icon: const Icon(Icons.refresh),
                          ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Text(
                      'Primero vincula la impresora en los ajustes de Bluetooth. Después, búscala aquí para conectarla.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  if (state.devices.isNotEmpty) ...[
                    const _SettingsDivider(),
                    ...state.devices.map(
                      (device) => ListTile(
                        leading: const Icon(Icons.bluetooth),
                        title: Text(device.name),
                        subtitle: Text(device.macAdress),
                        trailing: OutlinedButton(
                          onPressed: busy || connected
                              ? null
                              : () => context.read<PrinterBloc>().add(
                                  ConnectPrinterEvent(
                                    mac: device.macAdress,
                                    name: device.name,
                                  ),
                                ),
                          child: Text(
                            connected && state.connectedMac == device.macAdress
                                ? 'Conectada'
                                : 'Conectar',
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (canManageConnection) ...[
                    const _SettingsDivider(),
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Wrap(
                        spacing: 10,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: busy
                                ? null
                                : () => context.read<PrinterBloc>().add(
                                    TestPrintEvent(shopName),
                                  ),
                            icon: const Icon(Icons.receipt_long_outlined),
                            label: Text(
                              state.status == PrinterStatus.testPrinting
                                  ? 'Imprimiendo prueba…'
                                  : 'Imprimir prueba',
                            ),
                          ),
                          TextButton.icon(
                            onPressed: busy
                                ? null
                                : () => context.read<PrinterBloc>().add(
                                    DisconnectPrinterEvent(),
                                  ),
                            icon: const Icon(Icons.link_off),
                            label: const Text('Desconectar'),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const _SettingsDivider(),
                  _SettingsTile(
                    icon: Icons.bluetooth,
                    title: 'Ajustes de Bluetooth',
                    subtitle: 'Vincula la impresora desde el dispositivo',
                    onTap: () => AppSettings.openAppSettings(
                      type: AppSettingsType.bluetooth,
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 22),
          const _SectionTitle(
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
                    'Productos, clientes, ventas y datos de la tienda en archivos separados.',
                onTap: _isExportingBackup ? null : _exportCsvBackup,
                trailing: _isExportingBackup
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.ios_share_outlined),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 14),
                child: Text(
                  'Las imágenes y el logotipo se incluyen codificados en Base64 dentro de los CSV. Guarda estos archivos en un lugar seguro.',
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
  const _SectionTitle({required this.title, required this.subtitle});

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
  Widget build(BuildContext context) => ListTile(
    onTap: onTap,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    leading: CircleAvatar(
      backgroundColor: Theme.of(
        context,
      ).colorScheme.primary.withValues(alpha: .1),
      child: Icon(icon, color: Theme.of(context).colorScheme.primary),
    ),
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
    subtitle: Text(subtitle),
    trailing:
        trailing ??
        (onTap == null ? null : const Icon(Icons.chevron_right, size: 20)),
  );
}

class _SettingsDivider extends StatelessWidget {
  const _SettingsDivider();

  @override
  Widget build(BuildContext context) => const Divider(height: 1, indent: 72);
}
