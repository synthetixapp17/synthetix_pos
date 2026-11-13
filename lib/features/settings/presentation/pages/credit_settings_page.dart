import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';

import '../../../credit/data/credit_preferences.dart';
import '../../../credit/data/credit_pdf.dart';
import '../../../credit/data/credit_repository.dart';
import '../../../credit/domain/entities/credit_record.dart';

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
    (0xFF56345F, 0xFFB278B5, 'Violeta'),
    (0xFF7A3E12, 0xFFE68A32, 'Ámbar'),
    (0xFF30343B, 0xFF8C9AA8, 'Neutro'),
    (0xFF8B2635, 0xFFD65A6D, 'Rojo'),
    (0xFF00695C, 0xFF26A69A, 'Turquesa'),
    (0xFF4E5D2A, 0xFF9EAD45, 'Oliva'),
  ];

  late bool _enabled;
  late String _template;
  late int _primaryColor;
  late int _accentColor;
  late final TextEditingController _termsController;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _enabled = CreditPreferences.enabled;
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

  Future<void> _previewTemplate(String template) async {
    final selected = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Theme.of(dialogContext).colorScheme.surface,
        insetPadding: const EdgeInsets.all(20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480, maxHeight: 700),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Vista previa · $template',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Cerrar vista previa',
                      onPressed: () => Navigator.pop(dialogContext),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: PdfPreview(
                      build: (_) => buildCreditContractPdf({
                        'empresa': {
                          'nombre': 'COMERCIAL EJEMPLO',
                          'direccion': 'Av. Principal, local 12',
                          'telefono': '+58 412-555-0182',
                          'rif': 'J-12345678-9',
                        },
                        'cliente': {
                          'nombre': 'María Fernanda Pérez',
                          'cedulaRif': 'V-18.456.789',
                          'telefono': '+58 414-555-0134',
                          'correo': 'maria.perez@ejemplo.com',
                          'direccion': 'Urb. Las Flores, Valencia',
                        },
                        'productos': [
                          {
                            'cantidad': 1,
                            'descripcion': 'Equipo de oficina',
                            'precioUnitario': 1850.0,
                          },
                          {
                            'cantidad': 2,
                            'descripcion': 'Accesorios y suministros',
                            'precioUnitario': 300.0,
                          },
                        ],
                        'totalVenta': 2450.0,
                        'abonoInicial': 450.0,
                        'numeroCuotas': 4,
                        'diasPlazo': 30,
                        'porcentajeCredito': 5.0,
                        'fechaEmision': DateTime(2026, 10, 15),
                        'numeroContrato': 'CR-2026-00128',
                        'moneda': 'USD',
                        'representanteNombre': 'Carlos Mendoza',
                        'representanteCargo': 'Gerente de crédito',
                        'condiciones': _termsController.text.trim(),
                        'plantilla': template,
                        'colorPrincipal': _primaryColor,
                        'colorAcento': _accentColor,
                      }),
                      canChangeOrientation: false,
                      canChangePageFormat: false,
                      useActions: false,
                      allowPrinting: false,
                      allowSharing: false,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('Usar esta plantilla'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (selected == true && mounted) {
      setState(() => _template = template);
    }
  }

  Future<void> _chooseColor({required bool primary}) async {
    final selected = await showDialog<int>(
      context: context,
      builder: (dialogContext) => _CreditColorPicker(
        initialColor: primary ? _primaryColor : _accentColor,
      ),
    );
    if (selected == null || !mounted) return;
    setState(() {
      if (primary) {
        _primaryColor = selected;
      } else {
        _accentColor = selected;
      }
    });
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
        enabled: _enabled,
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
    final history = CreditRepository.getAll();
    final colors = theme.colorScheme;
    return Theme(
      data: theme.copyWith(
        colorScheme: colors,
        scaffoldBackgroundColor: theme.scaffoldBackgroundColor,
      ),
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(
          title: const Text('Créditos'),
          centerTitle: true,
          backgroundColor: theme.scaffoldBackgroundColor,
          foregroundColor: colors.onSurface,
          surfaceTintColor: Colors.transparent,
          leading: IconButton(
            tooltip: 'Volver',
            onPressed: () => context.pop(),
            icon: const Icon(Icons.arrow_back_rounded),
          ),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1050),
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
                    children: [
                      _SettingsCard(
                        child: SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          value: _enabled,
                          onChanged: (value) =>
                              setState(() => _enabled = value),
                          secondary: Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              color: colors.primaryContainer,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(
                              Icons.request_quote_outlined,
                              color: colors.primary,
                            ),
                          ),
                          title: const Text(
                            'Usar créditos',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                          subtitle: Text(
                            'En Revisar orden aparece Crear crédito. No descuenta stock.',
                            style: TextStyle(color: colors.onSurfaceVariant),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      _SettingsCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const _SectionHeading(
                              title: 'Diseño del PDF',
                              subtitle:
                                  'Elige una presentación, revisa la miniatura y guarda los cambios para aplicarlos al contrato.',
                            ),
                            const SizedBox(height: 18),
                            SizedBox(
                              height: 154,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: _templates.length,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(width: 14),
                                itemBuilder: (context, index) =>
                                    _ContractTemplateOption(
                                      name: _templates[index],
                                      selected: _template == _templates[index],
                                      primaryColor: _primaryColor,
                                      accentColor: _accentColor,
                                      onTap: () => setState(
                                        () => _template = _templates[index],
                                      ),
                                      onPreview: () =>
                                          _previewTemplate(_templates[index]),
                                    ),
                              ),
                            ),
                            const Divider(height: 30),
                            const _SectionHeading(
                              title: 'Colores',
                              subtitle: 'Se aplican al guardar.',
                            ),
                            const SizedBox(height: 14),
                            LayoutBuilder(
                              builder: (context, constraints) {
                                final width = (constraints.maxWidth - 12) / 2;
                                return Wrap(
                                  spacing: 12,
                                  runSpacing: 12,
                                  children: [
                                    _CreditColorCard(
                                      width: width,
                                      title: 'Principal',
                                      color: _primaryColor,
                                      onTap: () => _chooseColor(primary: true),
                                    ),
                                    _CreditColorCard(
                                      width: width,
                                      title: 'Acento',
                                      color: _accentColor,
                                      onTap: () => _chooseColor(primary: false),
                                    ),
                                  ],
                                );
                              },
                            ),
                            if (Color(_accentColor).computeLuminance() > .58)
                              Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: _CreditAccentWarning(
                                  onDarken: () => setState(
                                    () => _accentColor = _darken(_accentColor),
                                  ),
                                ),
                              ),
                            const SizedBox(height: 18),
                            Text(
                              'Combinaciones',
                              style: TextStyle(
                                color: colors.onSurface,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 10),
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  for (
                                    var index = 0;
                                    index < _palettes.length;
                                    index++
                                  ) ...[
                                    if (index > 0) const SizedBox(width: 8),
                                    _CreditColorCombination(
                                      primary: _palettes[index].$1,
                                      accent: _palettes[index].$2,
                                      selected:
                                          _palettes[index].$1 ==
                                              _primaryColor &&
                                          _palettes[index].$2 == _accentColor,
                                      label: _palettes[index].$3,
                                      onTap: () => setState(() {
                                        _primaryColor = _palettes[index].$1;
                                        _accentColor = _palettes[index].$2;
                                      }),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      _SettingsCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const _SectionHeading(
                              title: 'Cláusula del contrato',
                              subtitle:
                                  'Este texto aparecerá al final del PDF de crédito.',
                            ),
                            const SizedBox(height: 14),
                            TextField(
                              controller: _termsController,
                              minLines: 4,
                              maxLines: 8,
                              textCapitalization: TextCapitalization.sentences,
                              decoration: InputDecoration(
                                hintText:
                                    'Ej: El cliente se compromete a pagar la totalidad del crédito en un plazo de 30 días...',
                                alignLabelWithHint: true,
                                filled: true,
                                fillColor: colors.surface,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: const BorderSide(
                                    color: Color(0xFFE2E7ED),
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: const BorderSide(
                                    color: Color(0xFFE2E7ED),
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide(
                                    color: Color(_primaryColor),
                                    width: 1.5,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        'Historial',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (history.isEmpty)
                        _SettingsCard(
                          child: SizedBox(
                            height: 124,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.description_outlined,
                                  size: 36,
                                  color: colors.onSurfaceVariant.withValues(
                                    alpha: .65,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  'Aún no hay créditos. Crea uno desde Revisar orden.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: colors.onSurfaceVariant,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      else
                        ...history.map(
                          (credit) => _CreditHistoryTile(
                            credit: credit,
                            onTap: () =>
                                context.push('/settings/credits/${credit.id}'),
                          ),
                        ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: .07),
                        blurRadius: 16,
                        offset: const Offset(0, -4),
                      ),
                    ],
                  ),
                  child: SafeArea(
                    top: false,
                    child: SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton.icon(
                        onPressed: _saving ? null : _save,
                        style: FilledButton.styleFrom(
                          backgroundColor: colors.primary,
                          foregroundColor: colors.onPrimary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        icon: _saving
                            ? SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: colors.onPrimary,
                                ),
                              )
                            : const Icon(Icons.save_outlined),
                        label: Text(
                          _saving
                              ? 'Guardando...'
                              : 'Guardar diseño y contrato',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final Widget child;

  const _SettingsCard({required this.child});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: colors.shadow.withValues(alpha: .08),
            blurRadius: 16,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: child,
    );
  }
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
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontSize: 12,
        ),
      ),
    ],
  );
}

class _ContractTemplateOption extends StatelessWidget {
  final String name;
  final bool selected;
  final int primaryColor;
  final int accentColor;
  final VoidCallback onTap;
  final VoidCallback onPreview;

  const _ContractTemplateOption({
    required this.name,
    required this.selected,
    required this.primaryColor,
    required this.accentColor,
    required this.onTap,
    required this.onPreview,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Color(primaryColor);
    return SizedBox(
      width: 124,
      child: Column(
        children: [
          SizedBox(
            height: 116,
            child: Stack(
              children: [
                Positioned.fill(
                  child: Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      onTap: onTap,
                      onLongPress: onPreview,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.all(9),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: selected ? primary : const Color(0xFFDCE2EA),
                            width: selected ? 2.5 : 1,
                          ),
                        ),
                        child: _MiniContractSheet(
                          template: name,
                          primaryColor: primaryColor,
                          accentColor: accentColor,
                        ),
                      ),
                    ),
                  ),
                ),
                if (selected)
                  Positioned(
                    top: 5,
                    left: 5,
                    child: CircleAvatar(
                      radius: 10,
                      backgroundColor: primary,
                      child: const Icon(
                        Icons.check,
                        size: 13,
                        color: Colors.white,
                      ),
                    ),
                  ),
                Positioned(
                  right: 3,
                  bottom: 3,
                  child: Material(
                    color: Colors.white,
                    shape: const CircleBorder(),
                    elevation: 3,
                    child: IconButton(
                      tooltip: 'Ampliar plantilla $name',
                      onPressed: onPreview,
                      icon: Icon(
                        Icons.open_in_full_rounded,
                        color: primary,
                        size: 15,
                      ),
                      constraints: const BoxConstraints.tightFor(
                        width: 30,
                        height: 30,
                      ),
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 7),
          Text(
            name,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniContractSheet extends StatelessWidget {
  final String template;
  final int primaryColor;
  final int accentColor;

  const _MiniContractSheet({
    required this.template,
    required this.primaryColor,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Color(primaryColor);
    final accent = Color(accentColor);
    final minimal = template == 'Minimal';
    final professional = template == 'Profesional';
    const textColor = Color(0xFF263247);
    const muted = Color(0xFF7C8797);
    const line = Color(0xFFE5E9EF);

    Widget detail(String name, String quantity, String amount) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 4.5, color: textColor),
            ),
          ),
          Expanded(
            child: Text(
              quantity,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 4, color: muted),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              amount,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 4,
                color: textColor,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );

    Widget summary(String label, String value) => Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: muted,
                fontSize: 3,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              value,
              style: TextStyle(
                color: primary,
                fontSize: 4,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (professional)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
            decoration: BoxDecoration(
              color: primary,
              borderRadius: BorderRadius.circular(3),
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'MI NEGOCIO',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        'CONTRATO DE CRÉDITO',
                        style: TextStyle(color: Colors.white70, fontSize: 3.5),
                      ),
                    ],
                  ),
                ),
                Text(
                  'N.º CR-001',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .85),
                    fontSize: 4,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          )
        else ...[
          Container(
            height: minimal ? 2 : 4,
            decoration: BoxDecoration(
              color: minimal ? accent : primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(
                  'CONTRATO DE CRÉDITO',
                  style: TextStyle(
                    color: primary,
                    fontSize: 5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const Text(
                'N.º CR-001',
                style: TextStyle(color: muted, fontSize: 4),
              ),
            ],
          ),
        ],
        const SizedBox(height: 3),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
          decoration: BoxDecoration(
            color: minimal ? Colors.white : const Color(0xFFF3F5F8),
            border: minimal ? Border.all(color: line) : null,
            borderRadius: BorderRadius.circular(2),
          ),
          child: const Row(
            children: [
              Icon(Icons.person_outline_rounded, size: 7, color: muted),
              SizedBox(width: 3),
              Expanded(
                child: Text(
                  'CLIENTE · María Pérez',
                  maxLines: 1,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 4,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 3),
        Row(
          children: [
            summary('ABONO', '\$450'),
            const SizedBox(width: 3),
            summary('CUOTAS', '4 × \$525'),
          ],
        ),
        const SizedBox(height: 3),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
          decoration: BoxDecoration(
            color: minimal ? Colors.white : accent,
            border: minimal ? Border(bottom: BorderSide(color: line)) : null,
            borderRadius: BorderRadius.circular(2),
          ),
          child: Row(
            children: [
              Expanded(
                flex: 5,
                child: Text(
                  'PRODUCTO',
                  style: TextStyle(
                    color: minimal ? primary : Colors.white,
                    fontSize: 3.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  'CANT.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: minimal ? muted : Colors.white,
                    fontSize: 3.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  'IMPORTE',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: minimal ? muted : Colors.white,
                    fontSize: 3.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
        detail('Equipo de oficina', '1', '\$1,850'),
        Divider(height: 1, color: line),
        detail('Accesorios', '2', '\$600'),
        const SizedBox(height: 2),
        Align(
          alignment: Alignment.centerRight,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
              color: minimal ? Colors.white : primary,
              border: minimal ? Border(top: BorderSide(color: accent)) : null,
              borderRadius: BorderRadius.circular(2),
            ),
            child: Text(
              'TOTAL  \$2,450',
              style: TextStyle(
                color: minimal ? primary : Colors.white,
                fontSize: 4.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
        const Spacer(),
        Row(
          children: [
            Expanded(child: Container(height: 1, color: line)),
            const SizedBox(width: 5),
            Expanded(child: Container(height: 1, color: line)),
          ],
        ),
      ],
    );
  }
}

class _CreditColorCard extends StatelessWidget {
  final double width;
  final String title;
  final int color;
  final VoidCallback onTap;

  const _CreditColorCard({
    required this.width,
    required this.title,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final hex =
        '#${(color & 0x00FFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: width,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colors.outlineVariant),
          ),
          child: Column(
            children: [
              Container(
                height: 58,
                width: double.infinity,
                color: Color(color),
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  hex,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          color: colors.onSurface,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const Icon(Icons.edit_outlined, size: 18),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CreditColorPicker extends StatefulWidget {
  final int initialColor;

  const _CreditColorPicker({required this.initialColor});

  @override
  State<_CreditColorPicker> createState() => _CreditColorPickerState();
}

class _CreditColorPickerState extends State<_CreditColorPicker> {
  static const _palette = [
    0xFF174B3B,
    0xFF2E7D6F,
    0xFF183153,
    0xFF43A5D5,
    0xFF56345F,
    0xFFD49BD5,
    0xFF7A3E12,
    0xFFFFB74D,
    0xFF30343B,
    0xFF8C9AA8,
    0xFFC62828,
    0xFF00897B,
  ];

  late final TextEditingController _hexController;
  String? _validationError;

  @override
  void initState() {
    super.initState();
    _hexController = TextEditingController(
      text:
          '#${(widget.initialColor & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}',
    );
  }

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _hexController.text.trim().replaceFirst('#', '');
    if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(value)) {
      setState(() => _validationError = 'Escribe un color HEX válido.');
      return;
    }
    Navigator.pop(context, 0xFF000000 | int.parse(value, radix: 16));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Elegir color'),
    content: SizedBox(
      width: 340,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final color in _palette)
                InkWell(
                  onTap: () {
                    setState(() {
                      _hexController.text =
                          '#${(color & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
                      _validationError = null;
                    });
                  },
                  borderRadius: BorderRadius.circular(22),
                  child: CircleAvatar(
                    backgroundColor: Color(color),
                    child:
                        _hexController.text.toLowerCase() ==
                            '#${(color & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}'
                        ? const Icon(Icons.check, color: Colors.white, size: 18)
                        : null,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _hexController,
            decoration: InputDecoration(
              labelText: 'Color HEX',
              errorText: _validationError,
              prefixIcon: const Icon(Icons.color_lens_outlined),
            ),
            onChanged: (_) => setState(() => _validationError = null),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Aplicar')),
    ],
  );
}

class _CreditAccentWarning extends StatelessWidget {
  final VoidCallback onDarken;

  const _CreditAccentWarning({required this.onDarken});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF3A2D12) : const Color(0xFFFFF8E1),
        border: Border.all(
          color: isDark ? const Color(0xFF6D5521) : const Color(0xFFEADCA8),
        ),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 20,
            color: isDark ? const Color(0xFFFFE0A1) : const Color(0xFF795548),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'El acento es muy claro: los precios se leen mal sobre blanco. En el PDF se oscurece solo para el texto.',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? colors.onSurface : const Color(0xFF5D5140),
              ),
            ),
          ),
          TextButton(onPressed: onDarken, child: const Text('Oscurecer')),
        ],
      ),
    );
  }
}

class _CreditColorCombination extends StatelessWidget {
  final int primary;
  final int accent;
  final bool selected;
  final String label;
  final VoidCallback onTap;

  const _CreditColorCombination({
    required this.primary,
    required this.accent,
    required this.selected,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(14),
    child: Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        border: Border.all(
          color: selected ? Color(primary) : const Color(0xFFE5EAF0),
          width: selected ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 48,
              height: 24,
              child: Row(
                children: [
                  Expanded(child: ColoredBox(color: Color(primary))),
                  Expanded(child: ColoredBox(color: Color(accent))),
                ],
              ),
            ),
          ),
          const SizedBox(height: 3),
          Text(label, style: const TextStyle(fontSize: 9)),
        ],
      ),
    ),
  );
}

class _CreditHistoryTile extends StatelessWidget {
  final CreditRecord credit;
  final VoidCallback onTap;

  const _CreditHistoryTile({required this.credit, required this.onTap});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(
                Icons.description_outlined,
                color: Color(0xFF2E7D6F),
                size: 28,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      credit.customerName.isEmpty
                          ? 'Crédito ${credit.id}'
                          : credit.customerName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${credit.createdAt.day.toString().padLeft(2, '0')}/'
                      '${credit.createdAt.month.toString().padLeft(2, '0')}/'
                      '${credit.createdAt.year} · '
                      '${credit.currencyCode} ${credit.total.toStringAsFixed(2)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    ),
  );
}

int _darken(int color) {
  int channel(int shift) => (((color >> shift) & 0xFF) * .55).round();
  return 0xFF000000 | (channel(16) << 16) | (channel(8) << 8) | channel(0);
}
