import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/utils/app_currency.dart';
import '../../../../core/utils/payment_methods.dart';
import '../../../../core/utils/receipt_preferences.dart';
import '../../../../core/utils/receipt_qr.dart';
import '../../data/receipt_image.dart';
import '../../../credit/data/credit_pdf.dart';
import '../../../credit/data/credit_preferences.dart';
import '../../../credit/domain/entities/credit_schedule.dart';
import '../../../credit/data/credit_repository.dart';
import '../../../credit/domain/entities/credit_record.dart';
import '../../../reports/domain/entities/sale_record.dart';
import '../../../product/presentation/bloc/product_bloc.dart';
import '../../../settings/data/quotation_pdf.dart';
import '../../../settings/data/quotation_preferences.dart';
import '../../../settings/domain/entities/quotation.dart';
import '../../../shop/domain/entities/shop.dart';
import '../../../shop/presentation/bloc/shop_bloc.dart';
import '../../../customer/domain/entities/customer.dart';
import '../../../customer/presentation/bloc/customer_bloc.dart';
import '../../../dashboard/presentation/bloc/dashboard_bloc.dart';
import '../bloc/billing_bloc.dart';

class CheckoutPage extends StatefulWidget {
  const CheckoutPage({super.key});

  @override
  State<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends State<CheckoutPage> {
  final _initialPaymentController = TextEditingController();
  final _cashReceivedController = TextEditingController();
  final _installmentsController = TextEditingController(text: '1');
  final _daysBetweenPaymentsController = TextEditingController(text: '30');
  final _creditRateController = TextEditingController(text: '0');
  String? _receiptDialogSaleId;
  String? _creditSavedSaleId;
  double _creditInitialPayment = 0;
  int _creditInstallments = 1;
  int _creditDaysBetweenPayments = 30;
  double _creditInterestRate = 0;
  String _creditInitialPaymentMethod = loadPaymentMethods().first;
  String _paymentMethod = loadPaymentMethods().first;
  bool _isCreditSale = false;
  bool _isRecordingCredit = false;
  bool _isCreatingQuotation = false;

  @override
  void dispose() {
    _initialPaymentController.dispose();
    _cashReceivedController.dispose();
    _installmentsController.dispose();
    _daysBetweenPaymentsController.dispose();
    _creditRateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    AppCurrencyScope.of(context);
    const borderColor = Color(0xFFE5E5EA);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, dynamic result) {
        if (didPop) return;
        context.read<BillingBloc>().add(ClearCartEvent());
        context.go('/');
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'Finalizar venta',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          centerTitle: true,
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: Icon(
              Icons.chevron_left,
              size: 28,
              color: Theme.of(context).primaryColor,
            ),
            onPressed: () {
              context.read<BillingBloc>().add(ClearCartEvent());
              context.go('/');
            },
          ),
        ),
        body: BlocConsumer<BillingBloc, BillingState>(
          listenWhen: (previous, current) =>
              previous.printSuccess != current.printSuccess ||
              previous.error != current.error ||
              previous.completedSale?.id != current.completedSale?.id,
          listener: (context, state) {
            if (state.completedSale != null &&
                state.completedSale!.id != _receiptDialogSaleId) {
              _receiptDialogSaleId = state.completedSale!.id;
              context.read<DashboardBloc>().add(const LoadDashboardEvent());
              if (state.saleRecorded) {
                context.read<ProductBloc>().add(LoadProducts());
              }
              if (_isCreditSale) {
                unawaited(_recordCreditPurchase(context, state));
              } else {
                unawaited(_showReceiptOptions(context, state));
              }
            }
            if (state.printSuccess) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Ticket impreso. La venta quedó guardada.'),
                  backgroundColor: Colors.green,
                ),
              );
              context.read<BillingBloc>().add(ClearCartEvent());
              context.go('/');
            }
            if (state.error != null) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(state.error!),
                  backgroundColor: Colors.red,
                ),
              );
            }
          },
          builder: (context, billingState) {
            return BlocBuilder<ShopBloc, ShopState>(
              builder: (context, shopState) {
                String upiId = '';
                String shopName = 'Tienda';
                final currencyCode = billingState.cartItems.isEmpty
                    ? AppCurrency.currentCode
                    : billingState.cartItems.first.product.currencyCode;
                final parsedDownPayment = double.tryParse(
                  _initialPaymentController.text.trim().replaceAll(',', '.'),
                );
                final parsedCashReceived = double.tryParse(
                  _cashReceivedController.text.trim().replaceAll(',', '.'),
                );
                final cashReceivedAmount =
                    parsedCashReceived != null && parsedCashReceived.isFinite
                    ? parsedCashReceived
                    : 0.0;
                final changeAmount =
                    (cashReceivedAmount - billingState.totalAmount)
                        .clamp(0.0, double.infinity)
                        .toDouble();
                final downPaymentAmount =
                    parsedDownPayment != null && parsedDownPayment.isFinite
                    ? parsedDownPayment
                    : 0;
                final upiPaymentAmount = _isCreditSale
                    ? downPaymentAmount.clamp(0, billingState.totalAmount)
                    : billingState.totalAmount;

                if (shopState is ShopLoaded) {
                  upiId = shopState.shop.upiId;
                  shopName = shopState.shop.name;
                }

                return Column(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 16,
                        ),
                        child: Column(
                          children: [
                            _CustomerSelector(
                              selectedCustomer: billingState.customer,
                            ),
                            if (!billingState.saleRecorded &&
                                billingState.cartItems.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: () =>
                                      context.go('/new-sale/products'),
                                  icon: const Icon(
                                    Icons.add_shopping_cart_outlined,
                                  ),
                                  label: const Text(
                                    'Seguir agregando productos',
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(height: 18),
                            // Table
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: borderColor),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.05),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Table(
                                  border: const TableBorder(
                                    horizontalInside: BorderSide(
                                      color: borderColor,
                                    ),
                                    bottom: BorderSide(color: borderColor),
                                  ),
                                  children: [
                                    // Header row
                                    TableRow(
                                      decoration: const BoxDecoration(
                                        color: Color(0xFFF8FAFC),
                                        border: Border(
                                          bottom: BorderSide(
                                            color: borderColor,
                                          ),
                                        ),
                                      ),
                                      children: [
                                        _buildHeaderCell(
                                          'Producto',
                                          TextAlign.left,
                                        ),
                                        _buildHeaderCell(
                                          'Precio',
                                          TextAlign.right,
                                        ),
                                        _buildHeaderCell(
                                          'Importe',
                                          TextAlign.right,
                                        ),
                                      ],
                                    ),
                                    // Items rows
                                    ...billingState.cartItems.map((item) {
                                      return TableRow(
                                        children: [
                                          _buildDataCell(
                                            '${item.quantity} x ${item.product.name}',
                                            TextAlign.left,
                                          ),
                                          _buildDataCell(
                                            AppCurrency.formatConfigured(
                                              item.product.price,
                                            ),
                                            TextAlign.right,
                                            isSubtitle: true,
                                          ),
                                          _buildDataCell(
                                            AppCurrency.formatConfigured(
                                              item.total,
                                            ),
                                            TextAlign.right,
                                            isBold: true,
                                          ),
                                        ],
                                      );
                                    }),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),
                            if (upiId.isNotEmpty &&
                                currencyCode == 'INR' &&
                                (!_isCreditSale || upiPaymentAmount > 0))
                              Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    children: [
                                      const Text(
                                        'Pagar con UPI',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      SizedBox(
                                        width: 160,
                                        height: 160,
                                        child: PrettyQrView.data(
                                          data:
                                              'upi://pay?pa=$upiId&pn=$shopName&am=${upiPaymentAmount.toStringAsFixed(2)}&cu=$currencyCode',
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            if (!billingState.saleRecorded &&
                                !_isCreditSale) ...[
                              const SizedBox(height: 12),
                              Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(14),
                                  child: DropdownButtonFormField<String>(
                                    initialValue: _paymentMethod,
                                    decoration: const InputDecoration(
                                      labelText: 'Forma de pago',
                                      prefixIcon: Icon(
                                        Icons.account_balance_wallet_outlined,
                                      ),
                                    ),
                                    items: [
                                      for (final method in loadPaymentMethods())
                                        DropdownMenuItem(
                                          value: method,
                                          child: Text(method),
                                        ),
                                    ],
                                    onChanged: (value) {
                                      if (value != null) {
                                        setState(() => _paymentMethod = value);
                                      }
                                    },
                                  ),
                                ),
                              ),
                              if (_paymentMethod.toLowerCase() ==
                                  'efectivo') ...[
                                const SizedBox(height: 12),
                                Card(
                                  child: Padding(
                                    padding: const EdgeInsets.all(14),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        TextField(
                                          controller: _cashReceivedController,
                                          keyboardType:
                                              const TextInputType.numberWithOptions(
                                                decimal: true,
                                              ),
                                          decoration: InputDecoration(
                                            labelText: 'Efectivo recibido',
                                            prefixIcon: const Icon(
                                              Icons.payments_outlined,
                                            ),
                                            hintText:
                                                AppCurrency.formatConfigured(
                                                  billingState.totalAmount,
                                                ),
                                          ),
                                          onChanged: (_) => setState(() {}),
                                        ),
                                        const SizedBox(height: 10),
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            const Text('Vuelto'),
                                            Text(
                                              AppCurrency.formatConfigured(
                                                changeAmount,
                                              ),
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ],
                            if (QuotationPreferences.enabled &&
                                !billingState.saleRecorded) ...[
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: _isCreatingQuotation
                                      ? null
                                      : () => _createQuotation(
                                          billingState,
                                          shopName,
                                        ),
                                  icon: _isCreatingQuotation
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(
                                          Icons.picture_as_pdf_outlined,
                                        ),
                                  label: const Text('Crear cotización PDF'),
                                ),
                              ),
                            ],
                            if (!billingState.saleRecorded &&
                                CreditPreferences.enabled) ...[
                              const SizedBox(height: 12),
                              _CreditSaleOptions(
                                enabled: billingState.customer != null,
                                isCreditSale: _isCreditSale,
                                initialPaymentController:
                                    _initialPaymentController,
                                installmentsController: _installmentsController,
                                daysBetweenPaymentsController:
                                    _daysBetweenPaymentsController,
                                interestRateController: _creditRateController,
                                total: billingState.totalAmount,
                                currencyCode: currencyCode,
                                interestRate: _creditInterestRate,
                                installmentCount: _creditInstallments,
                                daysBetweenPayments: _creditDaysBetweenPayments,
                                initialPaymentMethod:
                                    _creditInitialPaymentMethod,
                                onInitialPaymentMethodChanged: (value) =>
                                    setState(
                                      () => _creditInitialPaymentMethod = value,
                                    ),
                                onChanged: (value) =>
                                    setState(() => _isCreditSale = value),
                                onInstallmentsChanged: (value) => setState(
                                  () => _creditInstallments =
                                      int.tryParse(value) ?? 0,
                                ),
                                onDaysBetweenPaymentsChanged: (value) =>
                                    setState(
                                      () => _creditDaysBetweenPayments =
                                          int.tryParse(value) ?? 0,
                                    ),
                                onInitialPaymentChanged: (_) => setState(() {}),
                                onInterestRateChanged: (value) => setState(
                                  () => _creditInterestRate = _parseCreditRate(
                                    value,
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(height: 16),
                          ],
                        ),
                      ),
                    ),

                    SafeArea(
                      top: false,
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          border: Border(
                            top: BorderSide(
                              color: Theme.of(
                                context,
                              ).colorScheme.outlineVariant,
                            ),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: .06),
                              blurRadius: 16,
                              offset: const Offset(0, -4),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Total de la venta',
                                  style: Theme.of(context).textTheme.titleSmall
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                Text(
                                  AppCurrency.formatConfigured(
                                    billingState.totalAmount,
                                  ),
                                  style: Theme.of(context).textTheme.titleLarge
                                      ?.copyWith(
                                        fontWeight: FontWeight.w900,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primary,
                                      ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed:
                                    billingState.isPrinting ||
                                        billingState.isSavingSale ||
                                        _isRecordingCredit
                                    ? null
                                    : () {
                                        if (billingState.saleRecorded) {
                                          final saleId =
                                              billingState.completedSale?.id;
                                          if (_isCreditSale &&
                                              saleId != _creditSavedSaleId) {
                                            unawaited(
                                              _recordCreditPurchase(
                                                context,
                                                billingState,
                                              ),
                                            );
                                          } else if (!_isCreditSale) {
                                            unawaited(
                                              _showReceiptOptions(
                                                context,
                                                billingState,
                                              ),
                                            );
                                          }
                                        } else if (_validateCreditSale(
                                              billingState,
                                            ) &&
                                            _validateCashPayment(
                                              billingState,
                                            )) {
                                          context.read<BillingBloc>().add(
                                            CompleteSaleEvent(
                                              paymentMethod: _isCreditSale
                                                  ? _creditInitialPaymentMethod
                                                  : _paymentMethod,
                                              isCreditSale: _isCreditSale,
                                              amountTendered:
                                                  !_isCreditSale &&
                                                      _paymentMethod
                                                              .toLowerCase() ==
                                                          'efectivo'
                                                  ? cashReceivedAmount
                                                  : 0,
                                            ),
                                          );
                                        }
                                      },
                                icon:
                                    _isRecordingCredit ||
                                        billingState.isSavingSale ||
                                        billingState.isPrinting
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : Icon(
                                        _isCreditSale
                                            ? Icons
                                                  .account_balance_wallet_outlined
                                            : Icons.check_circle_outline,
                                      ),
                                label: Text(
                                  _isRecordingCredit
                                      ? 'Guardando crédito...'
                                      : billingState.saleRecorded
                                      ? _isCreditSale
                                            ? 'Guardar compra a crédito'
                                            : 'Ver opciones del ticket'
                                      : _isCreditSale
                                      ? 'Registrar compra a crédito'
                                      : 'Finalizar venta',
                                ),
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 15,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  bool _validateCreditSale(BillingState billingState) {
    if (!_isCreditSale) return true;
    if (billingState.customer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecciona un cliente para registrar el crédito.'),
        ),
      );
      return false;
    }

    final initialPayment = _initialPaymentController.text.trim().isEmpty
        ? 0.0
        : double.tryParse(
            _initialPaymentController.text.trim().replaceAll(',', '.'),
          );
    if (initialPayment == null ||
        !initialPayment.isFinite ||
        initialPayment < 0 ||
        initialPayment > billingState.totalAmount) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'El abono inicial debe ser válido y no superar el total.',
          ),
        ),
      );
      return false;
    }
    final installments = int.tryParse(_installmentsController.text.trim());
    final interestRate = double.tryParse(
      _creditRateController.text.trim().replaceAll(',', '.'),
    );
    final daysBetweenPayments = int.tryParse(
      _daysBetweenPaymentsController.text.trim(),
    );
    if (installments == null ||
        installments < 1 ||
        installments > 600 ||
        interestRate == null ||
        !interestRate.isFinite ||
        interestRate < 0 ||
        daysBetweenPayments == null ||
        daysBetweenPayments < 1 ||
        daysBetweenPayments > 3650 ||
        !(billingState.totalAmount - initialPayment).isFinite ||
        !((billingState.totalAmount - initialPayment) * interestRate / 100)
            .isFinite) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Usa de 1 a 600 cuotas, una tasa válida y un plazo de 1 a 3650 días.',
          ),
        ),
      );
      return false;
    }
    _creditInitialPayment = initialPayment;
    _creditInstallments = installments;
    _creditInterestRate = interestRate;
    _creditDaysBetweenPayments = daysBetweenPayments;
    return true;
  }

  bool _validateCashPayment(BillingState billingState) {
    if (_isCreditSale || _paymentMethod.toLowerCase() != 'efectivo') {
      return true;
    }
    final amount = double.tryParse(
      _cashReceivedController.text.trim().replaceAll(',', '.'),
    );
    if (amount == null ||
        !amount.isFinite ||
        amount + 0.000001 < billingState.totalAmount) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Ingresa el efectivo recibido. Debe ser igual o mayor al total.',
          ),
        ),
      );
      return false;
    }
    return true;
  }

  Future<void> _recordCreditPurchase(
    BuildContext context,
    BillingState billingState,
  ) async {
    final sale = billingState.completedSale;
    final customer = billingState.customer;
    if (sale == null || customer == null || _isRecordingCredit) return;

    setState(() => _isRecordingCredit = true);
    try {
      final shopState = context.read<ShopBloc>().state;
      final shop = shopState is ShopLoaded ? shopState.shop : const Shop();
      final paid = _creditInitialPayment.clamp(0, sale.total).toDouble();
      final financedPrincipal = sale.total - paid;
      final interestAmount = CreditSchedule.simpleInterest(
        principal: financedPrincipal,
        percentage: _creditInterestRate,
      );
      final finalDueDate = sale.soldAt.add(
        Duration(days: _creditDaysBetweenPayments * _creditInstallments),
      );
      final pdfBytes = await CreditPdf.build(
        sale: sale,
        shopName: shop.name,
        customerName: customer.name,
        customerPhone: customer.phone,
        customerEmail: customer.email,
        customerAddress: customer.address,
        customerIdentity: customer.identityNumber,
        initialPayment: paid,
        initialPaymentMethod: _creditInitialPaymentMethod,
        numberOfInstallments: _creditInstallments,
        daysBetweenPayments: _creditDaysBetweenPayments,
        interestPercentage: _creditInterestRate,
        terms: CreditPreferences.terms,
        template: CreditPreferences.template,
        primaryColor: CreditPreferences.primaryColor,
        accentColor: CreditPreferences.accentColor,
        shopAddress: [
          shop.addressLine1,
          shop.addressLine2,
        ].where((line) => line.trim().isNotEmpty).join(', '),
        shopPhone: shop.phoneNumber,
        logoData: shop.logoData,
      );
      final record = CreditRecord(
        id: sale.id,
        createdAt: sale.soldAt,
        dueDate: finalDueDate,
        customerId: customer.id,
        customerName: customer.name,
        customerPhone: customer.phone,
        customerIdentity: customer.identityNumber,
        customerEmail: customer.email,
        customerAddress: customer.address,
        total: sale.total + interestAmount,
        interestPercentage: _creditInterestRate,
        interestAmount: interestAmount,
        purchaseAmount: sale.total,
        initialPayment: paid,
        installmentCount: _creditInstallments,
        daysBetweenPayments: _creditDaysBetweenPayments,
        currencyCode: sale.currencyCode,
        pdfBase64: base64Encode(pdfBytes),
        lines: sale.lines
            .map(
              (line) => CreditLineItem(
                productId: line.productId,
                productName: line.productName,
                category: line.category,
                barcode: line.barcode,
                quantity: line.quantity,
                unitPrice: line.unitPrice,
              ),
            )
            .toList(),
        payments: paid > 0
            ? [
                CreditPayment(
                  paidAt: sale.soldAt,
                  amount: paid,
                  note: 'Abono inicial',
                  method: _creditInitialPaymentMethod,
                ),
              ]
            : const [],
      );
      await CreditRepository.save(record);
      if (!mounted) return;
      _creditSavedSaleId = sale.id;
      final action = await showDialog<_CreditSavedAction>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.verified_outlined, size: 38),
          title: const Text('Crédito registrado'),
          content: Text(
            'El comprobante PDF se guardó junto con los datos de ${customer.name}. '
            'Saldo pendiente: ${AppCurrency.format(record.balance, code: record.currencyCode)}.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, _CreditSavedAction.close),
              child: const Text('Listo'),
            ),
            OutlinedButton.icon(
              onPressed: () => Navigator.pop(context, _CreditSavedAction.print),
              icon: const Icon(Icons.print_outlined),
              label: const Text('Imprimir / Guardar'),
            ),
            OutlinedButton.icon(
              onPressed: () => Navigator.pop(context, _CreditSavedAction.share),
              icon: const Icon(Icons.share_outlined),
              label: const Text('Compartir'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, _CreditSavedAction.view),
              icon: const Icon(Icons.open_in_new_rounded),
              label: const Text('Ver crédito'),
            ),
          ],
        ),
      );
      if (!mounted || action == null) return;

      switch (action) {
        case _CreditSavedAction.close:
          context.read<BillingBloc>().add(ClearCartEvent());
          context.go('/');
        case _CreditSavedAction.view:
          context.read<BillingBloc>().add(ClearCartEvent());
          context.go('/settings/credits/${record.id}');
        case _CreditSavedAction.share:
          try {
            await Printing.sharePdf(
              bytes: pdfBytes,
              filename: 'credito-${record.id}.pdf',
            );
            if (!mounted) return;
            context.read<BillingBloc>().add(ClearCartEvent());
            context.go('/');
          } catch (error) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'El crédito quedó guardado, pero no se pudo compartir el PDF: $error',
                  ),
                ),
              );
            }
          }
        case _CreditSavedAction.print:
          try {
            await Printing.layoutPdf(
              name: 'contrato-credito-${record.id}.pdf',
              onLayout: (_) async => pdfBytes,
            );
            if (!mounted) return;
            context.read<BillingBloc>().add(ClearCartEvent());
            context.go('/');
          } catch (error) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'El crédito quedó guardado, pero no se pudo abrir la impresión del contrato: $error',
                  ),
                ),
              );
            }
          }
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'La venta quedó guardada, pero no se pudo guardar el crédito y su PDF: $error',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isRecordingCredit = false);
    }
  }

  Future<void> _createQuotation(
    BillingState billingState,
    String shopName,
  ) async {
    if (_isCreatingQuotation || billingState.cartItems.isEmpty) return;
    setState(() => _isCreatingQuotation = true);
    var quotationSaved = false;
    try {
      final quotation = QuotationRecord(
        id: const Uuid().v4().substring(0, 8).toUpperCase(),
        createdAt: DateTime.now(),
        customerName: billingState.customer?.name ?? '',
        shopName: shopName,
        currencyCode: billingState.cartItems.first.product.currencyCode,
        lines: billingState.cartItems
            .map(
              (item) => QuotationLine(
                productName: item.product.name,
                barcode: item.product.barcode,
                quantity: item.quantity,
                unitPrice: item.product.price,
              ),
            )
            .toList(),
      );
      final bytes = await QuotationPdf.build(
        quotation: quotation,
        template: QuotationPreferences.template,
        primaryColor: QuotationPreferences.primaryColor,
        accentColor: QuotationPreferences.accentColor,
      );
      await QuotationPreferences.addToHistory(quotation);
      quotationSaved = true;
      if (!mounted) return;
      final shared = await Printing.sharePdf(
        bytes: Uint8List.fromList(bytes),
        filename: 'cotizacion-${quotation.id}.pdf',
      );
      if (mounted && shared) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cotización guardada en el historial.')),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Cotización guardada, pero no se pudo abrir la descarga del PDF.',
            ),
          ),
        );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            quotationSaved
                ? 'Cotización guardada, pero no se pudo abrir el PDF: $error'
                : 'No se pudo crear la cotización: $error',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isCreatingQuotation = false);
    }
  }

  Future<void> _showReceiptOptions(
    BuildContext context,
    BillingState billingState,
  ) async {
    final sale = billingState.completedSale;
    if (sale == null || !mounted) return;
    final shopState = context.read<ShopBloc>().state;
    final shop = shopState is ShopLoaded ? shopState.shop : const Shop();
    final shopName = shop.name.isEmpty ? 'MI TIENDA' : shop.name;
    final action = await showDialog<_ReceiptAction>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _ReceiptPreviewDialog(
        sale: sale,
        shopName: shopName,
        address: [
          shop.addressLine1,
          shop.addressLine2,
        ].where((line) => line.trim().isNotEmpty).join(', '),
        shopPhone: shop.phoneNumber,
        rif: shop.rif,
        qrData: ReceiptQr.saleUrl(sale.id),
        logoData: shop.logoData,
        footer: ReceiptPreferences.footerText ?? shop.footerText,
        showRif: ReceiptPreferences.showRif,
        showInvoiceQr: ReceiptPreferences.showInvoiceQr,
        canRegisterCustomer: billingState.customer == null,
      ),
    );
    if (!context.mounted || action == null) return;

    switch (action) {
      case _ReceiptAction.print:
        context.read<BillingBloc>().add(
          PrintReceiptEvent(
            shopName: shopName,
            address1: shop.addressLine1,
            address2: shop.addressLine2,
            phone: shop.phoneNumber,
            rif: shop.rif,
            qrData: ReceiptPreferences.showInvoiceQr
                ? ReceiptQr.saleUrl(sale.id)
                : null,
            customerName: billingState.customer?.name,
            logoData: shop.logoData,
            footer: ReceiptPreferences.footerText ?? shop.footerText,
            currencyCode: sale.currencyCode,
            paymentMethod: sale.paymentMethod,
            amountTendered: sale.amountTendered,
            changeAmount: sale.changeAmount,
            showAddress: ReceiptPreferences.showAddress,
            showPhone: ReceiptPreferences.showPhone,
            showRif: ReceiptPreferences.showRif,
            showInvoiceQr: ReceiptPreferences.showInvoiceQr,
            showDate: ReceiptPreferences.showDate,
            showBarcode: ReceiptPreferences.showBarcode,
            showUnitPrices: ReceiptPreferences.showUnitPrices,
          ),
        );
      case _ReceiptAction.whatsapp:
        await _shareWhatsappReceipt(context, sale, shop);
      case _ReceiptAction.registerCustomer:
        final customer = await context.push<Customer>('/customers/new?quick=1');
        if (!context.mounted || customer == null) return;
        final billingBloc = context.read<BillingBloc>();
        final update = billingBloc.stream.firstWhere(
          (state) =>
              state.completedSale?.customerId == customer.id ||
              state.error != null,
        );
        billingBloc.add(UpdateSaleCustomerEvent(customer));
        final updatedState = await update;
        if (updatedState.completedSale?.customerId != customer.id) {
          if (context.mounted && updatedState.error != null) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(updatedState.error!)));
          }
          return;
        }
        if (!context.mounted) return;
        await _shareWhatsappReceipt(context, updatedState.completedSale!, shop);
      case _ReceiptAction.noReceipt:
        context.read<BillingBloc>().add(ClearCartEvent());
        context.go('/');
    }
  }

  Future<void> _shareWhatsappReceipt(
    BuildContext context,
    SaleRecord sale,
    Shop shop,
  ) async {
    final shopName = shop.name.isEmpty ? 'MI TIENDA' : shop.name;
    final address = [
      shop.addressLine1,
      shop.addressLine2,
    ].where((line) => line.trim().isNotEmpty).join(', ');
    final message = StringBuffer()
      ..writeln(shopName)
      ..writeln('Comprobante de compra')
      ..writeln(
        'Fecha: ${DateFormat('dd/MM/yyyy HH:mm', 'es').format(sale.soldAt)}',
      )
      ..writeln('Folio: ${sale.id}')
      ..writeln();
    for (final line in sale.lines) {
      message.writeln(
        '${line.quantity} x ${line.productName}: '
        '${AppCurrency.format(line.total, code: sale.currencyCode)}',
      );
    }
    message
      ..writeln()
      ..writeln('Forma de pago: ${sale.paymentMethod}')
      ..writeln()
      ..write(
        'TOTAL: ${AppCurrency.format(sale.total, code: sale.currencyCode)}',
      );
    try {
      final image = await ReceiptImage.build(
        sale: sale,
        shopName: shopName,
        address: address,
        shopPhone: shop.phoneNumber,
        rif: shop.rif,
        qrData: ReceiptQr.saleUrl(sale.id),
        logoData: shop.logoData,
        footer: ReceiptPreferences.footerText ?? shop.footerText,
        showAddress: ReceiptPreferences.showAddress,
        showPhone: ReceiptPreferences.showPhone,
        showRif: ReceiptPreferences.showRif,
        showInvoiceQr: ReceiptPreferences.showInvoiceQr,
        showDate: ReceiptPreferences.showDate,
        showBarcode: ReceiptPreferences.showBarcode,
        showUnitPrices: ReceiptPreferences.showUnitPrices,
      );
      final filename =
          'ticket-${sale.id.substring(0, sale.id.length > 8 ? 8 : sale.id.length)}.png';
      final result = await SharePlus.instance.share(
        ShareParams(
          title: 'Ticket de compra',
          text: message.toString(),
          files: [XFile.fromData(image, name: filename, mimeType: 'image/png')],
          fileNameOverrides: [filename],
        ),
      );
      if (!context.mounted) return;
      if (result.status == ShareResultStatus.success) {
        context.read<BillingBloc>().add(ClearCartEvent());
        context.go('/');
      } else if (result.status == ShareResultStatus.dismissed) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No se compartió el ticket. Puedes volver a intentarlo.',
            ),
          ),
        );
      } else {
        throw StateError('El sistema no pudo abrir el menú para compartir.');
      }
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo preparar el ticket para compartir: $error'),
        ),
      );
    }
  }

  Widget _buildHeaderCell(String text, TextAlign align) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Text(
        text.toUpperCase(),
        textAlign: align,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 1,
          color: Colors.grey,
        ),
      ),
    );
  }

  Widget _buildDataCell(
    String text,
    TextAlign align, {
    bool isBold = false,
    bool isSubtitle = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      child: Text(
        text,
        textAlign: align,
        style: TextStyle(
          fontSize: isSubtitle ? 12 : 14,
          fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
          color: isSubtitle ? Colors.grey[500] : Colors.black87,
        ),
      ),
    );
  }
}

