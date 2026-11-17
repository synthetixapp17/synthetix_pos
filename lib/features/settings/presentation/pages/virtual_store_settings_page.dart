import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/data/hive_database.dart';
import '../../data/virtual_store_publisher.dart';
import '../../data/virtual_store_settings.dart';

class VirtualStoreSettingsPage extends StatefulWidget {
  const VirtualStoreSettingsPage({super.key});

  @override
  State<VirtualStoreSettingsPage> createState() =>
      _VirtualStoreSettingsPageState();
}

class _VirtualStoreSettingsPageState extends State<VirtualStoreSettingsPage> {
  static const _colorOptions = [
    ('Bosque', 0xFF176B55),
    ('Turquesa', 0xFF008C95),
    ('Esmeralda', 0xFF16845B),
    ('Oliva', 0xFF71833B),
    ('Azul marino', 0xFF203864),
    ('Cobalto', 0xFF2457C5),
    ('Cielo', 0xFF378ADD),
    ('Índigo', 0xFF4945A8),
    ('Lavanda', 0xFF8064A2),
    ('Ciruela', 0xFF773B67),
    ('Rosa', 0xFFC34F79),
    ('Coral', 0xFFE56B5D),
    ('Terracota', 0xFFB65C3A),
    ('Mandarina', 0xFFE78328),
    ('Dorado', 0xFFB58A2A),
    ('Amarillo', 0xFFFFB300),
    ('Aguamarina', 0xFF00A896),
    ('Grafito', 0xFF343A40),
    ('Negro', 0xFF242424),
  ];

  final _formKey = GlobalKey<FormState>();
  late final VirtualStoreSettings _initialSettings;
  late final TextEditingController _businessName;
  late final TextEditingController _slogan;
  late final TextEditingController _whatsapp;
  late final TextEditingController _logo;
  late int _primaryColor;
  late int _accentColor;
  String? _publishedUrl;
  bool _isSaving = false;
  bool _isPublishing = false;

  @override
  void initState() {
    super.initState();
    _initialSettings = VirtualStoreSettings.load();
    _businessName = TextEditingController(text: _initialSettings.businessName);
    _slogan = TextEditingController(text: _initialSettings.slogan);
    _whatsapp = TextEditingController(text: _initialSettings.whatsappNumber);
    _logo = TextEditingController(text: _initialSettings.logo);
    _primaryColor = _initialSettings.primaryColor;
    _accentColor = _initialSettings.accentColor;
    _publishedUrl = _initialSettings.publishedUrl.isEmpty
        ? null
        : _initialSettings.publishedUrl;
  }

  @override
  void dispose() {
    _businessName.dispose();
    _slogan.dispose();
    _whatsapp.dispose();
    _logo.dispose();
    super.dispose();
  }

