import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/data/hive_database.dart';
import '../../data/virtual_store_publisher.dart';
import '../../data/virtual_store_settings.dart';
import 'virtual_store_orders_page.dart';

class VirtualStoreSettingsPage extends StatefulWidget {
  const VirtualStoreSettingsPage({super.key});

  @override
  State<VirtualStoreSettingsPage> createState() =>
      _VirtualStoreSettingsPageState();
}

class _VirtualStoreSettingsPageState extends State<VirtualStoreSettingsPage> {
  final _formKey = GlobalKey<FormState>();
  late final VirtualStoreSettings _initialSettings;
  late final TextEditingController _businessName;
  late final TextEditingController _slogan;
  late final TextEditingController _whatsappNumber;
  late String _logo;
  late String _banner;
  late int _primaryColor;
  late int _accentColor;
  late bool _showUsdReference;
  late String _exchangeRateSource;
  String? _publishedUrl;
  bool _isSaving = false;
  bool _isPublishing = false;

  @override
  void initState() {
    super.initState();
    _initialSettings = VirtualStoreSettings.load();
    _businessName = TextEditingController(text: _initialSettings.businessName);
    _slogan = TextEditingController(text: _initialSettings.slogan);
    _whatsappNumber = TextEditingController(
      text: _initialSettings.whatsappNumber.replaceAll(RegExp(r'\D'), ''),
    );
    _logo = _initialSettings.logo;
    _banner = _initialSettings.banner;
    _primaryColor = _initialSettings.primaryColor;
    _accentColor = _initialSettings.accentColor;
    _showUsdReference = _initialSettings.showUsdReference;
    _exchangeRateSource = _initialSettings.exchangeRateSource;
    _publishedUrl = _initialSettings.publishedUrl.isEmpty
        ? null
        : _initialSettings.publishedUrl;
  }

  @override
  void dispose() {
    _businessName.dispose();
    _slogan.dispose();
    _whatsappNumber.dispose();
    super.dispose();
  }

  VirtualStoreSettings? _readForm() {
    if (!_formKey.currentState!.validate()) return null;
    return VirtualStoreSettings(
      businessName: _businessName.text.trim(),
      slogan: _slogan.text.trim(),
      whatsappNumber: _whatsappNumber.text.replaceAll(RegExp(r'\D'), ''),
      logo: _logo,
      banner: _banner,
      primaryColor: _primaryColor,
      accentColor: _accentColor,
      showUsdReference: _showUsdReference,
      exchangeRateSource: _exchangeRateSource,
      lastPublishedAt: _initialSettings.lastPublishedAt,
      publishedUrl: _initialSettings.publishedUrl,
    );
  }

  Future<VirtualStoreSettings?> _saveSettings() async {
    final settings = _readForm();
    if (settings == null) return null;
    await HiveDatabase.settingsBox.put(
      virtualStoreSettingsKey,
      jsonEncode(settings.toJson()),
    );
    if (mounted) {
      setState(() {
        _publishedUrl = settings.publishedUrl.isEmpty
            ? null
            : settings.publishedUrl;
      });
    }
    return settings;
  }

