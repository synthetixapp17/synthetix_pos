import 'package:app_settings/app_settings.dart' as app_settings;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

import '../../../../core/utils/receipt_preferences.dart';
import '../../../shop/presentation/bloc/shop_bloc.dart';
import '../bloc/printer_bloc.dart';
import '../bloc/printer_event.dart';
import '../bloc/printer_state.dart';

class PrinterSettingsPage extends StatefulWidget {
  const PrinterSettingsPage({super.key});

  @override
  State<PrinterSettingsPage> createState() => _PrinterSettingsPageState();
}

class _PrinterSettingsPageState extends State<PrinterSettingsPage> {
  late int _paperWidth;

  @override
  void initState() {
    super.initState();
    _paperWidth = ReceiptPreferences.paperWidth;
    context.read<PrinterBloc>().add(RefreshPrinterEvent());
  }

  Future<void> _savePaperWidth(int width) async {
    try {
      await ReceiptPreferences.savePaperWidth(width);
      if (!mounted) return;
      setState(() => _paperWidth = width);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Tamaño del ticket guardado: $width mm.'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo guardar el tamaño del ticket: $error')),
      );
    }
  }

  String _shopName(BuildContext context) {
    final shopState = context.read<ShopBloc>().state;
    if (shopState is ShopLoaded && shopState.shop.name.isNotEmpty) {
      return shopState.shop.name;
    }
    return 'Prueba de impresión';
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Impresora térmica')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: BlocConsumer<PrinterBloc, PrinterState>(
            listener: (context, state) {
              if (state.errorMessage != null) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(state.errorMessage!)));
              }
            },
            builder: (context, state) {
              final connected = state.status == PrinterStatus.connected;
              final busy = state.status == PrinterStatus.scanning ||
                  state.status == PrinterStatus.connecting ||
                  state.status == PrinterStatus.testPrinting;
              return ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                children: [
                  _PrinterIntroCard(
                    connected: connected,
                    printerName: state.connectedName,
                  ),
                  const SizedBox(height: 28),
                  const _PrinterSectionHeading(
                    title: 'Tamaño del papel',
                    subtitle:
                        'Elige el ancho que corresponde al rollo instalado en tu impresora.',
                  ),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SegmentedButton<int>(
                            segments: const [
                              ButtonSegment(
                                value: 58,
                                icon: Icon(Icons.receipt_outlined),
                                label: Text('58 mm'),
                              ),
                              ButtonSegment(
                                value: 80,
                                icon: Icon(Icons.receipt_long_outlined),
                                label: Text('80 mm'),
                              ),
                            ],
                            selected: {_paperWidth},
                            onSelectionChanged: (selection) =>
                                _savePaperWidth(selection.first),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            _paperWidth == 58
                                ? 'Formato compacto para impresoras térmicas de 58 mm.'
                                : 'Formato amplio para impresoras térmicas de 80 mm.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 26),
                  _PrinterSectionHeading(
                    title: 'Impresoras disponibles',
                    subtitle:
                        'Busca los dispositivos Bluetooth vinculados a este equipo y selecciona uno para conectarlo.',
                    trailing: IconButton.filledTonal(
                      tooltip: 'Buscar impresoras vinculadas',
                      onPressed: busy
                          ? null
                          : () => context.read<PrinterBloc>().add(
                              RefreshPrinterEvent(),
                            ),
                      icon: busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh_rounded),
                    ),
                  ),
                  Card(
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        if (state.devices.isEmpty && busy)
                          const Padding(
                            padding: EdgeInsets.all(26),
                            child: Column(
                              children: [
                                CircularProgressIndicator(),
                                SizedBox(height: 12),
                                Text('Buscando impresoras…'),
                              ],
                            ),
                          )
                        else if (state.devices.isEmpty)
                          Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              children: [
                                Icon(
                                  Icons.bluetooth_searching_rounded,
                                  size: 38,
                                  color: colors.primary,
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  'Aún no hay impresoras vinculadas',
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  'Vincula la impresora desde los ajustes Bluetooth del dispositivo y vuelve a buscarla.',
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          )
                        else
                          for (var index = 0;
                              index < state.devices.length;
                              index++) ...[
                            _PrinterDeviceTile(
                              device: state.devices[index],
                              connected: state.connectedMac ==
                                  state.devices[index].macAdress,
                              disabled: busy ||
                                  (connected &&
                                      state.connectedMac !=
                                          state.devices[index].macAdress),
                              onConnect: () => context.read<PrinterBloc>().add(
                                ConnectPrinterEvent(
                                  mac: state.devices[index].macAdress,
                                  name: state.devices[index].name,
                                ),
                              ),
                            ),
                            if (index < state.devices.length - 1)
                              const Divider(height: 1, indent: 72),
                          ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 26),
                  const _PrinterSectionHeading(
                    title: 'Prueba y conexión',
                    subtitle:
                        'Comprueba la impresión antes de emitir el siguiente ticket.',
                  ),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Wrap(
                        spacing: 12,
                        runSpacing: 10,
                        children: [
                          FilledButton.icon(
                            onPressed: connected && !busy
                                ? () => context.read<PrinterBloc>().add(
                                    TestPrintEvent(_shopName(context)),
                                  )
                                : null,
                            icon: state.status == PrinterStatus.testPrinting
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.receipt_long_outlined),
                            label: Text(
                              state.status == PrinterStatus.testPrinting
                                  ? 'Imprimiendo…'
                                  : 'Imprimir prueba',
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: connected && !busy
                                ? () => context.read<PrinterBloc>().add(
                                    DisconnectPrinterEvent(),
                                  )
                                : null,
                            icon: const Icon(Icons.link_off_rounded),
                            label: const Text('Desconectar'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () =>
                                app_settings.AppSettings.openAppSettings(
                                  type: app_settings.AppSettingsType.bluetooth,
                                ),
                            icon: const Icon(Icons.bluetooth_rounded),
                            label: const Text('Ajustes de Bluetooth'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _PrinterIntroCard extends StatelessWidget {
  const _PrinterIntroCard({required this.connected, this.printerName});

  final bool connected;
  final String? printerName;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              Icons.print_rounded,
              color: colors.primary,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  connected ? 'Impresora conectada' : 'Configura tu impresora',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  connected
                      ? printerName ?? 'Lista para imprimir tickets'
                      : 'Conecta tu impresora Bluetooth y ajusta el formato de tus tickets.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          if (connected)
            Icon(Icons.check_circle_rounded, color: colors.primary),
        ],
      ),
    );
  }
}

class _PrinterSectionHeading extends StatelessWidget {
  const _PrinterSectionHeading({
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 12), trailing!],
      ],
    ),
  );
}

class _PrinterDeviceTile extends StatelessWidget {
  const _PrinterDeviceTile({
    required this.device,
    required this.connected,
    required this.disabled,
    required this.onConnect,
  });

  final BluetoothInfo device;
  final bool connected;
  final bool disabled;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) => ListTile(
    minVerticalPadding: 14,
    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
    leading: CircleAvatar(
      backgroundColor: Theme.of(context).colorScheme.primary.withValues(
        alpha: 0.1,
      ),
      child: Icon(
        connected ? Icons.print_rounded : Icons.bluetooth_rounded,
        color: Theme.of(context).colorScheme.primary,
      ),
    ),
    title: Text(
      device.name.isEmpty ? 'Impresora térmica' : device.name,
      style: const TextStyle(fontWeight: FontWeight.w600),
    ),
    subtitle: Text(device.macAdress),
    trailing: connected
        ? const Chip(
            avatar: Icon(Icons.check_rounded, size: 16),
            label: Text('Conectada'),
          )
        : OutlinedButton(
            onPressed: disabled ? null : onConnect,
            child: const Text('Conectar'),
          ),
  );
}
