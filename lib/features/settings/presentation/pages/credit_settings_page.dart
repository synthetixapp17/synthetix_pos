import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../credit/data/credit_preferences.dart';

class CreditSettingsPage extends StatefulWidget {
  const CreditSettingsPage({super.key});

  @override
  State<CreditSettingsPage> createState() => _CreditSettingsPageState();
}

class _CreditSettingsPageState extends State<CreditSettingsPage> {
  static const _templates = ['Clásica', 'Minimal', 'Profesional'];
  static const _palettes = [
    (0xFF174B3B, 0xFF2E7D6F, 'Verde'),
    (0xFF183153, 0xFF43A5D5, 'Azul'),
    (0xFF56345F, 0xFFD49BD5, 'Violeta'),
    (0xFF7A3E12, 0xFFFFB74D, 'Ámbar'),
    (0xFF30343B, 0xFF8C9AA8, 'Neutro'),
  ];

  late String _template;
  late int _primaryColor;
  late int _accentColor;
  late final TextEditingController _termsController;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _template = CreditPreferences.template;
    _primaryColor = CreditPreferences.primaryColor;
    _accentColor = CreditPreferences.accentColor;
    _termsController = TextEditingController(text: CreditPreferences.terms);
  }

  @override
  void dispose() {
    _termsController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_termsController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Escribe las cláusulas del contrato.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await CreditPreferences.save(
        template: _template,
        primaryColor: _primaryColor,
        accentColor: _accentColor,
        terms: _termsController.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Diseño del contrato guardado.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo guardar la configuración: $error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme.copyWith(
      primary: Color(_primaryColor),
      secondary: Color(_accentColor),
    );
    return Theme(
      data: theme.copyWith(colorScheme: colors),
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F7FA),
        appBar: AppBar(
          title: const Text('Contrato de crédito'),
          centerTitle: true,
          backgroundColor: const Color(0xFFF5F7FA),
          leading: IconButton(
            tooltip: 'Volver',
            onPressed: () => context.pop(),
            icon: const Icon(Icons.arrow_back_rounded),
          ),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 850),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 110),
              children: [
                _SettingsCard(
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 25,
                        backgroundColor: Color(_primaryColor),
                        child: const Icon(
                          Icons.description_outlined,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Documentos claros y completos',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Personaliza los contratos PDF nuevos; los ya emitidos conservan su documento.',
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _SettingsCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _SectionHeading(
                        title: 'Presentación del PDF',
                        subtitle: 'Elige una plantilla para tus contratos.',
                      ),
                      const SizedBox(height: 14),
                      ..._templates.map((template) {
                        final selected = _template == template;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 9),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () => setState(() => _template = template),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 160),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: selected
                                    ? Color(
                                        _primaryColor,
                                      ).withValues(alpha: .08)
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: selected
                                      ? Color(_primaryColor)
                                      : const Color(0xFFE2E7ED),
                                  width: selected ? 1.6 : 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    selected
                                        ? Icons.radio_button_checked
                                        : Icons.radio_button_off,
                                    color: Color(_primaryColor),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          template,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          _templateDescription(template),
                                          style: TextStyle(
                                            color: Colors.blueGrey.shade600,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  _TemplatePreview(
                                    primary: _primaryColor,
                                    accent: _accentColor,
                                    template: template,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
                      const SizedBox(height: 8),
                      const _SectionHeading(
                        title: 'Paleta de colores',
                        subtitle: 'Se aplica al encabezado, tablas y resumen.',
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: _palettes.map((palette) {
                          final selected =
                              palette.$1 == _primaryColor &&
                              palette.$2 == _accentColor;
                          return ChoiceChip(
                            label: Text(palette.$3),
                            selected: selected,
                            avatar: CircleAvatar(
                              backgroundColor: Color(palette.$1),
                              child: Icon(
                                Icons.circle,
                                size: 9,
                                color: Color(palette.$2),
                              ),
                            ),
                            onSelected: (_) => setState(() {
                              _primaryColor = palette.$1;
                              _accentColor = palette.$2;
                            }),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _SettingsCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _SectionHeading(
                        title: 'Cláusulas y condiciones',
                        subtitle:
                            'Este texto aparecerá en el contrato de cada crédito nuevo.',
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _termsController,
                        minLines: 7,
                        maxLines: 12,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          labelText: 'Términos del contrato',
                          hintText:
                              'Describe fechas de pago, compromisos, mora y condiciones acordadas.',
                          alignLabelWithHint: true,
                          prefixIcon: Padding(
                            padding: EdgeInsets.only(bottom: 110),
                            child: Icon(Icons.gavel_outlined),
                          ),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 9),
                      Text(
                        'Incluye únicamente condiciones acordadas con el cliente.',
                        style: TextStyle(
                          color: Colors.blueGrey.shade600,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        bottomNavigationBar: SafeArea(
          minimum: const EdgeInsets.fromLTRB(18, 8, 18, 14),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 850),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(_saving ? 'Guardando...' : 'Guardar diseño'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _templateDescription(String template) => switch (template) {
    'Clásica' => 'Encabezado sólido y lectura tradicional.',
    'Minimal' => 'Diseño ligero con líneas limpias y espacio.',
    _ => 'Jerarquía visual ejecutiva y resumen destacado.',
  };
}

class _SettingsCard extends StatelessWidget {
  final Widget child;

  const _SettingsCard({required this.child});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: const Color(0xFFE5EAF0)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: .035),
          blurRadius: 16,
          offset: const Offset(0, 5),
        ),
      ],
    ),
    child: child,
  );
}

class _SectionHeading extends StatelessWidget {
  final String title;
  final String subtitle;

  const _SectionHeading({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 4),
      Text(
        subtitle,
        style: TextStyle(color: Colors.blueGrey.shade600, fontSize: 12),
      ),
    ],
  );
}

class _TemplatePreview extends StatelessWidget {
  final int primary;
  final int accent;
  final String template;

  const _TemplatePreview({
    required this.primary,
    required this.accent,
    required this.template,
  });

  @override
  Widget build(BuildContext context) => Container(
    width: 48,
    height: 58,
    padding: const EdgeInsets.all(6),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: const Color(0xFFD9E0E7)),
      borderRadius: BorderRadius.circular(5),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: template == 'Minimal' ? 3 : 8,
          decoration: BoxDecoration(
            color: Color(primary),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(height: 5),
        Container(height: 3, color: const Color(0xFFE6E9ED)),
        const SizedBox(height: 3),
        Container(height: 3, color: const Color(0xFFE6E9ED)),
        const Spacer(),
        Container(height: 7, color: Color(accent).withValues(alpha: .55)),
      ],
    ),
  );
}
