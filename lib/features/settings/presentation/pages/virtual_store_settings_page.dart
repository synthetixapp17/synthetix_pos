import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  final _formKey = GlobalKey<FormState>();
  late final VirtualStoreSettings _initialSettings;
  late final TextEditingController _businessName;
  String? _publishedUrl;
  bool _isSaving = false;
  bool _isPublishing = false;

  @override
  void initState() {
    super.initState();
    _initialSettings = VirtualStoreSettings.load();
    _businessName = TextEditingController(text: _initialSettings.businessName);
    _publishedUrl = _initialSettings.publishedUrl.isEmpty
        ? null
        : _initialSettings.publishedUrl;
  }

  @override
  void dispose() {
    _businessName.dispose();
    super.dispose();
  }

  VirtualStoreSettings? _readForm() {
    if (!_formKey.currentState!.validate()) return null;
    return VirtualStoreSettings(
      businessName: _businessName.text.trim(),
      slogan: _initialSettings.slogan,
      whatsappNumber: _initialSettings.whatsappNumber,
      logo: _initialSettings.logo,
      primaryColor: _initialSettings.primaryColor,
      accentColor: _initialSettings.accentColor,
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
                      'Ingresa el nombre de tu tienda para crear o actualizar su catálogo público.',
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
                OutlinedButton.icon(
                  onPressed: _isSaving || _isPublishing ? null : _saveLocally,
                  icon: _isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: const Text('Guardar nombre'),
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
