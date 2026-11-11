import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/data/hive_database.dart';
import '../../data/exchange_rates_service.dart';

const _rateStorageKey = 'multi_rate_calculator_rates';

const _rateSources = [
  _RateSource('BCV', 'USD'),
  _RateSource('Paralelo', 'USD'),
  _RateSource('USDT', 'USDT', automaticAvailable: false),
  _RateSource('Euro', 'EUR'),
];

Future<void> showMultiRateCalculator(BuildContext context) async {
  final isWide = MediaQuery.sizeOf(context).width >= 700;
  if (isWide) {
    await showDialog<void>(
      context: context,
      builder: (context) => const Dialog(
        insetPadding: EdgeInsets.all(24),
        child: SizedBox(width: 520, child: MultiRateCalculator()),
      ),
    );
    return;
  }
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => const SafeArea(
      top: false,
      child: FractionallySizedBox(
        heightFactor: .92,
        child: MultiRateCalculator(),
      ),
    ),
  );
}

class MultiRateCalculator extends StatefulWidget {
  const MultiRateCalculator({super.key});

  @override
  State<MultiRateCalculator> createState() => _MultiRateCalculatorState();
}

class _MultiRateCalculatorState extends State<MultiRateCalculator> {
  final _ratesService = ExchangeRatesService();
  int _selectedRate = 0;
  String _display = '0';
  double? _storedOperand;
  String? _pendingOperator;
  bool _startNewNumber = false;
  bool _isRefreshingRates = false;
  String? _rateError;
  late Map<String, _SavedRate> _rates;

  @override
  void initState() {
    super.initState();
    _rates = _readRates();
    _refreshRates(showMessage: false);
  }

  @override
  void dispose() {
    _ratesService.close();
    super.dispose();
  }

  _RateSource get _source => _rateSources[_selectedRate];
  _SavedRate? get _savedRate => _rates[_source.name];
  double get _amount => double.tryParse(_display.replaceAll(',', '.')) ?? 0;