  VirtualStoreSettings? _readForm() {
    if (!_formKey.currentState!.validate()) return null;
    final settings = VirtualStoreSettings(
      businessName: _businessName.text.trim(),
      slogan: _slogan.text.trim(),
      whatsappNumber: _whatsapp.text.replaceAll(RegExp(r'\D'), ''),
      logo: _logo.text.trim(),
      primaryColor: _primaryColor,
      accentColor: _accentColor,
      businessId: _initialSettings.businessId,
      clientSecret: _initialSettings.clientSecret,
      lastPublishedAt: _initialSettings.lastPublishedAt,
      publishedUrl: _initialSettings.publishedUrl,
    );
    return settings;
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
        primaryColor: settings.primaryColor,
        accentColor: settings.accentColor,
        businessId: settings.businessId,
        clientSecret: settings.clientSecret,
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
        _showMessage('Tienda actualizada y publicada correctamente.');
      }
    } catch (error) {
      if (mounted) _showMessage('No se pudo actualizar la tienda: $error');
    } finally {
      if (mounted) setState(() => _isPublishing = false);
    }
  }

  Future<void> _pickLogo() async {
    try {
      final selected = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 80,
      );
      if (selected == null) return;
      final mimeType = _imageMimeType(selected);
      final bytes = await selected.readAsBytes();
      if (bytes.length > 2 * 1024 * 1024) {
        throw const FormatException(
          'El logotipo supera 2 MB; elige una imagen más pequeña.',
        );
      }
      setState(() {
        _logo.text = 'data:$mimeType;base64,${base64Encode(bytes)}';
      });
    } catch (error) {
      if (mounted) _showMessage('No se pudo cargar el logotipo: $error');
    }
  }

  String _imageMimeType(XFile file) {
    final mimeType = file.mimeType;
    if (mimeType != null &&
        const {'image/png', 'image/jpeg', 'image/webp'}.contains(mimeType)) {
      return mimeType;
    }
    return switch (file.name.toLowerCase().split('.').last) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      'jpg' || 'jpeg' => 'image/jpeg',
      _ => throw const FormatException(
        'Selecciona un logotipo PNG, JPG o WebP.',
      ),
    };
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

  String? _validateLogo(String? value) {
    final source = value?.trim() ?? '';
    if (source.isEmpty) return null;
    if (source.startsWith('data:image/')) {
      if (!RegExp(
        r'^data:image/(png|jpeg|webp);base64,[A-Za-z0-9+/]+=*$',
      ).hasMatch(source)) {
        return 'El logotipo debe ser una imagen PNG, JPG o WebP válida.';
      }
      try {
        if (base64Decode(source.substring(source.indexOf(',') + 1)).length >
            2 * 1024 * 1024) {
          return 'El logotipo debe pesar menos de 2 MB.';
        }
      } on FormatException {
        return 'El contenido del logotipo no es válido.';
      }
      return null;
    }
    final uri = Uri.tryParse(source);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      return 'Usa una URL HTTPS válida o carga una imagen local.';
    }
    return null;
  }

  Widget _textField(
    TextEditingController controller,
    String label, {
    String? helper,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    int maxLines = 1,
    bool obscureText = false,
    Widget? suffixIcon,
    List<TextInputFormatter>? inputFormatters,
    ValueChanged<String>? onChanged,
  }) => TextFormField(
    controller: controller,
    decoration: InputDecoration(
      labelText: label,
      helperText: helper,
      border: const OutlineInputBorder(),
      suffixIcon: suffixIcon,
    ),
    keyboardType: keyboardType,
    maxLines: obscureText ? 1 : maxLines,
    obscureText: obscureText,
    validator: validator,
    inputFormatters: inputFormatters,
    onChanged: onChanged,
  );

  Widget _sectionTitle(String title, String subtitle) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
      ],
    ),
  );

  Widget _colorChoices(
    String title,
    int selectedColor,
    ValueChanged<int> onSelected,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final (name, color) in _colorOptions)
            ChoiceChip(
              key: ValueKey('$title-$name'),
              selected: selectedColor == color,
              onSelected: (_) => setState(() => onSelected(color)),
              avatar: CircleAvatar(backgroundColor: Color(color), radius: 10),
              label: Text(name),
            ),
        ],
      ),
    ],
  );

  Color _textColorOn(Color background) =>
      background.computeLuminance() > 0.55 ? Colors.black87 : Colors.white;

  Widget _storePreview() {
    final primary = Color(_primaryColor);
    final secondary = Color(_accentColor);
    final businessName = _businessName.text.trim();
    final slogan = _slogan.text.trim();
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFF7F6F2),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              color: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.storefront_rounded, color: primary),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      businessName.isEmpty ? 'Tu tienda' : businessName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF202824),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Icon(Icons.shopping_bag_outlined, color: primary),
                ],
              ),
            ),
            Container(
              margin: const EdgeInsets.all(12),
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [primary, Color.lerp(primary, Colors.black, 0.24)!],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Stack(
                children: [
                  Positioned(
                    right: -30,
                    top: -55,
                    child: Container(
                      width: 180,
                      height: 180,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.12),
                          width: 28,
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(30),
                          ),
                          child: Text(
                            'CATÁLOGO EXCLUSIVO',
                            style: TextStyle(
                              color: _textColorOn(primary),
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.1,
                            ),
                          ),
                        ),
                        const SizedBox(height: 13),
                        Text(
                          businessName.isEmpty
                              ? 'Una experiencia de compra especial'
                              : businessName,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                color: _textColorOn(primary),
                                fontWeight: FontWeight.w800,
                                height: 1.1,
                              ),
                        ),
                        if (slogan.isNotEmpty) ...[
                          const SizedBox(height: 7),
                          Text(
                            slogan,
                            style: TextStyle(
                              color: _textColorOn(
                                primary,
                              ).withValues(alpha: 0.88),
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: null,
                          style: FilledButton.styleFrom(
                            backgroundColor: secondary,
                            foregroundColor: _textColorOn(secondary),
                            disabledBackgroundColor: secondary,
                            disabledForegroundColor: _textColorOn(secondary),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                          ),
                          child: const Text('Explorar productos'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 2, 18, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Selección destacada',
                    style: TextStyle(
                      color: Color(0xFF202824),
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 11),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE8E8E2)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 68,
                          height: 68,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Color.lerp(primary, Colors.white, 0.12)!,
                                secondary.withValues(alpha: 0.7),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.local_mall_outlined,
                            color: _textColorOn(secondary),
                            size: 30,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Producto destacado',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF202824),
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Calidad seleccionada para ti',
                                style: TextStyle(
                                  color: Color(0xFF777D78),
                                  fontSize: 11,
                                ),
                              ),
                              SizedBox(height: 7),
                              Text(
                                '\$ 24.00',
                                style: TextStyle(
                                  color: Color(0xFF202824),
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.arrow_forward_rounded, color: primary),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _logoPreview({double size = 76}) {
    final source = _logo.text.trim();
    if (source.isEmpty) {
      return Icon(Icons.storefront_outlined, size: size * 0.55);
    }
    try {
      final image = source.startsWith('data:image/')
          ? Image.memory(
              base64Decode(source.substring(source.indexOf(',') + 1)),
              fit: BoxFit.contain,
            )
          : Image.network(source, fit: BoxFit.contain);
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(width: size, height: size, child: image),
      );
    } on FormatException {
      return const Icon(Icons.broken_image_outlined, size: 42);
    }
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
                      'El catálogo que publiques será visible para cualquier persona. Puedes actualizarlo cuando quieras desde esta pantalla.',
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                _sectionTitle(
                  'Identidad de la tienda',
                  'Información que verán tus clientes en la web.',
                ),
                _textField(
                  _businessName,
                  'Nombre del negocio',
                  onChanged: (_) => setState(() {}),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Ingresa el nombre del negocio.'
                      : null,
                ),
                const SizedBox(height: 14),
                _textField(
                  _slogan,
                  'Eslogan o descripción corta',
                  maxLines: 2,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 14),
                _textField(
                  _whatsapp,
                  'WhatsApp con código de país',
                  helper: 'Solo números, por ejemplo 584120000000.',
                  keyboardType: TextInputType.phone,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9 +()-]')),
                  ],
                  validator: (value) {
                    final number = value?.replaceAll(RegExp(r'\D'), '') ?? '';
                    return number.length < 8 || number.length > 15
                        ? 'Ingresa entre 8 y 15 dígitos, incluido el código de país.'
                        : null;
                  },
                ),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _textField(
                        _logo,
                        'URL HTTPS del logotipo',
                        helper:
                            'También puedes cargar una imagen desde el dispositivo.',
                        onChanged: (_) => setState(() {}),
                        validator: _validateLogo,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: OutlinedButton.icon(
                        onPressed: _pickLogo,
                        icon: const Icon(Icons.upload_outlined),
                        label: const Text('Subir'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    width: 92,
                    height: 92,
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    alignment: Alignment.center,
                    child: _logoPreview(),
                  ),
                ),
                const SizedBox(height: 24),
                _sectionTitle(
                  'Colores de la tienda',
                  'Elige por separado los colores que identifican tu tienda.',
                ),
                _colorChoices(
                  'Color primario',
                  _primaryColor,
                  (color) => _primaryColor = color,
                ),
                const SizedBox(height: 16),
                _colorChoices(
                  'Color secundario',
                  _accentColor,
                  (color) => _accentColor = color,
                ),
                const SizedBox(height: 18),
                _sectionTitle(
                  'Previsualización',
                  'Mira cómo se verá el estilo de tu tienda.',
                ),
                _storePreview(),
                const SizedBox(height: 22),
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
                  label: const Text('Actualizar Tienda'),
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
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
