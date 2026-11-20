import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

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
    (name: 'Bosque', primary: 0xFF315C46, accent: 0xFFD8A15D),
    (name: 'Marino', primary: 0xFF253B56, accent: 0xFFC88950),
    (name: 'Terracota', primary: 0xFF6B332E, accent: 0xFFD9B86C),
    (name: 'Lavanda', primary: 0xFF493A5C, accent: 0xFFC7A5D4),
    (name: 'Cobre', primary: 0xFF8A4B32, accent: 0xFFE2A66F),
    (name: 'Caribe', primary: 0xFF245B63, accent: 0xFFE4B95F),
    (name: 'Frambuesa', primary: 0xFF713F58, accent: 0xFFE7A7A1),
    (name: 'Oliva', primary: 0xFF4F5940, accent: 0xFFC8CF91),
    (name: 'Brisa', primary: 0xFF34495E, accent: 0xFF70A9A1),
    (name: 'Miel', primary: 0xFF8A5A24, accent: 0xFFE8CF8A),
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
  int _primaryColor = _palette.first.primary;
  int _accentColor = _palette.first.accent;
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

  Future<void> _viewMenu() async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Vista previa de todos los cambios'),
        content: SizedBox(
          width: double.maxFinite,
          height: MediaQuery.sizeOf(context).height * .62,
          child: SingleChildScrollView(
            child: _digitalMenuPreview(expanded: true),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  Future<void> _openPublishedMenu() async {
    final publishedUrl = _settings?.publishedUrl ?? '';
    if (publishedUrl.isEmpty) return;
    try {
      final uri = Uri.parse(publishedUrl);
      if (uri.scheme != 'https') {
        throw const FormatException('El enlace publicado no es seguro.');
      }
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw Exception('No se pudo abrir el enlace.');
      }
    } catch (error) {
      _showMessage('No se pudo visualizar el menú publicado: $error');
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
        title: const Text('Menú digital'),
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
                  final wide = constraints.maxWidth >= 1080;
                  final configuration = _configurationForm(colors);
                  final preview = _previewCard();
                  return Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1440),
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
                        children: [
                          _introCard(),
                          const SizedBox(height: 22),
                          if (wide)
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(flex: 6, child: configuration),
                                const SizedBox(width: 22),
                                Expanded(flex: 5, child: preview),
                              ],
                            )
                          else ...[
                            configuration,
                            const SizedBox(height: 8),
                            preview,
                          ],
                          const SizedBox(height: 8),
                          _publicationCard(settings),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }

  Widget _introCard() => Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [
          Color(_primaryColor),
          Color.lerp(Color(_primaryColor), Colors.black, .16)!,
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(26),
      boxShadow: [
        BoxShadow(
          color: Color(_primaryColor).withValues(alpha: .12),
          blurRadius: 28,
          offset: const Offset(0, 12),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .17),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.restaurant_menu_rounded,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Text(
                'Diseña tu menú digital',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -.3,
                ),
              ),
            ),
            if (_settings?.publishedUrl.isNotEmpty == true)
              _StatusBadge(
                label: 'Publicado',
                icon: Icons.check_circle_rounded,
                foregroundColor: Colors.white,
                backgroundColor: Colors.white.withValues(alpha: .16),
              ),
          ],
        ),
        const SizedBox(height: 12),
        const Text(
          'Personaliza cómo te ven, facilita los pedidos y comparte tu carta '
          'con tus clientes.',
          style: TextStyle(color: Colors.white, height: 1.45),
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 9,
          runSpacing: 8,
          children: [
            _IntroPill(
              number: '1',
              label: 'Identidad',
              accent: Color(_accentColor),
            ),
            _IntroPill(
              number: '2',
              label: 'Vista previa',
              accent: Color(_accentColor),
            ),
            _IntroPill(
              number: '3',
              label: 'Publicación',
              accent: Color(_accentColor),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          '${_menu.categories.length} ${_menu.categories.length == 1 ? 'categoría' : 'categorías'}'
          '  ·  ${_menu.products.length} ${_menu.products.length == 1 ? 'producto' : 'productos'}'
          '  ·  Se toman de tu Menú del restaurante',
          style: TextStyle(
            color: Colors.white.withValues(alpha: .78),
            fontSize: 12,
          ),
        ),
      ],
    ),
  );

  Widget _configurationForm(ColorScheme colors) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _SettingsCard(
        eyebrow: 'PASO 1 · IDENTIDAD',
        icon: Icons.storefront_outlined,
        title: 'Presenta tu restaurante',
        subtitle: 'Esto es lo primero que verán tus clientes en la carta.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: _logoPreview(size: 76),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Logo del restaurante',
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Usa una imagen cuadrada para que luzca mejor.',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colors.onSurfaceVariant),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            OutlinedButton.icon(
                              onPressed: _saving || _publishing
                                  ? null
                                  : _pickLogo,
                              icon: Icon(
                                _logoData == null
                                    ? Icons.add_photo_alternate_outlined
                                    : Icons.swap_horiz_rounded,
                                size: 18,
                              ),
                              label: Text(
                                _logoData == null ? 'Elegir logo' : 'Cambiar',
                              ),
                            ),
                            if (_logoData != null)
                              TextButton(
                                onPressed: _saving || _publishing
                                    ? null
                                    : () => setState(() => _logoData = null),
                                child: const Text('Quitar'),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            TextFormField(
              controller: _nameController,
              textCapitalization: TextCapitalization.words,
              maxLength: 120,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Nombre del restaurante',
                hintText: 'Ej.: La Casa del Sabor',
                prefixIcon: Icon(Icons.storefront_outlined),
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Escribe el nombre que aparecerá en tu carta.'
                  : null,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _sloganController,
              textCapitalization: TextCapitalization.sentences,
              maxLength: 100,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Frase o especialidad',
                hintText: 'Ej.: Cocina artesanal con ingredientes frescos',
                helperText: 'Una frase breve que describa tu propuesta.',
                prefixIcon: Icon(Icons.auto_awesome_outlined),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 8),
      _SettingsCard(
        eyebrow: 'PASO 2 · PEDIDOS',
        icon: Icons.chat_bubble_outline_rounded,
        title: 'Facilita el contacto',
        subtitle:
            'Los clientes podrán pedir productos individuales o enviar todo su carrito por WhatsApp.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'WhatsApp para recibir pedidos',
                hintText: '584121234567',
                prefixIcon: Icon(Icons.phone_outlined),
                helperText:
                    'Incluye el código del país, sin espacios. Ejemplo: 584121234567. Si lo dejas vacío, los pedidos por WhatsApp no estarán disponibles.',
              ),
              validator: (value) {
                final digits = (value ?? '').replaceAll(RegExp(r'\D'), '');
                if (digits.isNotEmpty &&
                    (digits.length < 8 || digits.length > 15)) {
                  return 'Usa entre 8 y 15 dígitos, incluido el código de país.';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _messageController,
              maxLength: 300,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Saludo para los pedidos',
                hintText: 'Hola, quisiera hacer un pedido.',
                helperText:
                    'Se agregará automáticamente al mensaje de WhatsApp. Si lo dejas vacío, usaremos un saludo predeterminado.',
                alignLabelWithHint: true,
                prefixIcon: Icon(Icons.chat_bubble_outline_rounded),
              ),
              validator: (value) => (value?.length ?? 0) > 300
                  ? 'El saludo no puede superar 300 caracteres.'
                  : null,
            ),
          ],
        ),
      ),
      const SizedBox(height: 8),
      _SettingsCard(
        eyebrow: 'PASO 3 · APARIENCIA',
        icon: Icons.palette_outlined,
        title: 'Elige el estilo de tu carta',
        subtitle:
            'El color principal se usa en encabezados y botones; el secundario resalta detalles.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 9,
              runSpacing: 9,
              children: [
                for (final palette in _palette)
                  _PaletteButton(
                    name: palette.name,
                    primary: palette.primary,
                    accent: palette.accent,
                    selected:
                        _primaryColor == palette.primary &&
                        _accentColor == palette.accent,
                    onTap: _saving || _publishing
                        ? null
                        : () => setState(() {
                            _primaryColor = palette.primary;
                            _accentColor = palette.accent;
                          }),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            _InfoNote(
              icon: Icons.tips_and_updates_outlined,
              text:
                  'Puedes cambiar los colores cuando quieras. La vista previa se actualiza al instante.',
            ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 6, 4, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton.icon(
              onPressed: _saving || _publishing ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(_saving ? 'Guardando cambios...' : 'Guardar cambios'),
            ),
            const SizedBox(height: 7),
            Text(
              'Guardar conserva tu configuración en la aplicación. Para actualizar el enlace público, usa “Publicar menú” al final de esta página.',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _previewCard() {
    return _SettingsCard(
      eyebrow: 'VISTA PREVIA EN VIVO',
      icon: Icons.visibility_outlined,
      title: 'Así verán tu carta',
      subtitle:
          'Comprueba tu identidad, tus colores y algunos productos antes de publicar.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.circle,
                  size: 9,
                  color: Theme.of(context).colorScheme.tertiary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Menú · ${_nameController.text.trim().isEmpty ? 'Tu restaurante' : _nameController.text.trim()}',
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  'EN VIVO',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.tertiary,
                    fontWeight: FontWeight.w900,
                    letterSpacing: .5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _digitalMenuPreview(expanded: false),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _viewMenu,
            icon: const Icon(Icons.visibility_outlined),
            label: const Text('Visualizar cambios'),
          ),
        ],
      ),
    );
  }

  Widget _digitalMenuPreview({required bool expanded}) {
    final categories = expanded ? _menu.categories : _menu.categories.take(1);
    final primary = Color(_primaryColor);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFBF9F4),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Color(_accentColor).withValues(alpha: .65)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: primary,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: _logoPreview(size: 60),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _nameController.text.trim().isEmpty
                            ? 'Tu restaurante'
                            : _nameController.text.trim(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      if (_sloganController.text.trim().isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          _sloganController.text.trim(),
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ],
                    ],
                  ),
                ),
                Icon(Icons.shopping_bag_outlined, color: Color(_accentColor)),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'NUESTRA CARTA',
            style: TextStyle(
              color: primary,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.8,
            ),
          ),
          const SizedBox(height: 10),
          if (_menu.products.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Text(
                'Agrega productos en Menú del restaurante para verlos aquí.',
              ),
            )
          else
            for (final category in categories) ...[
              Text(
                category.name,
                style: TextStyle(
                  color: primary,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (category.description.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 3, bottom: 8),
                  child: Text(
                    category.description,
                    style: const TextStyle(color: Colors.black54, fontSize: 12),
                  ),
                ),
              for (final product
                  in _menu.products
                      .where((item) => item.categoryId == category.id)
                      .take(expanded ? _menu.products.length : 2))
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE9E5DC)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              product.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          Text(
                            '${product.price.toStringAsFixed(2)} ${product.currencyCode}',
                            style: TextStyle(
                              color: primary,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                      if (product.description.trim().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            product.description,
                            style: const TextStyle(
                              color: Colors.black54,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 12,
                        runSpacing: 6,
                        children: [
                          _previewAction(Icons.chat_rounded, 'WhatsApp'),
                          _previewAction(
                            Icons.add_shopping_cart_rounded,
                            'Agregar al carrito',
                          ),
                          _previewAction(Icons.share_outlined, 'Compartir'),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        product.isAvailable ? 'Disponible' : 'Agotado',
                        style: TextStyle(
                          color: product.isAvailable
                              ? const Color(0xFF315C46)
                              : Colors.red.shade700,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
        ],
      ),
    );
  }

  Widget _previewAction(IconData icon, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 15, color: Color(_primaryColor)),
      const SizedBox(width: 4),
      Text(label, style: const TextStyle(fontSize: 10)),
    ],
  );

  Widget _publicationCard(RestaurantMenuPublicationSettings settings) {
    final lastPublished = settings.lastPublishedAt;
    final isPublished = settings.publishedUrl.isNotEmpty;
    return _SettingsCard(
      eyebrow: 'PASO 4 · COMPARTIR',
      icon: Icons.public_rounded,
      title: isPublished ? 'Actualiza tu carta pública' : 'Publica tu carta',
      subtitle:
          'Publicar envía tu diseño y los productos guardados del Menú del restaurante a tu enlace web.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isPublished) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.tertiaryContainer.withValues(alpha: .55),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.check_circle_rounded,
                    color: Theme.of(context).colorScheme.tertiary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Tu carta está publicada',
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        if (lastPublished != null) ...[
                          const SizedBox(height: 3),
                          Text(
                            'Actualizada el ${MaterialLocalizations.of(context).formatMediumDate(lastPublished)}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.link_rounded,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: SelectableText(
                          settings.publishedUrl,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Wrap(
                      spacing: 4,
                      children: [
                        IconButton(
                          tooltip: 'Copiar enlace',
                          onPressed: _copyPublishedUrl,
                          icon: const Icon(Icons.copy_rounded),
                        ),
                        IconButton(
                          tooltip: 'Ver carta publicada',
                          onPressed: _openPublishedMenu,
                          icon: const Icon(Icons.open_in_new_rounded),
                        ),
                        IconButton(
                          tooltip: 'Compartir enlace',
                          onPressed: _sharePublishedUrl,
                          icon: const Icon(Icons.share_outlined),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ] else ...[
            const _InfoNote(
              icon: Icons.info_outline_rounded,
              text:
                  'Todavía no hay una carta pública. Al publicar por primera vez se creará un enlace para compartir con tus clientes.',
            ),
            const SizedBox(height: 14),
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
              _publishing
                  ? 'Publicando tu carta...'
                  : isPublished
                  ? 'Actualizar carta pública'
                  : 'Publicar carta ahora',
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Al publicar, los clientes verán la última configuración guardada y los productos disponibles. Los cambios pueden tardar unos minutos en reflejarse.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final String? eyebrow;
  final IconData? icon;
  final String title;
  final String subtitle;
  final Widget child;

  const _SettingsCard({
    this.eyebrow,
    this.icon,
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
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (icon != null) ...[
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: colors.primaryContainer,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(icon, color: colors.onPrimaryContainer),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (eyebrow != null) ...[
                        Text(
                          eyebrow!,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: colors.primary,
                                fontWeight: FontWeight.w900,
                                letterSpacing: .7,
                              ),
                        ),
                        const SizedBox(height: 3),
                      ],
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
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
  final String name;
  final int primary;
  final int accent;
  final bool selected;
  final VoidCallback? onTap;

  const _PaletteButton({
    required this.name,
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
          const SizedBox(width: 5),
          _ColorDot(color: accent),
          const SizedBox(width: 8),
          Text(name, style: Theme.of(context).textTheme.labelMedium),
          if (selected) ...[
            const SizedBox(width: 5),
            Icon(
              Icons.check_circle_rounded,
              size: 16,
              color: Theme.of(context).colorScheme.primary,
            ),
          ],
        ],
      ),
    ),
  );
}

class _InfoNote extends StatelessWidget {
  final IconData icon;
  final String text;

  const _InfoNote({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.primaryContainer.withValues(alpha: .45),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 19, color: colors.primary),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colors.onSurface,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color foregroundColor;
  final Color backgroundColor;

  const _StatusBadge({
    required this.label,
    required this.icon,
    required this.foregroundColor,
    required this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
    decoration: BoxDecoration(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: foregroundColor),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            color: foregroundColor,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );
}

class _IntroPill extends StatelessWidget {
  final String number;
  final String label;
  final Color accent;

  const _IntroPill({
    required this.number,
    required this.label,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .14),
      border: Border.all(color: Colors.white.withValues(alpha: .2)),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 20,
          height: 20,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
          child: Text(
            number,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
          ),
        ),
        const SizedBox(width: 7),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
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
