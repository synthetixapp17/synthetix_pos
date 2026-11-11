import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/data/hive_database.dart';
import '../../data/exchange_rates_service.dart';

const _rateStorageKey = 'multi_rate_calculator_rates';

const _rateSources = [
  _RateSource('BCV', 'USD'),
  _RateSource('Paralelo', 'USD'),
  _RateSource('USDT', 'USDT', key: 'USDT'),
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
  _SavedRate? get _savedRate => _rates[_source.storageKey];
  double get _amount => double.tryParse(_display.replaceAll(',', '.')) ?? 0;

  Future<void> _refreshRates({bool showMessage = true}) async {
    if (_isRefreshingRates) return;
    setState(() {
      _isRefreshingRates = true;
      _rateError = null;
    });
    try {
      final liveRates = <String, LiveExchangeRate>{};
      final failedSources = <String>[];
      await Future.wait([
        () async {
          try {
            liveRates.addAll(await _ratesService.fetchRates());
          } catch (_) {
            failedSources.add('DolarApi');
          }
        }(),
        () async {
          try {
            liveRates['USDT'] = await _ratesService.fetchBinanceRate();
          } catch (_) {
            failedSources.add('Binance P2P');
          }
        }(),
      ]);
      if (liveRates.isEmpty) {
        throw StateError('No se pudo consultar ninguna fuente de tasas.');
      }
      final updated = Map<String, _SavedRate>.from(_rates);
      var updatedCount = 0;
      for (final entry in liveRates.entries) {
        if (updated[entry.key]?.isManual == true) continue;
        updated[entry.key] = _SavedRate(
          entry.value.vesPerUnit,
          entry.value.updatedAt,
          isManual: false,
          source: entry.value.source,
        );
        updatedCount++;
      }
      await HiveDatabase.settingsBox.put(_rateStorageKey, {
        for (final entry in updated.entries) entry.key: entry.value.toMap(),
      });
      if (!mounted) return;
      setState(() {
        _rates = updated;
        _rateError = failedSources.isEmpty
            ? null
            : 'No se pudo consultar ${failedSources.join(' ni ')}. Se conservan las tasas guardadas para esas fuentes.';
      });
      if (showMessage) {
        final message = failedSources.isNotEmpty
            ? 'Actualización parcial. Se conservaron las tasas guardadas donde no hubo conexión.'
            : updatedCount == 0
            ? 'Las tasas actuales están fijadas manualmente.'
            : 'Tasas actualizadas desde sus fuentes en línea.';
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
    final source = _source.storageKey;
    setState(() {
      _isRefreshingRates = true;
      _rateError = null;
    });
    try {
      final liveRate = source == 'USDT'
          ? await _ratesService.fetchBinanceRate()
          : (await _ratesService.fetchRates())[source];
      if (liveRate == null) {
        throw StateError('No hay una tasa automática para $source.');
      }
      final updated = Map<String, _SavedRate>.from(_rates)
        ..[source] = _SavedRate(
          liveRate.vesPerUnit,
          liveRate.updatedAt,
          isManual: false,
          source: liveRate.source,
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al consultar la tasa: $error')),
      );
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
        title: Text(
          _source.storageKey == 'USDT'
              ? 'Configurar tasa USDT'
              : 'Tasa ${_source.name}',
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _source.storageKey == 'USDT'
                  ? 'Ingresa la tasa en bolívares por cada USDT que utilizas en tu negocio. Esta tasa manual funciona aunque Binance no esté disponible.'
                  : 'Indica cuántos bolívares equivalen a 1 ${_source.unit}.',
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
      ..[_source.storageKey] = _SavedRate(
        rate,
        DateTime.now(),
        isManual: true,
        source: 'Manual',
      );
    await HiveDatabase.settingsBox.put(_rateStorageKey, {
      for (final entry in updated.entries) entry.key: entry.value.toMap(),
    });
    if (!mounted) return;
    setState(() => _rates = updated);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final equivalent = _savedRate == null ? null : _amount * _savedRate!.value;
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Calculadora Multi-Tasa',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Tasas en vivo y conversión a bolívares',
                          style: TextStyle(
                            color: Color(0xFF788596),
                            fontSize: 11,
                          ),
                        ),
                      ],
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
              SizedBox(
                height: 57,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _rateSources.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(width: 8),
                  itemBuilder: (context, index) => SizedBox(
                    width: 88,
                    child: _RatePill(
                      source: _rateSources[index],
                      selected: _selectedRate == index,
                      configured: _rates.containsKey(
                        _rateSources[index].storageKey,
                      ),
                      onTap: () => setState(() => _selectedRate = index),
                    ),
                  ),
                ),
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
                  border: Border.all(color: const Color(0xFFE7ECF2)),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'MONTO',
                          style: TextStyle(
                            color: Color(0xFF788596),
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: .5,
                          ),
                        ),
                        Text(
                          '${_source.unit} ${NumberFormat('#,##0.########', 'es').format(_amount)}',
                          style: const TextStyle(
                            color: Color(0xFF35465A),
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'RESULTADO ESTIMADO · VES',
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
                                    ? 'Define una tasa para calcular'
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
                                ? _source.storageKey == 'USDT'
                                      ? 'Configura tu tasa o consulta Binance P2P'
                                      : 'Esperando tasa en línea'
                                : '${_savedRate!.source} · ${DateFormat('dd/MM/yy HH:mm', 'es').format(_savedRate!.updatedAt)}',
                            style: const TextStyle(
                              color: Color(0xFF7C8795),
                              fontSize: 10,
                            ),
                          ),
                        ),
                        Wrap(
                          spacing: 4,
                          children: [
                            if (_savedRate?.isManual == true ||
                                _source.storageKey == 'USDT')
                              TextButton(
                                onPressed: _isRefreshingRates
                                    ? null
                                    : _useAutomaticRate,
                                child: Text(
                                  _source.storageKey == 'USDT'
                                      ? 'Binance P2P'
                                      : 'Automática',
                                  style: TextStyle(fontSize: 11),
                                ),
                              ),
                            TextButton.icon(
                              onPressed: _editRate,
                              icon: const Icon(Icons.edit_outlined, size: 15),
                              label: Text(
                                _savedRate == null
                                    ? _source.storageKey == 'USDT'
                                          ? 'Configurar USDT'
                                          : 'Definir'
                                    : 'Editar tasa',
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
                    if (_source.storageKey == 'USDT') ...[
                      const SizedBox(height: 4),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'La consulta P2P es opcional; la tasa manual guardada se mantiene disponible sin conexión.',
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
  final String storageKey;

  const _RateSource(this.name, this.unit, {String? key})
    : storageKey = key ?? name;
}

class _SavedRate {
  final double value;
  final DateTime updatedAt;
  final bool isManual;
  final String source;

  const _SavedRate(
    this.value,
    this.updatedAt, {
    required this.isManual,
    required this.source,
  });

  Map<String, Object> toMap() => {
    'value': value,
    'updatedAt': updatedAt.toIso8601String(),
    'isManual': isManual,
    'source': source,
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
    final isManual = map['isManual'] as bool? ?? true;
    return _SavedRate(
      value.toDouble(),
      updatedAt,
      isManual: isManual,
      source: map['source'] as String? ?? (isManual ? 'Manual' : 'DolarApi'),
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
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (source.storageKey == 'USDT')
                  const Padding(
                    padding: EdgeInsets.only(right: 3),
                    child: Icon(
                      Icons.currency_exchange_rounded,
                      size: 12,
                      color: Color(0xFFF0A900),
                    ),
                  ),
                Flexible(
                  child: Text(
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
                ),
              ],
            ),
            const SizedBox(height: 2),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  source.storageKey == 'USDT' ? 'P2P · Manual' : source.unit,
                  style: TextStyle(
                    color: selected
                        ? const Color(0xFF2768D7)
                        : const Color(0xFF788596),
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  configured ? Icons.check_circle : Icons.circle_outlined,
                  size: 9,
                  color: configured
                      ? const Color(0xFF2D9B6F)
                      : const Color(0xFFA8B1BC),
                ),
              ],
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
    color: background ?? (emphasized ? const Color(0xFFEAF1FC) : Colors.white),
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