  Future<void> _saveLocally() async {
    setState(() => _isSaving = true);
    try {
      final settings = await _saveSettings();
      if (settings != null && mounted) {
        _showMessage('Configuración de la tienda guardada.');
      }
    } catch (error) {
      if (mounted) _showMessage('No se pudo guardar la configuración: $error');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _pickImage({required bool forBanner}) async {
    try {
      final selected = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
        maxWidth: forBanner ? 1800 : 1000,
      );
      if (selected == null) return;
      final bytes = await selected.readAsBytes();
      if (bytes.length > 1024 * 1024) {
        throw const FormatException(
          'La imagen supera 1 MB. Elige una imagen más ligera.',
        );
      }
      setState(() {
        final encoded = base64Encode(bytes);
        if (forBanner) {
          _banner = encoded;
        } else {
          _logo = encoded;
        }
      });
    } catch (error) {
      if (mounted) _showMessage('No se pudo cargar la imagen: $error');
    }
  }

  Future<void> _openOrders() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const VirtualStoreOrdersPage()),
    );
  }

  ImageProvider? _imageProvider(String value) {
    if (value.isEmpty) return null;
    try {
      final encoded = value.startsWith('data:image/')
          ? value.substring(value.indexOf(',') + 1)
          : value;
      return MemoryImage(base64Decode(encoded));
    } on FormatException {
      return null;
    }
  }

  Future<void> _publish() async {
    if (_isPublishing) return;
    final settings = _readForm();
    if (settings == null) return;

    setState(() {
      _isPublishing = true;
      _publishedUrl = null;
    });
    try {
      await HiveDatabase.settingsBox.put(
        virtualStoreSettingsKey,
        jsonEncode(settings.toJson()),
      );
      final catalog = VirtualStoreCatalogBuilder().build(
        settings,
        HiveDatabase.productBox.values,
      );
      final publishedUrl = await VirtualStorePublisher().publish(
        settings: settings,
        catalog: catalog,
      );
      final publishedSettings = VirtualStoreSettings(
        businessName: settings.businessName,
        slogan: settings.slogan,
        whatsappNumber: settings.whatsappNumber,
        logo: settings.logo,
        banner: settings.banner,
        primaryColor: settings.primaryColor,
        accentColor: settings.accentColor,
        showUsdReference: settings.showUsdReference,
        exchangeRateSource: settings.exchangeRateSource,
        lastPublishedAt: DateTime.now(),
        publishedUrl: publishedUrl,
      );
      await HiveDatabase.settingsBox.put(
        virtualStoreSettingsKey,
        jsonEncode(publishedSettings.toJson()),
      );
      if (mounted) {
        setState(() {
          _publishedUrl = publishedUrl;
        });
        _showMessage(
          'Tienda publicada. Las páginas abiertas recibirán los cambios en hasta 15 segundos.',
        );
      }
    } catch (error) {
      if (mounted) _showMessage('No se pudo actualizar la tienda: $error');
    } finally {
      if (mounted) setState(() => _isPublishing = false);
    }
  }

  Future<void> _shareStore() async {
    final url = _publishedUrl;
    if (url == null) return;
    await SharePlus.instance.share(
      ShareParams(
        title: 'Tienda virtual de ${_businessName.text.trim()}',
        text: 'Visita nuestra tienda virtual: $url',
      ),
    );
  }

  Future<void> _viewStore() async {
    final url = _publishedUrl;
    if (url == null) return;
    try {
      final uri = Uri.parse(url);
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw StateError('No se pudo abrir el enlace de la tienda.');
      }
    } catch (error) {
      if (mounted) _showMessage('No se pudo abrir la tienda: $error');
    }
  }

  Future<void> _copyStoreLink() async {
    final url = _publishedUrl;
    if (url == null) return;
    await Clipboard.setData(ClipboardData(text: url));
    if (mounted) _showMessage('Enlace copiado.');
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Tienda virtual')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Card(
                  color: colors.secondaryContainer,
                  child: const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Personaliza la imagen y los colores de tu tienda, administra pedidos y publica el catálogo para tus clientes.',
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                TextFormField(
                  controller: _businessName,
                  decoration: const InputDecoration(
                    labelText: 'Nombre de la tienda',
                    border: OutlineInputBorder(),
                  ),
                  maxLength: 80,
                  textCapitalization: TextCapitalization.words,
                  onChanged: (_) => setState(() {}),
                  validator: (value) {
                    final name = value?.trim() ?? '';
                    if (name.isEmpty) return 'Ingresa el nombre de la tienda.';
                    if (name.length > 80) {
                      return 'El nombre no puede superar 80 caracteres.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _slogan,
                  decoration: const InputDecoration(
                    labelText: 'Eslogan o descripción breve',
                    border: OutlineInputBorder(),
                  ),
                  maxLength: 140,
                  textCapitalization: TextCapitalization.sentences,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _whatsappNumber,
                  decoration: const InputDecoration(
                    labelText: 'WhatsApp de la tienda',
                    hintText: '584120000000',
                    helperText: 'Incluye código de país, solo números.',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.phone,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  validator: (value) {
                    final number = value?.trim() ?? '';
                    if (number.isNotEmpty &&
                        !RegExp(r'^\d{8,15}$').hasMatch(number)) {
                      return 'Usa entre 8 y 15 dígitos, con código de país.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 22),
                Text(
                  'Identidad visual',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 10),
                _StoreImagePicker(
                  title: 'Logo',
                  image: _imageProvider(_logo),
                  onPick: () => _pickImage(forBanner: false),
                  onRemove: _logo.isEmpty
                      ? null
                      : () => setState(() => _logo = ''),
                ),
                const SizedBox(height: 12),
                _StoreImagePicker(
                  title: 'Banner de portada',
                  image: _imageProvider(_banner),
                  onPick: () => _pickImage(forBanner: true),
                  onRemove: _banner.isEmpty
                      ? null
                      : () => setState(() => _banner = ''),
                  isBanner: true,
                ),
                const SizedBox(height: 20),
                _ColorSelector(
                  title: 'Color principal',
                  selectedColor: _primaryColor,
                  onSelected: (color) => setState(() => _primaryColor = color),
                ),
                const SizedBox(height: 14),
                _ColorSelector(
                  title: 'Color de acento',
                  selectedColor: _accentColor,
                  onSelected: (color) => setState(() => _accentColor = color),
                ),
                const SizedBox(height: 20),
                Card(
                  child: SwitchListTile(
                    value: _showUsdReference,
                    onChanged: (value) =>
                        setState(() => _showUsdReference = value),
                    title: const Text('Mostrar precios en USD'),
                    subtitle: const Text(
                      'Añade la referencia en bolívares usando una tasa guardada en la plataforma.',
                    ),
                  ),
                ),
                if (_showUsdReference) ...[
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: _exchangeRateSource,
                    decoration: const InputDecoration(
                      labelText: 'Tasa para referencia en Bs.',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'USDT', child: Text('USDT')),
                      DropdownMenuItem(value: 'BCV', child: Text('BCV')),
                      DropdownMenuItem(
                        value: 'Paralelo',
                        child: Text('Paralelo'),
                      ),
                      DropdownMenuItem(
                        value: 'App',
                        child: Text('Moneda VES configurada'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _exchangeRateSource = value);
                      }
                    },
                  ),
                  const SizedBox(height: 6),
                  Builder(
                    builder: (context) {
                      final rate = VirtualStoreSettings.platformVesPerUsd(
                        _exchangeRateSource,
                      );
                      return Text(
                        rate == null
                            ? 'No hay una tasa guardada para esta fuente. Actualízala en la calculadora de tasas antes de publicar.'
                            : '1 USD = ${rate.toStringAsFixed(2)} Bs.',
                        style: Theme.of(context).textTheme.bodySmall,
                      );
                    },
                  ),
                ],
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: _openOrders,
                  icon: const Icon(Icons.receipt_long_outlined),
                  label: const Text('Gestionar pedidos de la tienda'),
                ),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: _isSaving || _isPublishing ? null : _saveLocally,
                  icon: _isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: const Text('Guardar configuración'),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _isPublishing || _isSaving ? null : _publish,
                  icon: _isPublishing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.cloud_upload_outlined),
                  label: const Text('Publicar tienda'),
                ),
                if (_publishedUrl != null) ...[
                  const SizedBox(height: 18),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _viewStore,
                        icon: const Icon(Icons.open_in_new),
                        label: const Text('Ver tienda'),
                      ),
                      FilledButton.icon(
                        onPressed: _shareStore,
                        icon: const Icon(Icons.share_outlined),
                        label: const Text('Compartir tienda'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _copyStoreLink,
                    icon: const Icon(Icons.copy_outlined),
                    label: const Text('Copiar enlace'),
                  ),
                  SelectableText(
                    _publishedUrl!,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StoreImagePicker extends StatelessWidget {
  final String title;
  final ImageProvider? image;
  final VoidCallback onPick;
  final VoidCallback? onRemove;
  final bool isBanner;

  const _StoreImagePicker({
    required this.title,
    required this.image,
    required this.onPick,
    required this.onRemove,
    this.isBanner = false,
  });

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (image != null)
          Image(
            image: image!,
            height: isBanner ? 130 : 110,
            fit: isBanner ? BoxFit.cover : BoxFit.contain,
          )
        else
          SizedBox(
            height: isBanner ? 110 : 90,
            child: Icon(
              isBanner ? Icons.panorama_outlined : Icons.storefront_outlined,
              size: 36,
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
          child: Row(
            children: [
              Expanded(child: Text(title)),
              IconButton(
                tooltip: image == null ? 'Subir $title' : 'Cambiar $title',
                onPressed: onPick,
                icon: const Icon(Icons.upload_outlined),
              ),
              if (onRemove != null)
                IconButton(
                  tooltip: 'Quitar $title',
                  onPressed: onRemove,
                  icon: const Icon(Icons.delete_outline),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _ColorSelector extends StatelessWidget {
  static const _colors = [
    0xFF00695C,
    0xFF1565C0,
    0xFF6A1B9A,
    0xFFAD1457,
    0xFFC62828,
    0xFFEF6C00,
    0xFF827717,
    0xFF37474F,
  ];

  final String title;
  final int selectedColor;
  final ValueChanged<int> onSelected;

  const _ColorSelector({
    required this.title,
    required this.selectedColor,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 10),
      Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final color in _colors)
            Semantics(
              label: '$title ${VirtualStoreCatalogBuilder.colorToHex(color)}',
              selected: color == selectedColor,
              child: InkWell(
                onTap: () => onSelected(color),
                customBorder: const CircleBorder(),
                child: CircleAvatar(
                  radius: 21,
                  backgroundColor: Color(color),
                  child: color == selectedColor
                      ? const Icon(Icons.check, color: Colors.white, size: 19)
                      : null,
                ),
              ),
            ),
        ],
      ),
    ],
  );
}
