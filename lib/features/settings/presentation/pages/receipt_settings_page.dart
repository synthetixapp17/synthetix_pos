import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';

import '../../../../core/data/hive_database.dart';
import '../../../../core/utils/app_currency.dart';
import '../../../../core/utils/receipt_preferences.dart';
import '../../../../core/utils/receipt_qr.dart';
import '../../../shop/domain/entities/shop.dart';
import '../../../shop/presentation/bloc/shop_bloc.dart';

class ReceiptSettingsPage extends StatefulWidget {
  const ReceiptSettingsPage({super.key});

  @override
  State<ReceiptSettingsPage> createState() => _ReceiptSettingsPageState();
}

class _ReceiptSettingsPageState extends State<ReceiptSettingsPage> {
  late bool _showAddress;
  late bool _showPhone;
  late bool _showDate;
  late bool _showBarcode;
  late bool _showUnitPrices;
  late bool _showRif;
  late bool _showInvoiceQr;
  late final TextEditingController _shopNameController;
  late final TextEditingController _addressController;
  late final TextEditingController _address2Controller;
  late final TextEditingController _phoneController;
  late final TextEditingController _rifController;
  late final TextEditingController _footerController;
  String? _logoData;
  Shop _shop = const Shop();
  bool _shopLoaded = false;
  bool _savingShop = false;
  String _footer = '¡Gracias por tu compra!';

  @override
  void initState() {
    super.initState();
    _showAddress = ReceiptPreferences.showAddress;
    _showPhone = ReceiptPreferences.showPhone;
    _showDate = ReceiptPreferences.showDate;
    _showBarcode = ReceiptPreferences.showBarcode;
    _showUnitPrices = ReceiptPreferences.showUnitPrices;
    _showRif = ReceiptPreferences.showRif;
    _showInvoiceQr = ReceiptPreferences.showInvoiceQr;
    _shopNameController = TextEditingController();
    _addressController = TextEditingController();
    _address2Controller = TextEditingController();
    _phoneController = TextEditingController();
    _rifController = TextEditingController();
    _footerController = TextEditingController(
      text: ReceiptPreferences.footerText,
    );
    context.read<ShopBloc>().add(LoadShopEvent());
  }

  @override
  void dispose() {
    _shopNameController.dispose();
    _addressController.dispose();
    _address2Controller.dispose();
    _phoneController.dispose();
    _rifController.dispose();
    _footerController.dispose();
    super.dispose();
  }

  void _fillShop(Shop shop) {
    if (_shopLoaded) return;
    _shopLoaded = true;
    _shop = shop;
    _shopNameController.text = shop.name;
    _addressController.text = shop.addressLine1;
    _address2Controller.text = shop.addressLine2;
    _phoneController.text = shop.phoneNumber;
    _rifController.text = shop.rif;
    _logoData = shop.logoData;
    if (_footerController.text.isEmpty) {
      _footerController.text = shop.footerText;
    }
    _footer = _footerController.text;
  }