double _parseCreditRate(String value) {
  final rate = double.tryParse(value.trim().replaceAll(',', '.'));
  return rate != null && rate.isFinite && rate >= 0 ? rate : 0;
}

enum _ReceiptAction { print, whatsapp, registerCustomer, noReceipt }

enum _CreditSavedAction { close, view, share, print }

class _CreditSaleOptions extends StatelessWidget {
  final bool enabled;
  final bool isCreditSale;
  final TextEditingController initialPaymentController;
  final TextEditingController installmentsController;
  final TextEditingController daysBetweenPaymentsController;
  final TextEditingController interestRateController;
  final double total;
  final String currencyCode;
  final int installmentCount;
  final int daysBetweenPayments;
  final double interestRate;
  final String initialPaymentMethod;
  final ValueChanged<bool> onChanged;
  final ValueChanged<String> onInstallmentsChanged;
  final ValueChanged<String> onDaysBetweenPaymentsChanged;
  final ValueChanged<String> onInitialPaymentChanged;
  final ValueChanged<String> onInterestRateChanged;
  final ValueChanged<String> onInitialPaymentMethodChanged;

  const _CreditSaleOptions({
    required this.enabled,
    required this.isCreditSale,
    required this.initialPaymentController,
    required this.installmentsController,
    required this.daysBetweenPaymentsController,
    required this.interestRateController,
    required this.total,
    required this.currencyCode,
    required this.installmentCount,
    required this.daysBetweenPayments,
    required this.interestRate,
    required this.initialPaymentMethod,
    required this.onChanged,
    required this.onInstallmentsChanged,
    required this.onDaysBetweenPaymentsChanged,
    required this.onInitialPaymentChanged,
    required this.onInterestRateChanged,
    required this.onInitialPaymentMethodChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final parsedInitialPayment = double.tryParse(
      initialPaymentController.text.trim().replaceAll(',', '.'),
    );
    final initialPayment =
        parsedInitialPayment != null && parsedInitialPayment.isFinite
        ? parsedInitialPayment
        : 0;
    final downPayment = initialPayment.clamp(0, total).toDouble();
    final principal = total - downPayment;
    final rawInterest = principal * interestRate / 100;
    final interest = rawInterest.isFinite
        ? CreditSchedule.roundMoney(rawInterest)
        : 0;
    final totalDue = principal + interest;
    final count = installmentCount.clamp(1, 600);
    final previewCount = count < 4 ? count : 4;
    final installments = CreditSchedule.splitEvenly(totalDue, count);
    final scheduleDays = daysBetweenPayments.clamp(1, 3650);

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        children: [
          CheckboxListTile(
            value: isCreditSale,
            onChanged: enabled ? (value) => onChanged(value ?? false) : null,
            controlAffinity: ListTileControlAffinity.leading,
            secondary: Icon(
              Icons.account_balance_wallet_outlined,
              color: colors.primary,
            ),
            title: const Text(
              'Plan de venta a crédito',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            subtitle: Text(
              enabled
                  ? 'Define el abono, la tasa y el calendario antes de registrar.'
                  : 'Selecciona un cliente para habilitar el financiamiento.',
            ),
          ),
          if (isCreditSale)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Divider(height: 1),
                  const SizedBox(height: 16),
                  Text(
                    'CONDICIONES DE FINANCIAMIENTO',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: .6,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: initialPaymentController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          onChanged: onInitialPaymentChanged,
                          decoration: const InputDecoration(
                            labelText: 'Abono inicial',
                            hintText: '0,00',
                            prefixIcon: Icon(Icons.payments_outlined),
                            helperText: 'Se descuenta de la venta.',
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: interestRateController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          onChanged: onInterestRateChanged,
                          decoration: const InputDecoration(
                            labelText: 'Interés del crédito',
                            suffixText: '%',
                            prefixIcon: Icon(Icons.percent_rounded),
                            helperText: 'Sobre el saldo financiado.',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: initialPaymentMethod,
                    decoration: const InputDecoration(
                      labelText: 'Forma de pago del abono inicial',
                      prefixIcon: Icon(Icons.account_balance_outlined),
                    ),
                    items: [
                      for (final method in CreditPayment.methods)
                        DropdownMenuItem(value: method, child: Text(method)),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        onInitialPaymentMethodChanged(value);
                      }
                    },
                  ),
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: installmentsController,
                          keyboardType: TextInputType.number,
                          onChanged: onInstallmentsChanged,
                          decoration: const InputDecoration(
                            labelText: 'Cantidad de cuotas',
                            prefixIcon: Icon(Icons.format_list_numbered),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: daysBetweenPaymentsController,
                          keyboardType: TextInputType.number,
                          onChanged: onDaysBetweenPaymentsChanged,
                          decoration: const InputDecoration(
                            labelText: 'Frecuencia (días)',
                            prefixIcon: Icon(Icons.calendar_month_outlined),
                            helperText: '30 días = mensual.',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: colors.primaryContainer.withValues(alpha: .42),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: colors.primary.withValues(alpha: .16),
                      ),
                    ),
                    child: Column(
                      children: [
                        _CreditSummaryLine(
                          label: 'Abono inicial',
                          value: AppCurrency.format(
                            downPayment,
                            code: currencyCode,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _CreditSummaryLine(
                          label: 'Capital financiado',
                          value: AppCurrency.format(
                            principal,
                            code: currencyCode,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _CreditSummaryLine(
                          label:
                              'Interés (${interestRate.toStringAsFixed(2)}%)',
                          value: AppCurrency.format(
                            interest,
                            code: currencyCode,
                          ),
                        ),
                        const Divider(height: 18),
                        _CreditSummaryLine(
                          label: 'Total de la operación',
                          value: AppCurrency.format(
                            downPayment + totalDue,
                            code: currencyCode,
                          ),
                          emphasize: true,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      const Icon(Icons.event_note_outlined, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'Calendario de pagos',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        'Cada $scheduleDays días',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (installmentCount > 0 && daysBetweenPayments > 0)
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: colors.outlineVariant),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          for (var index = 0; index < previewCount; index++)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 9,
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 28,
                                    height: 28,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: colors.primaryContainer,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Text(
                                      '${index + 1}',
                                      style: TextStyle(
                                        color: colors.primary,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      'Cuota ${index + 1} · '
                                      '${DateFormat('dd/MM/yyyy').format(DateTime.now().add(Duration(days: scheduleDays * (index + 1))))}',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodySmall,
                                    ),
                                  ),
                                  Text(
                                    AppCurrency.format(
                                      installments[index],
                                      code: currencyCode,
                                    ),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          if (count > previewCount)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                              child: Text(
                                'Las ${count - previewCount} cuotas restantes se incluirán en el contrato.',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: colors.onSurfaceVariant),
                              ),
                            ),
                        ],
                      ),
                    )
                  else
                    Text(
                      'Indica una cantidad de cuotas y una frecuencia válidas.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  const SizedBox(height: 10),
                  Text(
                    'El porcentaje se aplica una sola vez al capital financiado. '
                    'El contrato incluirá el total, el interés y cada fecha de pago.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _CreditSummaryLine extends StatelessWidget {
  final String label;
  final String value;
  final bool emphasize;

  const _CreditSummaryLine({
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          label,
          style: TextStyle(
            fontSize: emphasize ? 14 : 12,
            fontWeight: emphasize ? FontWeight.w800 : FontWeight.w500,
          ),
        ),
      ),
      Text(
        value,
        style: TextStyle(
          fontSize: emphasize ? 15 : 12,
          fontWeight: FontWeight.w800,
          color: emphasize ? Theme.of(context).colorScheme.primary : null,
        ),
      ),
    ],
  );
}

class _ReceiptPreviewDialog extends StatelessWidget {
  final SaleRecord sale;
  final String shopName;
  final String address;
  final String shopPhone;
  final String rif;
  final String qrData;
  final String? logoData;
  final String footer;
  final bool showRif;
  final bool showInvoiceQr;
  final bool canRegisterCustomer;

  const _ReceiptPreviewDialog({
    required this.sale,
    required this.shopName,
    required this.address,
    required this.shopPhone,
    required this.rif,
    required this.qrData,
    required this.logoData,
    required this.footer,
    required this.showRif,
    required this.showInvoiceQr,
    required this.canRegisterCustomer,
  });

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Comprobante de compra'),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (logoData != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Image.memory(
                    base64Decode(logoData!),
                    height: 64,
                    fit: BoxFit.contain,
                  ),
                ),
              Text(
                shopName.isEmpty ? 'MI TIENDA' : shopName.toUpperCase(),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
              if (ReceiptPreferences.showAddress && address.isNotEmpty)
                Text(address, textAlign: TextAlign.center),
              if (ReceiptPreferences.showPhone && shopPhone.isNotEmpty)
                Text(shopPhone, textAlign: TextAlign.center),
              if (showRif && rif.trim().isNotEmpty)
                Text('RIF: ${rif.trim()}', textAlign: TextAlign.center),
              if (sale.customerName != null)
                Text(
                  'Cliente: ${sale.customerName}',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              Text(
                'Forma de pago: ${sale.paymentMethod}',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (sale.paymentMethod.toLowerCase() == 'efectivo' &&
                  sale.amountTendered > 0) ...[
                Text(
                  'Efectivo recibido: ${AppCurrency.format(sale.amountTendered, code: sale.currencyCode)}',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Text(
                  'Vuelto: ${AppCurrency.format(sale.changeAmount, code: sale.currencyCode)}',
                  textAlign: TextAlign.center,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
              if (ReceiptPreferences.showDate)
                Text(
                  DateFormat('dd/MM/yyyy HH:mm', 'es').format(sale.soldAt),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              const Divider(height: 24),
              for (final line in sale.lines)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              line.productName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              ReceiptPreferences.showUnitPrices
                                  ? '${line.quantity} × ${AppCurrency.format(line.unitPrice, code: sale.currencyCode)}'
                                  : '${line.quantity} unidades',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            if (ReceiptPreferences.showBarcode)
                              Text(
                                'Código: ${line.barcode}',
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        AppCurrency.format(line.total, code: sale.currencyCode),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              const Divider(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'TOTAL',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  Text(
                    AppCurrency.format(sale.total, code: sale.currencyCode),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              if (footer.trim().isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(footer, textAlign: TextAlign.center),
              ],
              if (showInvoiceQr) ...[
                const SizedBox(height: 12),
                Center(
                  child: SizedBox(
                    width: 96,
                    height: 96,
                    child: PrettyQrView.data(data: qrData),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Escanea para consultar esta venta',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
              const SizedBox(height: 8),
              Text(
                'Folio ${sale.id.substring(0, sale.id.length > 8 ? 8 : sale.id.length)}',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      if (canRegisterCustomer)
        TextButton.icon(
          onPressed: () =>
              Navigator.pop(context, _ReceiptAction.registerCustomer),
          icon: const Icon(Icons.person_add_alt_1_outlined),
          label: const Text('Registrar cliente'),
        ),
      TextButton(
        onPressed: () => Navigator.pop(context, _ReceiptAction.noReceipt),
        child: const Text('Sin factura'),
      ),
      OutlinedButton.icon(
        onPressed: () => Navigator.pop(context, _ReceiptAction.whatsapp),
        icon: const Icon(Icons.chat_outlined),
        label: const Text('WhatsApp'),
      ),
      FilledButton.icon(
        onPressed: () => Navigator.pop(context, _ReceiptAction.print),
        icon: const Icon(Icons.print_outlined),
        label: const Text('Imprimir'),
      ),
    ],
  );
}

class _CustomerSelector extends StatelessWidget {
  final Customer? selectedCustomer;
  const _CustomerSelector({required this.selectedCustomer});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: BlocBuilder<CustomerBloc, CustomerState>(
          builder: (context, state) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Cliente de la venta',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<Customer?>(
                initialValue: selectedCustomer,
                isExpanded: true,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.person_outline),
                  labelText: 'Selecciona un cliente (opcional)',
                ),
                items: [
                  const DropdownMenuItem<Customer?>(
                    value: null,
                    child: Text('Venta sin cliente'),
                  ),
                  ...state.customers.map(
                    (customer) => DropdownMenuItem<Customer?>(
                      value: customer,
                      child: Text(customer.name),
                    ),
                  ),
                ],
                onChanged: (customer) => context.read<BillingBloc>().add(
                  SelectCustomerEvent(customer),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () async {
                    final customer = await context.push<Customer>(
                      '/customers/new?quick=1',
                    );
                    if (customer != null && context.mounted) {
                      context.read<BillingBloc>().add(
                        SelectCustomerEvent(customer),
                      );
                    }
                  },
                  icon: const Icon(Icons.person_add_alt_1),
                  label: const Text('Crear cliente rápido'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
