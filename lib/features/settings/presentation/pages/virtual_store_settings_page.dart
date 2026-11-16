import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';

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
  static const _palettes = [
    ('Turquesa', 0xFF008C95, 0xFFFFB300),
    ('Esmeralda', 0xFF16845B, 0xFFFFC857),
    ('Azul', 0xFF2457C5, 0xFFFFA62B),
    ('Morado', 0xFF7041A6, 0xFFFFB454),
    ('Negro', 0xFF242424, 0xFF00A896),
  ];

  final _formKey = GlobalKey<FormState>();
  late final VirtualStoreSettings _initialSettings;
  late final TextEditingController _businessName;
  late final TextEditingController _slogan;
  late final TextEditingController _whatsapp;
  late final TextEditingController _logo;
  late final TextEditingController _githubOwner;
  late final TextEditingController _githubRepository;
  late final TextEditingController _publisherApiKey;
  late int _primaryColor;
  late int _accentColor;
  String? _publishedUrl;
  bool _isSaving = false;
  bool _isPublishing = false;
  bool _obscureApiKey = true;

  @override
  void initState() {
    super.initState();
    _initialSettings = VirtualStoreSettings.load();
    _businessName = TextEditingController(text: _initialSettings.businessName);
    _slogan = TextEditingController(text: _initialSettings.slogan);
    _whatsapp = TextEditingController(text: _initialSettings.whatsappNumber);
    _logo = TextEditingController(text: _initialSettings.logo);
    _githubOwner = TextEditingController(text: _initialSettings.githubOwner);
    _githubRepository = TextEditingController(
      text: _initialSettings.githubRepository,
    );
    _publisherApiKey = TextEditingController(
      text: _initialSettings.publisherApiKey,
    );
    _primaryColor = _initialSettings.primaryColor;
    _accentColor = _initialSettings.accentColor;
    if (_initialSettings.lastPublishedAt != null &&
        _githubOwner.text.isNotEmpty &&
        _githubRepository.text.isNotEmpty) {
      _publishedUrl = VirtualStoreCatalogBuilder.publicStoreUrl(
        _githubOwner.text,
        _githubRepository.text,
      );
    }
  }

  @override
  void dispose() {
    _businessName.dispose();
    _slogan.dispose();
    _whatsapp.dispose();
    _logo.dispose();
    _githubOwner.dispose();
    _githubRepository.dispose();
    _publisherApiKey.dispose();
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
      githubOwner: _githubOwner.text.trim(),
      githubRepository: _githubRepository.text.trim(),
      publisherApiKey: _publisherApiKey.text.trim(),
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
        _publishedUrl = null;
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
    if (settings.publisherApiKey.isEmpty) {
      _showMessage('Ingresa la clave de acceso del servicio de publicación.');
      return;
    }

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
      await VirtualStorePublisher().publish(
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
        githubOwner: settings.githubOwner,
        githubRepository: settings.githubRepository,
        publisherApiKey: settings.publisherApiKey,
        lastPublishedAt: DateTime.now(),
      );
      await HiveDatabase.settingsBox.put(
        virtualStoreSettingsKey,
        jsonEncode(publishedSettings.toJson()),
      );
      if (mounted) {
        setState(() {
          _publishedUrl = VirtualStoreCatalogBuilder.publicStoreUrl(
            settings.githubOwner,
            settings.githubRepository,
          );
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

  Widget _colorChoices() => Wrap(
    spacing: 10,
    runSpacing: 10,
    children: [
      for (final (name, primary, accent) in _palettes)
        ChoiceChip(
          selected: _primaryColor == primary && _accentColor == accent,
          onSelected: (_) => setState(() {
            _primaryColor = primary;
            _accentColor = accent;
          }),
          avatar: CircleAvatar(
            backgroundColor: Color(primary),
            child: Icon(Icons.circle, size: 12, color: Color(accent)),
          ),
          label: Text(name),
        ),
    ],
  );

  Widget _logoPreview() {
    final source = _logo.text.trim();
    if (source.isEmpty) {
      return const Icon(Icons.storefront_outlined, size: 42);
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
        child: SizedBox(width: 76, height: 76, child: image),
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
                      'La tienda y su catálogo serán públicos en GitHub Pages. El token de GitHub permanece únicamente en el servicio de publicación; la clave de esta pantalla solo autoriza a la app a usar ese servicio.',
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
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Ingresa el nombre del negocio.'
                      : null,
                ),
                const SizedBox(height: 14),
                _textField(_slogan, 'Eslogan o descripción corta', maxLines: 2),
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
                  'Los colores se aplicarán a los botones y destacados del sitio.',
                ),
                _colorChoices(),
                const SizedBox(height: 24),
                _sectionTitle(
                  'Repositorio GitHub Pages',
                  'Configura un repositorio público exclusivo para este comercio.',
                ),
                Row(
                  children: [
                    Expanded(
                      child: _textField(
                        _githubOwner,
                        'Usuario u organización',
                        validator: (value) =>
                            value == null ||
                                !RegExp(r'^[A-Za-z0-9-]{1,39}$').hasMatch(value)
                            ? 'Nombre de usuario GitHub inválido.'
                            : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _textField(
                        _githubRepository,
                        'Nombre del repositorio',
                        validator: (value) =>
                            value == null ||
                                !RegExp(
                                  r'^[A-Za-z0-9._-]{1,100}$',
                                ).hasMatch(value)
                            ? 'Nombre de repositorio inválido.'
                            : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Cloudflare Worker',
                    border: OutlineInputBorder(),
                  ),
                  child: SelectableText(virtualStoreWorkerUrl),
                ),
                const SizedBox(height: 14),
                _textField(
                  _publisherApiKey,
                  'Clave de acceso del servicio',
                  helper:
                      'Clave exclusiva de este repositorio registrada en CLIENT_API_KEYS. No ingreses tu token de GitHub.',
                  obscureText: _obscureApiKey,
                  suffixIcon: IconButton(
                    tooltip: _obscureApiKey ? 'Mostrar clave' : 'Ocultar clave',
                    onPressed: () =>
                        setState(() => _obscureApiKey = !_obscureApiKey),
                    icon: Icon(
                      _obscureApiKey
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
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
                  FilledButton.icon(
                    onPressed: _shareStore,
                    icon: const Icon(Icons.link),
                    label: const Text('Compartir Tienda Virtual'),
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