  Future<void> _pickLogo() async {
    try {
      final selected = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1200,
      );
      if (selected == null || !mounted) return;
      final bytes = await selected.readAsBytes();
      if (!mounted) return;
      setState(() => _logoData = base64Encode(bytes));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo cargar el logotipo: $error')),
      );
    }
  }

  Future<void> _saveShopInfo() async {
    final name = _shopNameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El nombre del negocio es obligatorio.')),
      );
      return;
    }
    setState(() => _savingShop = true);
    try {
      await HiveDatabase.settingsBox.put(
        ReceiptPreferences.footerTextKey,
        _footerController.text.trim(),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _savingShop = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo guardar el mensaje del ticket: $error'),
        ),
      );
      return;
    }
    if (!mounted) return;
    _shop = Shop(
      name: name,
      addressLine1: _addressController.text.trim(),
      addressLine2: _address2Controller.text.trim(),
      phoneNumber: _phoneController.text.trim(),
      rif: _rifController.text.trim(),
      upiId: _shop.upiId,
      footerText: _footerController.text.trim(),
      logoData: _logoData,
    );
    context.read<ShopBloc>().add(UpdateShopEvent(_shop));
  }

  Future<void> _save(String key, bool value) async {
    try {
      await HiveDatabase.settingsBox.put(key, value);
      if (!mounted) return;
      setState(() {
        switch (key) {
          case ReceiptPreferences.showAddressKey:
            _showAddress = value;
            break;
          case ReceiptPreferences.showPhoneKey:
            _showPhone = value;
            break;
          case ReceiptPreferences.showDateKey:
            _showDate = value;
            break;
          case ReceiptPreferences.showBarcodeKey:
            _showBarcode = value;
            break;
          case ReceiptPreferences.showUnitPricesKey:
            _showUnitPrices = value;
            break;
          case ReceiptPreferences.showRifKey:
            _showRif = value;
            break;
          case ReceiptPreferences.showInvoiceQrKey:
            _showInvoiceQr = value;
            break;
        }
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo guardar el diseño del ticket: $error'),
        ),
      );
    }
  }

  Future<void> _saveFooter() async {
    try {
      final footer = _footerController.text.trim();
      await HiveDatabase.settingsBox.put(
        ReceiptPreferences.footerTextKey,
        footer,
      );
      if (!mounted) return;
      setState(() => _footer = footer);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mensaje del ticket guardado.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo guardar el mensaje: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Diseño del ticket')),
      body: BlocConsumer<ShopBloc, ShopState>(
        listener: (context, state) {
          if (state is ShopLoaded) {
            _fillShop(state.shop);
          } else if (state is ShopOperationSuccess && _savingShop) {
            setState(() => _savingShop = false);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Logo e información del ticket guardados.'),
              ),
            );
          } else if (state is ShopError) {
            setState(() => _savingShop = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'No se pudo guardar la información: ${state.message}',
                ),
              ),
            );
          }
        },
        builder: (context, state) => ListView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 32),
          children: [
            Text(
              'Personaliza la información que se imprimirá en cada comprobante.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 18),
            _ReceiptSectionHeading(
              title: 'Identidad e información del ticket',
              subtitle:
                  'Configura el logotipo y los datos del negocio que verán tus clientes.',
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 34,
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.primaryContainer,
                          backgroundImage: _logoData == null
                              ? null
                              : MemoryImage(base64Decode(_logoData!)),
                          child: _logoData == null
                              ? Icon(
                                  Icons.storefront_outlined,
                                  size: 30,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onPrimaryContainer,
                                )
                              : null,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Logotipo del ticket',
                                style: Theme.of(context).textTheme.titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Aparecerá en la vista previa y en el ticket impreso.',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _pickLogo,
                          icon: const Icon(Icons.upload_outlined),
                          label: Text(
                            _logoData == null ? 'Agregar logo' : 'Cambiar logo',
                          ),
                        ),
                        if (_logoData != null)
                          TextButton.icon(
                            onPressed: () => setState(() => _logoData = null),
                            icon: const Icon(Icons.delete_outline),
                            label: const Text('Quitar'),
                          ),
                      ],
                    ),
                    const Divider(height: 24),
                    TextFormField(
                      controller: _shopNameController,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Nombre del negocio',
                        prefixIcon: Icon(Icons.storefront_outlined),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _addressController,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        labelText: 'Dirección',
                        prefixIcon: Icon(Icons.location_on_outlined),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _address2Controller,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        labelText: 'Complemento de dirección',
                        prefixIcon: Icon(Icons.map_outlined),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Teléfono del negocio',
                        prefixIcon: Icon(Icons.phone_outlined),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _rifController,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                        labelText: 'RIF del negocio',
                        hintText: 'J-12345678-9',
                        prefixIcon: Icon(Icons.badge_outlined),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _savingShop || !_shopLoaded
                            ? null
                            : _saveShopInfo,
                        icon: _savingShop
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.save_outlined),
                        label: Text(
                          _savingShop
                              ? 'Guardando…'
                              : 'Guardar logo e información',
                        ),
                      ),
                    ),
                    if (!_shopLoaded && state is ShopLoading)
                      const Padding(
                        padding: EdgeInsets.only(top: 10),
                        child: LinearProgressIndicator(),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 22),
            _ReceiptSectionHeading(
              title: 'Vista previa',
              subtitle: 'Así aparecerá la información al presentar el ticket.',
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (_logoData != null)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.memory(
                          base64Decode(_logoData!),
                          width: 76,
                          height: 76,
                          fit: BoxFit.contain,
                        ),
                      )
                    else
                      const Icon(Icons.storefront_outlined, size: 28),
                    const SizedBox(height: 8),
                    Text(
                      (_shopNameController.text.isEmpty
                              ? 'MI TIENDA'
                              : _shopNameController.text)
                          .toUpperCase(),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                      ),
                    ),
                    if (_showAddress && _addressController.text.isNotEmpty)
                      Text(
                        [_addressController.text, _address2Controller.text]
                            .where((address) => address.trim().isNotEmpty)
                            .join(', '),
                      ),
                    if (_showPhone && _phoneController.text.isNotEmpty)
                      Text(_phoneController.text),
                    if (_showRif && _rifController.text.isNotEmpty)
                      Text('RIF: ${_rifController.text}'),
                    if (_showDate) ...[
                      const SizedBox(height: 8),
                      Text(
                        DateFormat(
                          'dd/MM/yyyy HH:mm',
                          'es',
                        ).format(DateTime.now()),
                      ),
                    ],
                    const Divider(height: 24),
                    const Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Text(
                            'Producto',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        Expanded(
                          child: Text('Cant.', textAlign: TextAlign.center),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text('Total', textAlign: TextAlign.end),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Producto de ejemplo'),
                              if (_showBarcode)
                                Text(
                                  'Código: 000123',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                            ],
                          ),
                        ),
                        const Expanded(
                          child: Text('2', textAlign: TextAlign.center),
                        ),
                        Expanded(
                          flex: 2,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              if (_showUnitPrices)
                                Text(
                                  '2 × ${AppCurrency.formatConfigured(10)}',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              Text(
                                AppCurrency.formatConfigured(20),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'TOTAL',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          AppCurrency.formatConfigured(20),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    if (_showInvoiceQr) ...[
                      const SizedBox(height: 16),
                      SizedBox(
                        width: 76,
                        height: 76,
                        child: PrettyQrView.data(
                          data: ReceiptQr.privateReceiptData,
                        ),
                      ),
                      Text(
                        'QR privado sin enlace ni datos de venta',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                    const SizedBox(height: 16),
                    Text(_footer),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            _ReceiptOptionTile(
              title: 'Dirección del negocio',
              subtitle: 'Imprime la dirección de la tienda.',
              value: _showAddress,
              onChanged: (value) =>
                  _save(ReceiptPreferences.showAddressKey, value),
            ),
            _ReceiptOptionTile(
              title: 'Teléfono de contacto',
              subtitle: 'Muestra el teléfono de la tienda.',
              value: _showPhone,
              onChanged: (value) =>
                  _save(ReceiptPreferences.showPhoneKey, value),
            ),
            _ReceiptOptionTile(
              title: 'RIF del negocio',
              subtitle: 'Incluye el RIF guardado en los datos del ticket.',
              value: _showRif,
              onChanged: (value) => _save(ReceiptPreferences.showRifKey, value),
            ),
            _ReceiptOptionTile(
              title: 'QR de consulta de la venta',
              subtitle:
                  'Añade un QR para abrir esta venta por su folio en reportes.',
              value: _showInvoiceQr,
              onChanged: (value) =>
                  _save(ReceiptPreferences.showInvoiceQrKey, value),
            ),
            _ReceiptOptionTile(
              title: 'Fecha y hora',
              subtitle: 'Incluye cuándo se realizó la venta.',
              value: _showDate,
              onChanged: (value) =>
                  _save(ReceiptPreferences.showDateKey, value),
            ),
            _ReceiptOptionTile(
              title: 'Código del producto',
              subtitle: 'Muestra el código de barras junto al producto.',
              value: _showBarcode,
              onChanged: (value) =>
                  _save(ReceiptPreferences.showBarcodeKey, value),
            ),
            _ReceiptOptionTile(
              title: 'Precio por unidad',
              subtitle: 'Muestra el precio unitario además del total.',
              value: _showUnitPrices,
              onChanged: (value) =>
                  _save(ReceiptPreferences.showUnitPricesKey, value),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _footerController,
              maxLength: 120,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Mensaje final del ticket',
                helperText: 'Se imprime al pie del comprobante.',
                prefixIcon: Icon(Icons.edit_note_outlined),
              ),
              onChanged: (value) => setState(() => _footer = value),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _saveFooter,
                icon: const Icon(Icons.save_outlined),
                label: const Text('Guardar mensaje'),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'El nombre, las cantidades, el total y el mensaje final se conservan en el ticket.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _ReceiptSectionHeading extends StatelessWidget {
  final String title;
  final String subtitle;

  const _ReceiptSectionHeading({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 4),
      Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
    ],
  );
}

class _ReceiptOptionTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ReceiptOptionTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Card(
    child: SwitchListTile(
      title: Text(title),
      subtitle: Text(subtitle),
      value: value,
      onChanged: onChanged,
    ),
  );
}