  Future<void> _refreshRates({bool showMessage = true}) async {
    if (_isRefreshingRates) return;
    setState(() {
      _isRefreshingRates = true;
      _rateError = null;
    });
    try {
      final liveRates = await _ratesService.fetchRates();
      final updated = Map<String, _SavedRate>.from(_rates);
      var updatedCount = 0;
      for (final entry in liveRates.entries) {
        if (updated[entry.key]?.isManual == true) continue;
        updated[entry.key] = _SavedRate(
          entry.value.vesPerUnit,
          entry.value.updatedAt,
          isManual: false,
        );
        updatedCount++;
      }
      await HiveDatabase.settingsBox.put(_rateStorageKey, {
        for (final entry in updated.entries) entry.key: entry.value.toMap(),
      });
      if (!mounted) return;
      setState(() {
        _rates = updated;
        _rateError = null;
      });
      if (showMessage) {
        final message = updatedCount == 0
            ? 'Las tasas actuales están fijadas manualmente.'
            : 'Tasas oficiales actualizadas desde DolarApi.';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _rateError =
            'No se pudieron consultar las tasas en línea. Se conservan las tasas guardadas.',
      );
      if (showMessage) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al actualizar tasas: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _isRefreshingRates = false);
    }
  }

  Future<void> _useAutomaticRate() async {
    final source = _source.name;
    setState(() {
      _isRefreshingRates = true;
      _rateError = null;
    });
    try {
      final liveRate = (await _ratesService.fetchRates())[source];
      if (liveRate == null) {
        throw StateError('No hay una tasa automática para $source.');
      }
      final updated = Map<String, _SavedRate>.from(_rates)
        ..[source] = _SavedRate(
          liveRate.vesPerUnit,
          liveRate.updatedAt,
          isManual: false,
        );
      await HiveDatabase.settingsBox.put(_rateStorageKey, {
        for (final entry in updated.entries) entry.key: entry.value.toMap(),
      });
      if (!mounted) return;
      setState(() => _rates = updated);
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _rateError =
            'No se pudo restaurar la tasa automática. Inténtalo nuevamente.',
      );
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error al consultar la tasa: $error')));
    } finally {
      if (mounted) setState(() => _isRefreshingRates = false);
    }
  }

  Map<String, _SavedRate> _readRates() {
    final stored = HiveDatabase.settingsBox.get(_rateStorageKey);
    if (stored is! Map) return {};
    return {
      for (final entry in stored.entries)
        if (entry.key is String && entry.value is Map)
          entry.key as String: _SavedRate.fromMap(entry.value as Map),
    };
  }

  void _append(String key) {
    setState(() {
      if (key == 'clear') {
        _display = '0';
        _storedOperand = null;
        _pendingOperator = null;
        _startNewNumber = false;
        return;
      }
      if (key == 'delete') {
        _display = _display.length > 1
            ? _display.substring(0, _display.length - 1)
            : '0';
        if (_display == '-') _display = '0';
        return;
      }
      if (key == '.') {
        if (_startNewNumber) {
          _display = '0.';
          _startNewNumber = false;
        } else if (!_display.contains('.')) {
          _display += '.';
        }
        return;
      }
      if (key == 'sign') {
        if (_amount != 0) {
          _display = _formatNumber(-_amount);
        }
        return;
      }
      if (key == 'percent') {
        _display = _formatNumber(_amount * 1.16);
        _startNewNumber = true;
        return;
      }
      if (_startNewNumber || _display == '0') {
        _display = key;
        _startNewNumber = false;
      } else {
        _display += key;
      }
    });
  }

  void _chooseOperator(String operator) {
    setState(() {
      if (_storedOperand != null &&
          _pendingOperator != null &&
          !_startNewNumber) {
        _calculate();
      }
      _storedOperand = _amount;
      _pendingOperator = operator;
      _startNewNumber = true;
    });
  }

  void _calculate() {
    final first = _storedOperand;
    final operator = _pendingOperator;
    if (first == null || operator == null) return;
    final second = _amount;
    final result = switch (operator) {
      '+' => first + second,
      '−' => first - second,
      '×' => first * second,
      '÷' => second == 0 ? null : first / second,
      _ => null,
    };
    if (result == null || !result.isFinite) {
      _display = '0';
    } else {
      _display = _formatNumber(result);
    }
    _storedOperand = null;
    _pendingOperator = null;
    _startNewNumber = true;
  }

  String _formatNumber(double value) {
    if (!value.isFinite) return '0';
    var formatted = value.toStringAsFixed(8);
    if (formatted.contains('.')) {
      formatted = formatted.replaceFirst(RegExp(r'0+$'), '');
      formatted = formatted.replaceFirst(RegExp(r'\.$'), '');
    }
    return formatted == '-0' || formatted.isEmpty ? '0' : formatted;
  }

  Future<void> _editRate() async {
    final controller = TextEditingController(
      text: _savedRate?.value.toString() ?? '',
    );
    final rate = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Tasa ${_source.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Indica cuántos bolívares equivalen a 1 ${_source.unit}.',
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'VES por unidad',
                prefixIcon: Icon(Icons.currency_exchange_rounded),
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final value = double.tryParse(
                controller.text.trim().replaceAll(',', '.'),
              );
              if (value == null || !value.isFinite || value <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('La tasa debe ser un valor mayor que cero.'),
                  ),
                );
                return;
              }
              Navigator.pop(context, value);
            },
            child: const Text('Guardar tasa'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (rate == null || !mounted) return;
    final updated = Map<String, _SavedRate>.from(_rates)
      ..[_source.name] = _SavedRate(rate, DateTime.now(), isManual: true);
    await HiveDatabase.settingsBox.put(_rateStorageKey, {
      for (final entry in updated.entries)
        entry.key: entry.value.toMap(),
    });
    if (!mounted) return;
    setState(() => _rates = updated);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final equivalent = _savedRate == null
        ? null
        : _amount * _savedRate!.value;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFDCE3E9),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAF2FF),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: const Icon(
                      Icons.calculate_rounded,
                      color: Color(0xFF2768D7),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Calculadora Multi-Tasa',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Actualizar tasas en línea',
                    onPressed: _isRefreshingRates
                        ? null
                        : () => _refreshRates(),
                    icon: _isRefreshingRates
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.sync_rounded),
                  ),
                  IconButton(
                    tooltip: 'Cerrar',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  for (var index = 0; index < _rateSources.length; index++)
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(
                          right: index == _rateSources.length - 1 ? 0 : 7,
                        ),
                        child: _RatePill(
                          source: _rateSources[index],
                          selected: _selectedRate == index,
                          configured: _rates.containsKey(
                            _rateSources[index].name,
                          ),
                          onTap: () => setState(() => _selectedRate = index),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (_rateError != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF4E5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _rateError!,
                    style: const TextStyle(
                      color: Color(0xFF8A4B08),
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 13, 16, 14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F5F8),
                  borderRadius: BorderRadius.circular(17),
                ),
                child: Column(
                  children: [
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        '${_source.unit} ${NumberFormat('#,##0.########', 'es').format(_amount)}',
                        style: const TextStyle(
                          color: Color(0xFF596779),
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'EQUIVALENTE (${_source.name.toUpperCase()})',
                                style: const TextStyle(
                                  color: Color(0xFF788596),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: .5,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _savedRate == null
                                    ? 'Configura la tasa para calcular'
                                    : '1 ${_source.unit} = ${_savedRate!.value.toString()} VES',
                                style: const TextStyle(
                                  color: Color(0xFF596779),
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          equivalent == null
                              ? '—'
                              : 'Bs. ${NumberFormat('#,##0.00', 'es').format(equivalent)}',
                          textAlign: TextAlign.end,
                          style: TextStyle(
                            color: colors.primary,
                            fontSize: 21,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _savedRate == null
                                ? _source.automaticAvailable
                                      ? 'Esperando tasa en línea'
                                      : 'Sin fuente automática verificada'
                                : '${_savedRate!.isManual ? 'Manual' : 'DolarApi'} · ${DateFormat('dd/MM/yy HH:mm', 'es').format(_savedRate!.updatedAt)}',
                            style: const TextStyle(
                              color: Color(0xFF7C8795),
                              fontSize: 10,
                            ),
                          ),
                        ),
                        Wrap(
                          spacing: 4,
                          children: [
                            if (_savedRate?.isManual == true &&
                                _source.automaticAvailable)
                              TextButton(
                                onPressed: _isRefreshingRates
                                    ? null
                                    : _useAutomaticRate,
                                child: const Text(
                                  'Automática',
                                  style: TextStyle(fontSize: 11),
                                ),
                              ),
                            TextButton.icon(
                              onPressed: _editRate,
                              icon: const Icon(Icons.edit_outlined, size: 15),
                              label: Text(
                                _savedRate == null ? 'Definir' : 'Editar',
                                style: const TextStyle(fontSize: 11),
                              ),
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    if (!_source.automaticAvailable) ...[
                      const SizedBox(height: 4),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'USDT requiere una tasa manual; no se usa el dólar como sustituto.',
                          style: TextStyle(
                            color: Color(0xFF7C8795),
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: GridView.count(
                  crossAxisCount: 4,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 1.56,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    _CalcKey(
                      label: 'C',
                      background: const Color(0xFFFFEDF0),
                      foreground: const Color(0xFFE24B68),
                      onTap: () => _append('clear'),
                    ),
                    _CalcKey(
                      icon: Icons.backspace_outlined,
                      onTap: () => _append('delete'),
                    ),
                    _CalcKey(
                      label: '+16%',
                      foreground: const Color(0xFF2768D7),
                      onTap: () => _append('percent'),
                    ),
                    _CalcKey(
                      label: '÷',
                      emphasized: true,
                      onTap: () => _chooseOperator('÷'),
                    ),
                    for (final key in [
                      '7',
                      '8',
                      '9',
                      '×',
                      '4',
                      '5',
                      '6',
                      '−',
                      '1',
                      '2',
                      '3',
                      '+',
                    ])
                      _CalcKey(
                        label: key,
                        emphasized: const {'×', '−', '+'}.contains(key),
                        onTap: const {'×', '−', '+'}.contains(key)
                            ? () => _chooseOperator(key)
                            : () => _append(key),
                      ),
                    _CalcKey(
                      label: '±',
                      foreground: const Color(0xFF596779),
                      onTap: () => _append('sign'),
                    ),
                    _CalcKey(label: '0', onTap: () => _append('0')),
                    _CalcKey(label: '.', onTap: () => _append('.')),
                    _CalcKey(
                      label: '=',
                      background: colors.primary,
                      foreground: colors.onPrimary,
                      onTap: () => setState(_calculate),
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
}

class _RateSource {
  final String name;
  final String unit;
  final bool automaticAvailable;

  const _RateSource(
    this.name,
    this.unit, {
    this.automaticAvailable = true,
  });
}

class _SavedRate {
  final double value;
  final DateTime updatedAt;
  final bool isManual;

  const _SavedRate(this.value, this.updatedAt, {required this.isManual});

  Map<String, Object> toMap() => {
    'value': value,
    'updatedAt': updatedAt.toIso8601String(),
    'isManual': isManual,
  };

  factory _SavedRate.fromMap(Map map) {
    final value = map['value'];
    final updatedAt = DateTime.tryParse(map['updatedAt']?.toString() ?? '');
    if (value is! num ||
        !value.toDouble().isFinite ||
        value <= 0 ||
        updatedAt == null) {
      throw const FormatException('La tasa guardada no es válida.');
    }
    return _SavedRate(
      value.toDouble(),
      updatedAt,
      isManual: map['isManual'] as bool? ?? true,
    );
  }
}

class _RatePill extends StatelessWidget {
  final _RateSource source;
  final bool selected;
  final bool configured;
  final VoidCallback onTap;

  const _RatePill({
    required this.source,
    required this.selected,
    required this.configured,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: selected ? Colors.white : const Color(0xFFEFF2F6),
    borderRadius: BorderRadius.circular(14),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? const Color(0xFF2768D7) : Colors.transparent,
            width: 1.2,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: .07),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Column(
          children: [
            Text(
              source.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected
                    ? const Color(0xFF2768D7)
                    : const Color(0xFF596779),
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 3),
            Icon(
              configured ? Icons.check_circle : Icons.circle_outlined,
              size: 10,
              color: configured
                  ? const Color(0xFF2D9B6F)
                  : const Color(0xFFA8B1BC),
            ),
          ],
        ),
      ),
    ),
  );
}

class _CalcKey extends StatelessWidget {
  final String? label;
  final IconData? icon;
  final Color? background;
  final Color? foreground;
  final bool emphasized;
  final VoidCallback onTap;

  const _CalcKey({
    this.label,
    this.icon,
    this.background,
    this.foreground,
    this.emphasized = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Material(
    color:
        background ??
        (emphasized ? const Color(0xFFEAF1FC) : Colors.white),
    borderRadius: BorderRadius.circular(14),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: emphasized
                ? const Color(0xFFD5E2F8)
                : const Color(0xFFE4E9EF),
          ),
        ),
        alignment: Alignment.center,
        child: icon != null
            ? Icon(icon, color: foreground ?? const Color(0xFF293647), size: 20)
            : Text(
                label!,
                style: TextStyle(
                  color: foreground ?? const Color(0xFF222D3A),
                  fontSize: label == '+16%' ? 13 : 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
      ),
    ),
  );
}
