import 'dart:async';
import 'dart:convert';

import 'package:billing_app/core/widgets/primary_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';

import '../../../../core/utils/app_currency.dart';
import '../../../../core/utils/receipt_preferences.dart';
import '../../../reports/domain/entities/sale_record.dart';
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
  String? _receiptDialogSaleId;

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
              unawaited(_showReceiptOptions(context, state));
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

                            const SizedBox(
                              height: 120,
                            ), // padding for bottom fixed bar
                          ],
                        ),
                      ),
                    ),

                    // Bottom Bar
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.9),
                        borderRadius: const BorderRadius.horizontal(
                          left: Radius.circular(24),
                          right: Radius.circular(24),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 10,
                            offset: const Offset(0, -4),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Column(
                              children: [
                                const SizedBox(height: 8),
                                upiId.isNotEmpty && currencyCode == 'INR'
                                    ? Column(
                                        children: [
                                          const Text(
                                            'Escanea para pagar',
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.black87,
                                              letterSpacing: 1.1,
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          SizedBox(
                                            width: 180,
                                            height: 180,
                                            child: PrettyQrView.data(
                                              data:
                                                  'upi://pay?pa=$upiId&pn=$shopName&am=${billingState.totalAmount.toStringAsFixed(2)}&cu=$currencyCode',
                                            ),
                                          ),
                                        ],
                                      )
                                    : const SizedBox.shrink(),
                                const SizedBox(height: 15),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'TOTAL A PAGAR',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.grey[400],
                                        letterSpacing: 1.2,
                                      ),
                                    ),
                                    Text(
                                      AppCurrency.formatConfigured(
                                        billingState.totalAmount,
                                      ),
                                      style: const TextStyle(
                                        fontSize: 24,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: -0.5,
                                        color: Color(0xFF0F172A),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          PrimaryButton(
                            onPressed: () {
                              if (billingState.saleRecorded) {
                                unawaited(
                                  _showReceiptOptions(context, billingState),
                                );
                              } else {
                                context.read<BillingBloc>().add(
                                  CompleteSaleEvent(),
                                );
                              }
                            },
                            label: billingState.saleRecorded
                                ? 'Ver opciones del ticket'
                                : 'Finalizar venta',
                            icon: Icons.check_circle_outline,
                            isLoading:
                                billingState.isPrinting ||
                                billingState.isSavingSale,
                          ),
                        ],
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
        logoData: shop.logoData,
        footer: ReceiptPreferences.footerText ?? shop.footerText,
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
            customerName: billingState.customer?.name,
            logoData: shop.logoData,
            footer: ReceiptPreferences.footerText ?? shop.footerText,
            currencyCode: sale.currencyCode,
            showAddress: ReceiptPreferences.showAddress,
            showPhone: ReceiptPreferences.showPhone,
            showDate: ReceiptPreferences.showDate,
            showBarcode: ReceiptPreferences.showBarcode,
            showUnitPrices: ReceiptPreferences.showUnitPrices,
          ),
        );
      case _ReceiptAction.whatsapp:
        final recipient = await _requestWhatsappRecipient(
          context,
          initialPhone: billingState.customer?.phone ?? '',
          allowRegistration: billingState.customer == null,
        );
        if (!context.mounted || recipient == null) return;

        var phone = recipient.phone;
        if (recipient.registerCustomer) {
          final customer = await context.push<Customer>(
            '/customers/new?quick=1&phone=${Uri.encodeQueryComponent(recipient.phone)}',
          );
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
          phone = customer.phone;
        }
        if (!context.mounted) return;
        await _sendWhatsappReceipt(context, sale, phone, shopName);
      case _ReceiptAction.noReceipt:
        context.read<BillingBloc>().add(ClearCartEvent());
        context.go('/');
    }
  }

  Future<_WhatsappRecipient?> _requestWhatsappRecipient(
    BuildContext context, {
    required String initialPhone,
    required bool allowRegistration,
  }) async {
    final formKey = GlobalKey<FormState>();
    final phoneController = TextEditingController(text: initialPhone);
    try {
      return await showDialog<_WhatsappRecipient>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Enviar por WhatsApp'),
          content: Form(
            key: formKey,
            child: TextFormField(
              controller: phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Número de WhatsApp',
                hintText: 'Código de país + número',
                prefixIcon: Icon(Icons.phone_outlined),
              ),
              validator: (value) {
                final digits = (value ?? '').replaceAll(RegExp(r'\D'), '');
                return digits.length >= 8
                    ? null
                    : 'Escribe un número válido con código de país.';
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            if (allowRegistration)
              OutlinedButton(
                onPressed: () {
                  if (!formKey.currentState!.validate()) return;
                  Navigator.pop(
                    dialogContext,
                    _WhatsappRecipient(
                      phone: phoneController.text.trim(),
                      registerCustomer: true,
                    ),
                  );
                },
                child: const Text('Registrar cliente'),
              ),
            FilledButton(
              onPressed: () {
                if (!formKey.currentState!.validate()) return;
                Navigator.pop(
                  dialogContext,
                  _WhatsappRecipient(
                    phone: phoneController.text.trim(),
                    registerCustomer: false,
                  ),
                );
              },
              child: const Text('Continuar'),
            ),
          ],
        ),
      );
    } finally {
      phoneController.dispose();
    }
  }

  Future<void> _sendWhatsappReceipt(
    BuildContext context,
    SaleRecord sale,
    String phone,
    String shopName,
  ) async {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El número de WhatsApp no es válido.')),
      );
      return;
    }
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
      ..write(
        'TOTAL: ${AppCurrency.format(sale.total, code: sale.currencyCode)}',
      );

    final uri = Uri.https('wa.me', '/$digits', {'text': message.toString()});
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!context.mounted) return;
      if (!opened) {
        await _shareReceipt(context, message.toString());
      } else {
        context.read<BillingBloc>().add(ClearCartEvent());
        context.go('/');
      }
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo abrir WhatsApp: $error. Usa compartir.'),
          action: SnackBarAction(
            label: 'Compartir',
            onPressed: () {
              unawaited(_shareReceipt(context, message.toString()));
            },
          ),
        ),
      );
    }
  }

  Future<void> _shareReceipt(BuildContext context, String message) async {
    try {
      await SharePlus.instance.share(
        ShareParams(text: message, subject: 'Comprobante de compra'),
      );
      if (!context.mounted) return;
      context.read<BillingBloc>().add(ClearCartEvent());
      context.go('/');
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo compartir el comprobante: $error')),
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

enum _ReceiptAction { print, whatsapp, noReceipt }

class _WhatsappRecipient {
  final String phone;
  final bool registerCustomer;

  const _WhatsappRecipient({
    required this.phone,
    required this.registerCustomer,
  });
}

class _ReceiptPreviewDialog extends StatelessWidget {
  final SaleRecord sale;
  final String shopName;
  final String address;
  final String shopPhone;
  final String? logoData;
  final String footer;

  const _ReceiptPreviewDialog({
    required this.sale,
    required this.shopName,
    required this.address,
    required this.shopPhone,
    required this.logoData,
    required this.footer,
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
              if (sale.customerName != null)
                Text(
                  'Cliente: ${sale.customerName}',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
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
