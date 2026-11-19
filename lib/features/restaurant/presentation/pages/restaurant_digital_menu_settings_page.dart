import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/restaurant_menu_publication_settings.dart';
import '../../data/restaurant_menu_publisher.dart';
import '../../data/restaurant_menu_repository.dart';
import '../../domain/entities/restaurant_menu.dart';

class RestaurantDigitalMenuSettingsPage extends StatefulWidget {
  const RestaurantDigitalMenuSettingsPage({super.key});

  @override
  State<RestaurantDigitalMenuSettingsPage> createState() =>
      _RestaurantDigitalMenuSettingsPageState();
}

class _RestaurantDigitalMenuSettingsPageState
    extends State<RestaurantDigitalMenuSettingsPage> {
  static const _palette = [
    (0xFF315C46, 0xFFD8A15D),
    (0xFF253B56, 0xFFC88950),
    (0xFF6B332E, 0xFFD9B86C),
    (0xFF493A5C, 0xFFC7A5D4),
  ];

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _sloganController = TextEditingController();
  final _phoneController = TextEditingController();
  final _messageController = TextEditingController();
  final _repository = RestaurantMenuRepository();
  final _publisher = const RestaurantMenuPublisher();

  RestaurantMenuPublicationSettings? _settings;
  RestaurantMenuState _menu = const RestaurantMenuState();
  String? _logoData;
  int _primaryColor = _palette.first.$1;
  int _accentColor = _palette.first.$2;
  bool _loading = true;
  bool _saving = false;
  bool _publishing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _sloganController.dispose();
    _phoneController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final settings = RestaurantMenuPublicationSettings.load();
      final menu = _repository.load();
      if (!mounted) return;
      setState(() {
        _settings = settings;
        _menu = menu;
        _nameController.text = settings.restaurantName;
        _sloganController.text = settings.slogan;
        _phoneController.text = settings.whatsappNumber;
        _messageController.text = settings.whatsappMessage;
        _logoData = settings.logoData;
        _primaryColor = settings.primaryColor;
        _accentColor = settings.accentColor;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
      _showMessage('No se pudo cargar la configuración del menú: $error');
    }
  }

  RestaurantMenuPublicationSettings _readForm() {
    final settings = _settings!;
    return settings.copyWith(
      restaurantName: _nameController.text.trim(),
      slogan: _sloganController.text.trim(),
      whatsappNumber: _phoneController.text.replaceAll(RegExp(r'\D'), ''),
      whatsappMessage: _messageController.text.trim(),
      logoData: _logoData,
      clearLogo: _logoData == null,
      primaryColor: _primaryColor,
      accentColor: _accentColor,
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final settings = _readForm();
      await settings.save();
      if (!mounted) return;
      setState(() {
        _settings = settings;
        _saving = false;
      });
      _showMessage('Configuración del menú guardada.');
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      _showMessage('No se pudo guardar la configuración: $error');
    }
  }

  Future<void> _publish() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _publishing = true);
    try {
      final settings = _readForm();
      await settings.save();
      final menu = _repository.load();
      _repository.validate(menu);
      final payload = RestaurantMenuCatalogBuilder().build(settings, menu);
      final url = await _publisher.publish(settings: settings, menu: payload);
      final publishedSettings = settings.copyWith(
        publishedUrl: url,
        lastPublishedAt: DateTime.now(),
      );
      await publishedSettings.save();
      if (!mounted) return;
      setState(() {
        _settings = publishedSettings;
        _menu = menu;
        _publishing = false;
      });
      _showMessage('El menú digital se publicó correctamente.');
    } catch (error) {
      if (!mounted) return;
      setState(() => _publishing = false);
      _showMessage('No se pudo publicar el menú: $error');
    }
  }

  Future<void> _pickLogo() async {
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 82,
        maxWidth: 1400,
      );
      if (file == null || !mounted) return;
      final bytes = await file.readAsBytes();
      if (bytes.length > 1024 * 1024) {
        _showMessage('El logotipo debe pesar menos de 1 MB.');
        return;
      }
      setState(() => _logoData = base64Encode(bytes));
    } catch (error) {
      _showMessage('No se pudo cargar el logotipo: $error');
    }
  }

  Future<void> _copyPublishedUrl() async {
    final url = _settings?.publishedUrl ?? '';
    if (url.isEmpty) return;
    try {
      await Clipboard.setData(ClipboardData(text: url));
      _showMessage('Enlace copiado.');
    } catch (error) {
      _showMessage('No se pudo copiar el enlace: $error');
    }
  }

  Future<void> _sharePublishedUrl() async {
    final url = _settings?.publishedUrl ?? '';
    if (url.isEmpty) return;
    try {
      await SharePlus.instance.share(
        ShareParams(
          title: 'Menú de ${_settings?.restaurantName ?? 'restaurante'}',
          text: url,
        ),
      );
    } catch (error) {
      _showMessage('No se pudo compartir el enlace: $error');
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  Widget _logoPreview({required double size}) {
    final source = _logoData;
    if (source != null && source.isNotEmpty) {
      try {
        return Image.memory(
          base64Decode(source),
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _logoPlaceholder(size),
        );
      } on FormatException {
        return _logoPlaceholder(size);
      }
    }
    return _logoPlaceholder(size);
  }

  Widget _logoPlaceholder(double size) => Container(
    width: size,
    height: size,
    color: Color(_primaryColor).withValues(alpha: .1),
    child: Icon(
      Icons.restaurant_rounded,
      size: size * .4,
      color: Color(_primaryColor),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final settings = _settings;
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Menú digital del restaurante'),
        actions: [
          IconButton(
            tooltip: 'Actualizar configuración',
            onPressed: _loading || _saving || _publishing ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : settings == null
          ? const Center(
              child: Text('No se pudo inicializar la configuración del menú.'),
            )
          : Form(
              key: _formKey,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 1000;
                  final configuration = _configurationForm(colors);
                  final preview = _previewCard();
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 36),
                    children: [
                      _introCard(colors),
                      const SizedBox(height: 18),
                      if (wide)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 6, child: configuration),
                            const SizedBox(width: 20),
                            Expanded(flex: 5, child: preview),
                          ],
                        )
                      else ...[
                        configuration,
                        const SizedBox(height: 18),
                        preview,
                      ],
                      const SizedBox(height: 18),
                      _publicationCard(settings),
                    ],
                  );
                },
              ),
            ),
    );
  }

  Widget _introCard(ColorScheme colors) => Container(
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [
          Color(_primaryColor).withValues(alpha: .13),
          colors.surfaceContainerLow,
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: colors.outlineVariant.withValues(alpha: .55)),
    ),
    child: Row(
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: Color(_primaryColor).withValues(alpha: .12),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(Icons.public_rounded, color: Color(_primaryColor)),
        ),
        const SizedBox(width: 15),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Tu carta, lista para compartir',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              SizedBox(height: 5),
              Text(
                'Personaliza la identidad y publica categorías y productos del '
                'menú del restaurante con su disponibilidad.',
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _configurationForm(ColorScheme colors) => _SettingsCard(
    title: 'Identidad y contacto',
    subtitle: 'Estos datos aparecerán en la carta pública.',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: _logoPreview(size: 104),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Logotipo del restaurante',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'Se mostrará en grande al costado del menú.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _saving || _publishing ? null : _pickLogo,
                        icon: const Icon(Icons.upload_rounded, size: 18),
                        label: Text(
                          _logoData == null ? 'Subir logo' : 'Cambiar',
                        ),
                      ),
                      if (_logoData != null)
                        IconButton(
                          tooltip: 'Quitar logotipo',
                          onPressed: _saving || _publishing
                              ? null
                              : () => setState(() => _logoData = null),
                          icon: const Icon(Icons.delete_outline_rounded),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        TextFormField(
          controller: _nameController,
          textCapitalization: TextCapitalization.words,
          maxLength: 120,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: 'Nombre del restaurante',
            prefixIcon: Icon(Icons.storefront_outlined),
          ),
          validator: (value) => value == null || value.trim().isEmpty
              ? 'Ingresa el nombre del restaurante.'
              : null,
        ),
        const SizedBox(height: 14),
        TextFormField(
          controller: _sloganController,
          textCapitalization: TextCapitalization.sentences,
          maxLength: 100,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: 'Frase o especialidad',
            hintText: 'Ej.: Cocina artesanal, ingredientes frescos',
            prefixIcon: Icon(Icons.auto_awesome_outlined),
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: _phoneController,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: 'WhatsApp del restaurante',
            hintText: 'Código de país y número',
            prefixIcon: Icon(Icons.phone_outlined),
            helperText: 'Se usará para pedidos desde la carta pública.',
          ),
          validator: (value) {
            final digits = (value ?? '').replaceAll(RegExp(r'\D'), '');
            if (digits.isNotEmpty &&
                (digits.length < 8 || digits.length > 15)) {
              return 'Ingresa entre 8 y 15 dígitos, con código de país.';
            }
            return null;
          },
        ),
        const SizedBox(height: 14),
        TextFormField(
          controller: _messageController,
          maxLength: 300,
          maxLines: 3,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Mensaje predeterminado de WhatsApp',
            hintText: 'Hola, quisiera hacer un pedido...',
            alignLabelWithHint: true,
            prefixIcon: Icon(Icons.chat_bubble_outline_rounded),
          ),
          validator: (value) => (value?.length ?? 0) > 300
              ? 'El mensaje no puede superar 300 caracteres.'
              : null,
        ),
        const SizedBox(height: 16),
        Text(
          'Estilo de la carta',
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final (primary, accent) in _palette)
              _PaletteButton(
                primary: primary,
                accent: accent,
                selected: _primaryColor == primary && _accentColor == accent,
                onTap: _saving || _publishing
                    ? null
                    : () => setState(() {
                        _primaryColor = primary;
                        _accentColor = accent;
                      }),
              ),
          ],
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _saving || _publishing ? null : _save,
          icon: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_outlined),
          label: Text(_saving ? 'Guardando...' : 'Guardar configuración'),
        ),
      ],
    ),
  );

  Widget _previewCard() {
    final categories = _menu.categories;
    final firstCategory = categories.isEmpty ? null : categories.first;
    final sampleProducts = firstCategory == null
        ? const <RestaurantMenuProduct>[]
        : _menu.products
              .where((product) => product.categoryId == firstCategory.id)
              .take(2)
              .toList();
    return _SettingsCard(
      title: 'Vista previa',
      subtitle: 'Así se verá la carta en teléfono y computadora.',
      child: Container(
        constraints: const BoxConstraints(minHeight: 350),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFF9F7F1),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Color(_accentColor).withValues(alpha: .5)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 122,
              child: Column(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: _logoPreview(size: 110),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _nameController.text.trim().isEmpty
                        ? 'Tu restaurante'
                        : _nameController.text.trim(),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(_primaryColor),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (_sloganController.text.trim().isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Text(
                      _sloganController.text.trim(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 11),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'CARTA',
                    style: TextStyle(
                      color: Color(_accentColor),
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                      fontSize: 10,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    firstCategory?.name ?? 'Categorías del menú',
                    style: TextStyle(
                      color: Color(_primaryColor),
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (sampleProducts.isEmpty)
                    const Text(
                      'Agrega productos en Menú del restaurante para verlos aquí.',
                      style: TextStyle(fontSize: 12),
                    )
                  else
                    for (final product in sampleProducts)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    product.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  if (product.description.trim().isNotEmpty)
                                    Text(
                                      product.description,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: Colors.black54,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            Text(
                              '${product.price.toStringAsFixed(2)} ${product.currencyCode}',
                              style: TextStyle(
                                color: Color(_primaryColor),
                                fontWeight: FontWeight.w800,
                              ),
                            ),
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

  Widget _publicationCard(RestaurantMenuPublicationSettings settings) {
    final lastPublished = settings.lastPublishedAt;
    return _SettingsCard(
      title: 'Publicación',
      subtitle:
          'La carta usa los productos y categorías guardados en el menú del restaurante.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (settings.publishedUrl.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  const Icon(Icons.link_rounded),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SelectableText(
                      settings.publishedUrl,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Copiar enlace',
                    onPressed: _copyPublishedUrl,
                    icon: const Icon(Icons.copy_rounded),
                  ),
                  IconButton(
                    tooltip: 'Compartir enlace',
                    onPressed: _sharePublishedUrl,
                    icon: const Icon(Icons.share_outlined),
                  ),
                ],
              ),
            ),
            if (lastPublished != null) ...[
              const SizedBox(height: 8),
              Text(
                'Última publicación: ${MaterialLocalizations.of(context).formatMediumDate(lastPublished)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 12),
          ],
          FilledButton.icon(
            onPressed: _publishing || _saving ? null : _publish,
            icon: _publishing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.publish_rounded),
            label: Text(
              _publishing ? 'Publicando...' : 'Publicar menú digital',
            ),
          ),
          const SizedBox(height: 9),
          Text(
            'Los cambios guardados aparecen en el enlace después de publicar '
            'nuevamente. La propagación puede tardar unos minutos.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;

  const _SettingsCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: colors.outlineVariant.withValues(alpha: .55)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 18),
            child,
          ],
        ),
      ),
    );
  }
}

class _PaletteButton extends StatelessWidget {
  final int primary;
  final int accent;
  final bool selected;
  final VoidCallback? onTap;

  const _PaletteButton({
    required this.primary,
    required this.accent,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(14),
    child: Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border.all(
          color: selected
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.outlineVariant,
          width: selected ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ColorDot(color: primary),
          const SizedBox(width: 6),
          _ColorDot(color: accent),
        ],
      ),
    ),
  );
}

class _ColorDot extends StatelessWidget {
  final int color;

  const _ColorDot({required this.color});

  @override
  Widget build(BuildContext context) => Container(
    width: 22,
    height: 22,
    decoration: BoxDecoration(
      color: Color(color),
      shape: BoxShape.circle,
      border: Border.all(color: Colors.black.withValues(alpha: .08)),
    ),
  );
}
