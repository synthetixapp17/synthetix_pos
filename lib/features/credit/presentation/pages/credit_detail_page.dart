import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../../../core/utils/app_currency.dart';
import '../../data/credit_repository.dart';
import '../../domain/entities/credit_record.dart';

class CreditDetailPage extends StatefulWidget {
  final String creditId;

  const CreditDetailPage({super.key, required this.creditId});

  @override
  State<CreditDetailPage> createState() => _CreditDetailPageState();
}

class _CreditDetailPageState extends State<CreditDetailPage> {
  CreditRecord? _record;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => _record = CreditRepository.getById(widget.creditId);

  Future<void> _addPayment() async {
    final record = _record;
    if (record == null || record.isPaid) return;
    final amountController = TextEditingController();
    final noteController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final result = await showDialog<CreditPayment>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Registrar abono'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Saldo pendiente: ${AppCurrency.format(record.balance, code: record.currencyCode)}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: amountController,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Importe del abono',
                  prefixIcon: Icon(Icons.payments_outlined),
                ),
                validator: (value) {
                  final amount = double.tryParse(
                    (value ?? '').trim().replaceAll(',', '.'),
                  );
                  if (amount == null || amount <= 0) {
                    return 'Escribe un importe válido.';
                  }
                  if (amount > record.balance) {
                    return 'El abono supera el saldo pendiente.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: noteController,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Nota (opcional)',
                  prefixIcon: Icon(Icons.notes_outlined),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              if (!formKey.currentState!.validate()) return;
              Navigator.pop(
                context,
                CreditPayment(
                  paidAt: DateTime.now(),
                  amount: double.parse(
                    amountController.text.trim().replaceAll(',', '.'),
                  ),
                  note: noteController.text.trim(),
                ),
              );
            },
            child: const Text('Guardar abono'),
          ),
        ],
      ),
    );
    amountController.dispose();
    noteController.dispose();
    if (result == null || !mounted) return;

    setState(() => _isProcessing = true);
    try {
      await CreditRepository.addPayment(record.id, result);
      if (!mounted) return;
      setState(_reload);
      _notify('Abono registrado correctamente.');
    } catch (error) {
      if (mounted) _notify('No se pudo registrar el abono: $error');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _sharePdf(CreditRecord record) async {
    setState(() => _isProcessing = true);
    try {
      await Printing.sharePdf(
        bytes: base64Decode(record.pdfBase64),
        filename: 'credito-${record.id}.pdf',
      );
    } catch (error) {
      if (mounted) _notify('No se pudo compartir el PDF: $error');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _printPdf(CreditRecord record) async {
    setState(() => _isProcessing = true);
    try {
      await Printing.layoutPdf(
        onLayout: (_) async => base64Decode(record.pdfBase64),
        name: 'credito-${record.id}.pdf',
      );
    } catch (error) {
      if (mounted) _notify('No se pudo abrir el documento: $error');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _notify(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _date(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/${date.year} '
      '${date.hour.toString().padLeft(2, '0')}:'
      '${date.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final record = _record;
    if (record == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Detalle del crédito')),
        body: const Center(child: Text('No se encontró este crédito.')),
      );
    }
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalle del crédito'),
        actions: [
          IconButton(
            tooltip: 'Compartir PDF',
            onPressed: _isProcessing ? null : () => _sharePdf(record),
            icon: const Icon(Icons.share_outlined),
          ),
          IconButton(
            tooltip: 'Imprimir PDF',
            onPressed: _isProcessing ? null : () => _printPdf(record),
            icon: const Icon(Icons.print_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: colors.primaryContainer,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      record.isPaid
                          ? Icons.check_circle_outline
                          : Icons.account_balance_wallet_outlined,
                      color: colors.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      record.isPaid ? 'Crédito pagado' : 'Saldo pendiente',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  AppCurrency.format(record.balance, code: record.currencyCode),
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text('Folio ${record.id} · ${_date(record.createdAt)}'),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _DetailCard(
            title: 'Cliente',
            icon: Icons.person_outline_rounded,
            children: [
              Text(
                record.customerName,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              if (record.customerPhone.isNotEmpty)
                Text('Teléfono: ${record.customerPhone}'),
              if (record.customerEmail.isNotEmpty)
                Text('Correo: ${record.customerEmail}'),
              if (record.customerAddress.isNotEmpty)
                Text('Dirección: ${record.customerAddress}'),
            ],
          ),
          const SizedBox(height: 12),
          _DetailCard(
            title: 'Resumen de la compra',
            icon: Icons.receipt_long_outlined,
            children: [
              _MoneyRow(
                label: 'Total de la compra',
                amount: record.total,
                code: record.currencyCode,
              ),
              _MoneyRow(
                label: 'Total abonado',
                amount: record.paidAmount,
                code: record.currencyCode,
              ),
              const Divider(height: 18),
              _MoneyRow(
                label: 'Saldo pendiente',
                amount: record.balance,
                code: record.currencyCode,
                bold: true,
              ),
              if (record.dueDate != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text('Fecha acordada: ${_date(record.dueDate!)}'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          _DetailCard(
            title: 'Historial de pagos',
            icon: Icons.history_rounded,
            children: record.payments.isEmpty
                ? [const Text('Aún no se han registrado abonos.')]
                : [
                    for (final payment in record.payments)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.check_circle_outline,
                              size: 18,
                              color: Color(0xFF16865B),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(_date(payment.paidAt)),
                                  if (payment.note.isNotEmpty)
                                    Text(
                                      payment.note,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodySmall,
                                    ),
                                ],
                              ),
                            ),
                            Text(
                              AppCurrency.format(
                                payment.amount,
                                code: record.currencyCode,
                              ),
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
          ),
          const SizedBox(height: 12),
          Card(
            elevation: 0,
            color: colors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(color: colors.outlineVariant),
            ),
            child: ListTile(
              leading: Icon(
                Icons.picture_as_pdf_outlined,
                color: colors.primary,
              ),
              title: const Text(
                'Comprobante PDF adjunto',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: const Text('Guardado con los datos del cliente'),
              trailing: _isProcessing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.chevron_right_rounded),
              onTap: _isProcessing ? null : () => _sharePdf(record),
            ),
          ),
        ],
      ),
      bottomNavigationBar: record.isPaid
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
                child: FilledButton.icon(
                  onPressed: _isProcessing ? null : _addPayment,
                  icon: const Icon(Icons.add_card_rounded),
                  label: const Text('Registrar abono'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ),
    );
  }
}

class _DetailCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const _DetailCard({
    required this.title,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 19, color: colors.primary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _MoneyRow extends StatelessWidget {
  final String label;
  final double amount;
  final String code;
  final bool bold;

  const _MoneyRow({
    required this.label,
    required this.amount,
    required this.code,
    this.bold = false,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(fontWeight: bold ? FontWeight.w800 : null),
          ),
        ),
        Text(
          AppCurrency.format(amount, code: code),
          style: TextStyle(fontWeight: bold ? FontWeight.w900 : null),
        ),
      ],
    ),
  );
}
