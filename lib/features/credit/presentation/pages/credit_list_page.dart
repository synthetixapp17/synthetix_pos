import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/utils/app_currency.dart';
import '../../data/credit_repository.dart';
import '../../domain/entities/credit_record.dart';

class CreditListPage extends StatefulWidget {
  const CreditListPage({super.key});

  @override
  State<CreditListPage> createState() => _CreditListPageState();
}

class _CreditListPageState extends State<CreditListPage> {
  String _query = '';
  bool _showPaid = true;

  @override
  Widget build(BuildContext context) {
    final allCredits = CreditRepository.getAll();
    final openCredits = allCredits.where((credit) => !credit.isPaid).toList();
    final totalDue = openCredits.fold<double>(
      0,
      (total, credit) => total + credit.balance,
    );
    final filtered = allCredits.where((credit) {
      if (!_showPaid && credit.isPaid) return false;
      final query = _query.trim().toLowerCase();
      return query.isEmpty ||
          credit.customerName.toLowerCase().contains(query) ||
          credit.customerPhone.toLowerCase().contains(query) ||
          credit.id.toLowerCase().contains(query);
    }).toList();
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Compras a crédito'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: () => setState(() {}),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
        children: [
          Row(
            children: [
              Expanded(
                child: _SummaryCard(
                  label: 'Saldo por cobrar',
                  value: AppCurrency.formatConfigured(totalDue),
                  detail: '${openCredits.length} créditos pendientes',
                  icon: Icons.account_balance_wallet_outlined,
                  color: colors.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _SummaryCard(
                  label: 'Créditos registrados',
                  value: '${allCredits.length}',
                  detail: '${allCredits.length - openCredits.length} pagados',
                  icon: Icons.receipt_long_outlined,
                  color: const Color(0xFF3878C7),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          TextField(
            onChanged: (value) => setState(() => _query = value),
            decoration: InputDecoration(
              hintText: 'Buscar por cliente, teléfono o folio',
              prefixIcon: const Icon(Icons.search_rounded),
              filled: true,
              fillColor: colors.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: colors.outlineVariant),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: colors.outlineVariant),
              ),
            ),
          ),
          const SizedBox(height: 10),
          FilterChip(
            selected: _showPaid,
            label: const Text('Mostrar créditos pagados'),
            avatar: const Icon(Icons.check_circle_outline, size: 18),
            onSelected: (value) => setState(() => _showPaid = value),
          ),
          const SizedBox(height: 12),
          if (filtered.isEmpty)
            _EmptyCredits(hasCredits: allCredits.isNotEmpty)
          else
            ...filtered.map(
              (credit) => _CreditCard(
                credit: credit,
                onTap: () async {
                  await context.push('/settings/credits/${credit.id}');
                  if (mounted) setState(() {});
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String label;
  final String value;
  final String detail;
  final IconData icon;
  final Color color;

  const _SummaryCard({
    required this.label,
    required this.value,
    required this.detail,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 138),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color),
        const SizedBox(height: 12),
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 3),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
        ),
        const SizedBox(height: 3),
        Text(detail, style: Theme.of(context).textTheme.bodySmall),
      ],
    ),
  );
}

class _CreditCard extends StatelessWidget {
  final CreditRecord credit;
  final VoidCallback onTap;

  const _CreditCard({required this.credit, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isOverdue =
        !credit.isPaid &&
        credit.dueDate != null &&
        credit.dueDate!.isBefore(DateUtils.dateOnly(DateTime.now()));
    final statusColor = credit.isPaid
        ? const Color(0xFF16865B)
        : isOverdue
        ? colors.error
        : const Color(0xFFB36B00);
    final status = credit.isPaid
        ? 'Pagado'
        : isOverdue
        ? 'Vencido'
        : 'Pendiente';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: colors.primaryContainer,
                    foregroundColor: colors.primary,
                    child: const Icon(Icons.person_outline_rounded),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          credit.customerName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          credit.customerPhone.isEmpty
                              ? 'Folio ${credit.id}'
                              : credit.customerPhone,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Text(
                      status,
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 15),
              Row(
                children: [
                  Expanded(
                    child: _AmountColumn(
                      label: 'Total',
                      amount: credit.total,
                      currencyCode: credit.currencyCode,
                    ),
                  ),
                  Expanded(
                    child: _AmountColumn(
                      label: 'Abonado',
                      amount: credit.paidAmount,
                      currencyCode: credit.currencyCode,
                    ),
                  ),
                  Expanded(
                    child: _AmountColumn(
                      label: 'Pendiente',
                      amount: credit.balance,
                      currencyCode: credit.currencyCode,
                      emphasize: !credit.isPaid,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(
                    Icons.calendar_today_outlined,
                    size: 14,
                    color: colors.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      credit.dueDate == null
                          ? 'Registrado ${_formatDate(credit.createdAt)}'
                          : 'Vence ${_formatDate(credit.dueDate!)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  Icon(
                    Icons.picture_as_pdf_outlined,
                    color: colors.primary,
                    size: 19,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Documento adjunto',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colors.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/${date.year}';
}

class _AmountColumn extends StatelessWidget {
  final String label;
  final double amount;
  final String currencyCode;
  final bool emphasize;

  const _AmountColumn({
    required this.label,
    required this.amount,
    required this.currencyCode,
    this.emphasize = false,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: Theme.of(context).textTheme.labelSmall),
      const SizedBox(height: 3),
      FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(
          AppCurrency.format(amount, code: currencyCode),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: emphasize ? Theme.of(context).colorScheme.error : null,
          ),
        ),
      ),
    ],
  );
}

class _EmptyCredits extends StatelessWidget {
  final bool hasCredits;

  const _EmptyCredits({required this.hasCredits});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 58, horizontal: 20),
    child: Column(
      children: [
        Icon(
          hasCredits ? Icons.search_off_rounded : Icons.receipt_long_outlined,
          size: 48,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(height: 12),
        Text(
          hasCredits ? 'No se encontraron créditos' : 'Aún no hay créditos',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Text(
          hasCredits
              ? 'Prueba con otro nombre, teléfono o folio.'
              : 'Las compras a crédito aparecerán aquí con su saldo y documento.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    ),
  );
}
