import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import '../../../../core/utils/app_currency.dart';
import '../../../shop/presentation/bloc/shop_bloc.dart';
import '../../data/quotation_pdf.dart';
import '../../data/quotation_preferences.dart';
import '../../domain/entities/quotation.dart';

class QuotationSettingsPage extends StatefulWidget {
  const QuotationSettingsPage({super.key});

  @override
  State<QuotationSettingsPage> createState() => _QuotationSettingsPageState();
}

class _QuotationSettingsPageState extends State<QuotationSettingsPage> {
  static const _templates = ['Clásica', 'Minimal', 'Profesional'];
  static const _colorPairs = [
    (0xFF2E7D6F, 0xFF00BFA5),
    (0xFF183153, 0xFF43A5D5),
    (0xFF6D3E76, 0xFFD49BD5),
    (0xFF9A4E13, 0xFFFFB74D),
    (0xFF30343B, 0xFF8C9AA8),
  ];

  late bool _enabled;
  late String _template;
  late int _primaryColor;
  late int _accentColor;
  late List<QuotationRecord> _history;
  String? _historyError;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _enabled = QuotationPreferences.enabled;
    _template = QuotationPreferences.template;
    _primaryColor = QuotationPreferences.primaryColor;
    _accentColor = QuotationPreferences.accentColor;
    _loadHistory();
    context.read<ShopBloc>().add(LoadShopEvent());
  }

  void _loadHistory() {
    try {
      _history = QuotationPreferences.history;
      _historyError = null;
    } on FormatException catch (error) {
      _history = const [];
      _historyError = error.message;
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await QuotationPreferences.save(
        enabled: _enabled,
        template: _template,
        primaryColor: _primaryColor,
        accentColor: _accentColor,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Configuración guardada.')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo guardar la configuración: $error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _chooseColor({required bool primary}) async {
    final selected = await showDialog<int>(
      context: context,
      builder: (dialogContext) => _ColorPickerDialog(
        initialColor: primary ? _primaryColor : _accentColor,
      ),
    );
    if (selected == null) return;
    setState(() {
      if (primary) {
        _primaryColor = selected;
      } else {
        _accentColor = selected;
      }
    });
  }

  Future<void> _previewTemplate(String template) async {
    final selected = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: const Color(0xFFF5F7FA),
        insetPadding: const EdgeInsets.all(20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480, maxHeight: 680),
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
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
                const SizedBox(height: 12),
                Flexible(
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: 0.707,
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.08),
                              blurRadius: 22,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: BlocBuilder<ShopBloc, ShopState>(
                          builder: (context, state) => _InvoicePreview(
                            name: template,
                            shopName: state is ShopLoaded
                                ? state.shop.name
                                : '',
                            primaryColor: _primaryColor,
                            accentColor: _accentColor,
                            expanded: true,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
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

  void _selectCombination(int primary, int accent) {
    setState(() {
      _primaryColor = primary;
      _accentColor = accent;
    });
  }

  Future<void> _shareQuotation(QuotationRecord quotation) async {
    try {
      final bytes = await QuotationPdf.build(
        quotation: quotation,
        template: _template,
        primaryColor: _primaryColor,
        accentColor: _accentColor,
      );
      final shared = await Printing.sharePdf(
        bytes: bytes,
        filename: 'cotizacion-${quotation.id}.pdf',
      );
      if (!shared && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo abrir la descarga del PDF.'),
          ),
        );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo generar el PDF: $error')),
      );
    }
  }

  String _hex(int color) =>
      '#${(color & 0x00FFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  String _colorLabel(int primary, int accent) {
    final index = _colorPairs.indexWhere(
      (pair) => pair.$1 == primary && pair.$2 == accent,
    );
    return ['Verde', 'Azul', 'Violeta', 'Ámbar', 'Neutro'][index < 0
        ? 0
        : index];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme.copyWith(
      brightness: Brightness.light,
      primary: Color(_primaryColor),
      onPrimary: Colors.white,
      surface: Colors.white,
      onSurface: const Color(0xFF202938),
      onSurfaceVariant: const Color(0xFF687386),
      outlineVariant: const Color(0xFFE5EAF0),
    );
    final accentIsLight = Color(_accentColor).computeLuminance() > 0.58;
    return Theme(
      data: theme.copyWith(
        colorScheme: colors,
        scaffoldBackgroundColor: const Color(0xFFF5F7FA),
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F7FA),
        appBar: AppBar(
          title: const Text('Cotización'),
          centerTitle: true,
          foregroundColor: const Color(0xFF202938),
          backgroundColor: const Color(0xFFF5F7FA),
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
                      _SurfaceCard(
                        child: SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          value: _enabled,
                          onChanged: (value) =>
                              setState(() => _enabled = value),
                          secondary: Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              color: const Color(0xFFE5F4F0),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(
                              Icons.request_quote_outlined,
                              color: Color(0xFF2E7D6F),
                            ),
                          ),
                          title: const Text(
                            'Usar cotizaciones',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                          subtitle: Text(
                            'En Revisar orden aparece Crear cotización para generar un PDF.',
                            style: TextStyle(color: colors.onSurfaceVariant),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      _SurfaceCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Diseño del PDF',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Elige una presentación para tus documentos.',
                              style: TextStyle(color: colors.onSurfaceVariant),
                            ),
                            const SizedBox(height: 18),
                            SizedBox(
                              height: 154,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: _templates.length,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(width: 14),
                                itemBuilder: (context, index) {
                                  final template = _templates[index];
                                  return _TemplateOption(
                                    name: template,
                                    selected: _template == template,
                                    primaryColor: _primaryColor,
                                    accentColor: _accentColor,
                                    onTap: () =>
                                        setState(() => _template = template),
                                    onPreview: () => _previewTemplate(template),
                                  );
                                },
                              ),
                            ),
                            const Divider(height: 30),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Colores',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        'Personaliza la identidad del PDF.',
                                        style: TextStyle(
                                          color: colors.onSurfaceVariant,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                CircleAvatar(
                                  radius: 11,
                                  backgroundColor: Color(_primaryColor),
                                ),
                                const SizedBox(width: 7),
                                CircleAvatar(
                                  radius: 11,
                                  backgroundColor: Color(_accentColor),
                                ),
                                const SizedBox(width: 6),
                                Icon(
                                  Icons.expand_more_rounded,
                                  color: colors.onSurfaceVariant,
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            LayoutBuilder(
                              builder: (context, constraints) {
                                final width = (constraints.maxWidth - 12) / 2;
                                return Wrap(
                                  spacing: 12,
                                  runSpacing: 12,
                                  children: [
                                    _PdfColorCard(
                                      width: width,
                                      title: 'Principal',
                                      color: _primaryColor,
                                      hex: _hex(_primaryColor),
                                      onTap: () => _chooseColor(primary: true),
                                    ),
                                    _PdfColorCard(
                                      width: width,
                                      title: 'Acento',
                                      color: _accentColor,
                                      hex: _hex(_accentColor),
                                      onTap: () => _chooseColor(primary: false),
                                    ),
                                  ],
                                );
                              },
                            ),
                            if (accentIsLight) ...[
                              const SizedBox(height: 12),
                              _AccentWarning(
                                onDarken: () =>
                                    setState(() => _accentColor = 0xFF008F7A),
                              ),
                            ],
                            const SizedBox(height: 18),
                            Text(
                              'Combinaciones',
                              style: TextStyle(
                                color: colors.onSurfaceVariant,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: [
                                for (final (primary, accent) in _colorPairs)
                                  _ColorCombination(
                                    primary: primary,
                                    accent: accent,
                                    label: _colorLabel(primary, accent),
                                    selected:
                                        primary == _primaryColor &&
                                        accent == _accentColor,
                                    onTap: () =>
                                        _selectCombination(primary, accent),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Historial',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (_historyError != null)
                        _SurfaceCard(
                          child: Text(
                            'No se pudo leer el historial: $_historyError',
                            style: TextStyle(color: colors.error),
                          ),
                        )
                      else if (_history.isEmpty)
                        _SurfaceCard(
                          child: SizedBox(
                            height: 150,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.description_outlined,
                                  size: 38,
                                  color: colors.onSurfaceVariant.withValues(
                                    alpha: 0.55,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  'Aún no hay cotizaciones',
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
                        for (final quotation in _history)
                          _QuotationHistoryTile(
                            quotation: quotation,
                            onTap: () => _shareQuotation(quotation),
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
                        color: Colors.black.withValues(alpha: 0.07),
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
                          backgroundColor: const Color(0xFF2E7D6F),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        icon: _saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.save_outlined),
                        label: const Text(
                          'Guardar',
                          style: TextStyle(fontWeight: FontWeight.w800),
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

class _SurfaceCard extends StatelessWidget {
  final Widget child;

  const _SurfaceCard({required this.child});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: const Color(0xFFE9EDF2)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.035),
          blurRadius: 14,
          offset: const Offset(0, 4),
        ),
      ],
    ),
    child: child,
  );
}

class _TemplateOption extends StatelessWidget {
  final String name;
  final bool selected;
  final int primaryColor;
  final int accentColor;
  final VoidCallback onTap;
  final VoidCallback onPreview;

  const _TemplateOption({
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 124,
        child: Column(
          children: [
            SizedBox(
              height: 116,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: selected ? primary : const Color(0xFFDCE2EA),
                          width: selected ? 2.5 : 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(
                              0xFF172B4D,
                            ).withValues(alpha: 0.06),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: BlocBuilder<ShopBloc, ShopState>(
                        builder: (context, state) => _InvoicePreview(
                          name: name,
                          shopName: state is ShopLoaded ? state.shop.name : '',
                          primaryColor: primaryColor,
                          accentColor: accentColor,
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
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InvoicePreview extends StatelessWidget {
  final String name;
  final String shopName;
  final int primaryColor;
  final int accentColor;
  final bool expanded;

  const _InvoicePreview({
    required this.name,
    required this.shopName,
    required this.primaryColor,
    required this.accentColor,
    this.expanded = false,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Color(primaryColor);
    final accent = Color(accentColor);
    final displayShopName = shopName.trim().isEmpty
        ? 'MI TIENDA'
        : shopName.trim().toUpperCase();
    final minimal = name == 'Minimal';
    final professional = name == 'Profesional';
    final scale = expanded ? 1.0 : 0.56;
    final textColor = const Color(0xFF263247);
    final muted = const Color(0xFF7C8797);
    final line = const Color(0xFFE5E9EF);
    final baseFont = expanded ? 1.0 : 0.72;

    TextStyle style({
      required double size,
      Color? color,
      FontWeight weight = FontWeight.w500,
    }) => TextStyle(
      color: color ?? textColor,
      fontSize: size * baseFont,
      fontWeight: weight,
    );

    Widget detailRow(String product, String quantity, String amount) => Padding(
      padding: EdgeInsets.symmetric(vertical: 7 * scale),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: Text(
              product,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style(size: 10),
            ),
          ),
          Expanded(
            flex: 1,
            child: Text(
              quantity,
              textAlign: TextAlign.center,
              style: style(size: 9, color: muted),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              amount,
              textAlign: TextAlign.right,
              style: style(size: 9, weight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );

    return ClipRect(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (professional)
            Container(
              padding: EdgeInsets.all(10 * scale),
              decoration: BoxDecoration(
                color: primary,
                borderRadius: BorderRadius.circular(6 * scale),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayShopName,
                          style: style(
                            size: 12,
                            color: Colors.white,
                            weight: FontWeight.w900,
                          ),
                        ),
                        SizedBox(height: 3 * scale),
                        Text(
                          'PROPUESTA COMERCIAL',
                          style: style(
                            size: 7,
                            color: Colors.white.withValues(alpha: 0.78),
                            weight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: EdgeInsets.all(6 * scale),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(5 * scale),
                    ),
                    child: Text(
                      'COTIZACIÓN\nN.º 001',
                      textAlign: TextAlign.right,
                      style: style(
                        size: 7,
                        color: Colors.white,
                        weight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else ...[
            if (!minimal)
              Container(
                height: 5 * scale,
                decoration: BoxDecoration(
                  color: primary,
                  borderRadius: BorderRadius.circular(4 * scale),
                ),
              )
            else
              Container(height: 2 * scale, color: accent),
            SizedBox(height: 8 * scale),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayShopName,
                        style: style(
                          size: 12,
                          color: primary,
                          weight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(height: 3 * scale),
                      Text(
                        'COTIZACIÓN',
                        style: style(
                          size: 8,
                          color: accent,
                          weight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  'N.º 001 · 31/10/2026',
                  textAlign: TextAlign.right,
                  style: style(size: 7, color: muted),
                ),
              ],
            ),
          ],
          SizedBox(height: 14 * scale),
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(9 * scale),
            decoration: BoxDecoration(
              color: minimal ? Colors.transparent : const Color(0xFFF5F7FA),
              borderRadius: BorderRadius.circular(5 * scale),
              border: minimal ? Border.all(color: line) : null,
            ),
            child: Row(
              children: [
                Icon(
                  Icons.person_outline_rounded,
                  size: 13 * scale,
                  color: primary,
                ),
                SizedBox(width: 6 * scale),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('PREPARADO PARA', style: style(size: 6, color: muted)),
                      SizedBox(height: 2 * scale),
                      Text(
                        'José Núñez',
                        style: style(size: 9, weight: FontWeight.w800),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 12 * scale),
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: 5 * scale,
              vertical: 6 * scale,
            ),
            decoration: BoxDecoration(
              color: minimal ? Colors.transparent : accent,
              borderRadius: BorderRadius.circular(3 * scale),
              border: minimal ? Border(bottom: BorderSide(color: line)) : null,
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 5,
                  child: Text(
                    'PRODUCTO',
                    style: style(
                      size: 7,
                      color: minimal ? primary : Colors.white,
                      weight: FontWeight.w800,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    'CANT.',
                    textAlign: TextAlign.center,
                    style: style(
                      size: 6,
                      color: minimal ? muted : Colors.white,
                      weight: FontWeight.w800,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'IMPORTE',
                    textAlign: TextAlign.right,
                    style: style(
                      size: 6,
                      color: minimal ? muted : Colors.white,
                      weight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
          detailRow('Café molido', '2', '\$25.00'),
          Divider(height: 1, color: line),
          detailRow('Té verde', '1', '\$35.00'),
          Divider(height: 1, color: line),
          SizedBox(height: 10 * scale),
          Align(
            alignment: Alignment.centerRight,
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: 12 * scale,
                vertical: 8 * scale,
              ),
              decoration: BoxDecoration(
                color: minimal ? Colors.transparent : primary,
                borderRadius: BorderRadius.circular(5 * scale),
                border: minimal ? Border(top: BorderSide(color: accent)) : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'TOTAL',
                    style: style(
                      size: 8,
                      color: minimal ? muted : Colors.white,
                      weight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(width: 18 * scale),
                  Text(
                    '\$60.00',
                    style: style(
                      size: 12,
                      color: minimal ? primary : Colors.white,
                      weight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),
          Divider(color: line),
          Text(
            'Documento de cotización · No representa una factura',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style(size: 6, color: muted),
          ),
        ],
      ),
    );
  }
}

class _PdfColorCard extends StatelessWidget {
  final double width;
  final String title;
  final int color;
  final String hex;
  final VoidCallback onTap;

  const _PdfColorCard({
    required this.width,
    required this.title,
    required this.color,
    required this.hex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: width,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE7EBF0)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF172B4D).withValues(alpha: 0.045),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              height: 62,
              width: double.infinity,
              color: Color(color),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.centerLeft,
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
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: Color(0xFF202938),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.edit_outlined,
                    color: Color(0xFF697587),
                    size: 18,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _AccentWarning extends StatelessWidget {
  final VoidCallback onDarken;

  const _AccentWarning({required this.onDarken});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF8E1),
      border: Border.all(color: const Color(0xFFEADCA8)),
      borderRadius: BorderRadius.circular(13),
    ),
    child: Row(
      children: [
        const CircleAvatar(
          radius: 15,
          backgroundColor: Color(0xFFFFE7A8),
          child: Icon(
            Icons.info_outline_rounded,
            size: 18,
            color: Color(0xFF795548),
          ),
        ),
        const SizedBox(width: 10),
        const Expanded(
          child: Text(
            'El acento es muy claro y puede tener poco contraste.',
            style: TextStyle(fontSize: 12, color: Color(0xFF5D5140)),
          ),
        ),
        TextButton(onPressed: onDarken, child: const Text('Oscurecer')),
      ],
    ),
  );
}

class _ColorCombination extends StatelessWidget {
  final int primary;
  final int accent;
  final bool selected;
  final String label;
  final VoidCallback onTap;

  const _ColorCombination({
    required this.primary,
    required this.accent,
    required this.selected,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(20),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        border: Border.all(
          color: selected
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.outlineVariant,
          width: selected ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 32,
            height: 18,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
            ),
            child: Row(
              children: [
                Expanded(child: ColoredBox(color: Color(primary))),
                Expanded(child: ColoredBox(color: Color(accent))),
              ],
            ),
          ),
          const SizedBox(width: 7),
          Text(
            label,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    ),
  );
}

class _QuotationHistoryTile extends StatelessWidget {
  final QuotationRecord quotation;
  final VoidCallback onTap;

  const _QuotationHistoryTile({required this.quotation, required this.onTap});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: _SurfaceCard(
      child: Row(
        children: [
          const Icon(
            Icons.picture_as_pdf_outlined,
            color: Color(0xFF2E7D6F),
            size: 28,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  quotation.customerName.isEmpty
                      ? 'Cotización ${quotation.id}'
                      : quotation.customerName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 3),
                Text(
                  '${DateFormat('dd/MM/yyyy HH:mm').format(quotation.createdAt)} · '
                  '${quotation.lines.length} productos · '
                  '${AppCurrency.format(quotation.total, code: quotation.currencyCode)} · '
                  '${AppCurrency.formatReference(quotation.totalInUsd)} · '
                  '1 USD = ${quotation.exchangeRate} ${quotation.currencyCode}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Descargar PDF',
            onPressed: onTap,
            icon: const Icon(Icons.download_outlined),
          ),
        ],
      ),
    ),
  );
}

class _ColorPickerDialog extends StatefulWidget {
  final int initialColor;

  const _ColorPickerDialog({required this.initialColor});

  @override
  State<_ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<_ColorPickerDialog> {
  static const _palette = [
    0xFF2E7D6F,
    0xFF00BFA5,
    0xFF008F7A,
    0xFF183153,
    0xFF43A5D5,
    0xFF6D3E76,
    0xFFD49BD5,
    0xFF9A4E13,
    0xFFFFB74D,
    0xFF30343B,
    0xFF8C9AA8,
    0xFFC62828,
  ];
  late int _selected;
  late final TextEditingController _hexController;
  String? _validationError;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialColor;
    _hexController = TextEditingController(
      text: '#${(_selected & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}',
    );
  }

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  void _setColor(int color) {
    setState(() {
      _selected = color;
      _hexController.text =
          '#${(color & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
      _validationError = null;
    });
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
                  onTap: () => _setColor(color),
                  borderRadius: BorderRadius.circular(22),
                  child: CircleAvatar(
                    backgroundColor: Color(color),
                    child: _selected == color
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
