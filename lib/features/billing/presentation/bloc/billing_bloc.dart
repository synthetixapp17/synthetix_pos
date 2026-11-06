import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import '../../../../core/services/sound_service.dart';
import '../../domain/entities/cart_item.dart';
import 'package:billing_app/features/product/domain/entities/product.dart';
import 'package:billing_app/features/product/domain/usecases/product_usecases.dart';
import '../../../../core/utils/printer_helper.dart';
import '../../../../core/data/hive_database.dart';
import '../../../customer/domain/entities/customer.dart';
import '../../../reports/domain/entities/sale_record.dart';
import '../../../reports/domain/usecases/reports_usecases.dart';
import 'package:uuid/uuid.dart';

part 'billing_event.dart';
part 'billing_state.dart';

class BillingBloc extends Bloc<BillingEvent, BillingState> {
  final GetProductByBarcodeUseCase getProductByBarcodeUseCase;
  final RecordSaleUseCase? recordSaleUseCase;
  final Future<void> Function() _playCartAddSound;

  BillingBloc({
    required this.getProductByBarcodeUseCase,
    this.recordSaleUseCase,
    Future<void> Function()? playCartAddSound,
  }) : _playCartAddSound =
           playCartAddSound ?? SoundService.instance.playScanSound,
       super(const BillingState()) {
    on<ScanBarcodeEvent>(_onScanBarcode);
    on<AddProductToCartEvent>(_onAddProductToCart);
    on<RemoveProductFromCartEvent>(_onRemoveProductFromCart);
    on<UpdateQuantityEvent>(_onUpdateQuantity);
    on<ClearCartEvent>(_onClearCart);
    on<CompleteSaleEvent>(_onCompleteSale);
    on<UpdateSaleCustomerEvent>(_onUpdateSaleCustomer);
    on<PrintReceiptEvent>(_onPrintReceipt);
    on<SelectCustomerEvent>(_onSelectCustomer);
  }

  Future<void> _onScanBarcode(
    ScanBarcodeEvent event,
    Emitter<BillingState> emit,
  ) async {
    final result = await getProductByBarcodeUseCase(event.barcode);
    result.fold(
      (failure) => emit(
        state.copyWith(
          error: 'No se encontró un producto con el código ${event.barcode}.',
        ),
      ),
      (product) {
        add(AddProductToCartEvent(product));
      },
    );
  }

  Future<void> _onAddProductToCart(
    AddProductToCartEvent event,
    Emitter<BillingState> emit,
  ) async {
    if (event.product.stock <= 0) {
      emit(
        state.copyWith(
          error: 'No hay existencias disponibles de "${event.product.name}".',
        ),
      );
      return;
    }
    if (state.cartItems.isNotEmpty &&
        state.cartItems.first.product.currencyCode !=
            event.product.currencyCode) {
      emit(
        state.copyWith(
          error:
              'No se pueden mezclar monedas distintas en una misma venta. Finaliza esta venta antes de agregar productos en otra moneda.',
        ),
      );
      return;
    }
    // Clear error when adding
    final cleanState = state.copyWith(error: null);

    final existingIndex = cleanState.cartItems.indexWhere(
      (item) => item.product.id == event.product.id,
    );
    if (existingIndex >= 0) {
      final existingItem = cleanState.cartItems[existingIndex];
      if (existingItem.quantity >= event.product.stock) {
        final stockMessage = event.product.stock == 1
            ? 'Solo hay 1 unidad disponible'
            : 'Solo hay ${event.product.stock} unidades disponibles';
        emit(
          cleanState.copyWith(
            error:
                '$stockMessage de '
                '"${event.product.name}".',
          ),
        );
        return;
      }
      final backendItems = List<CartItem>.from(cleanState.cartItems);
      backendItems[existingIndex] = existingItem.copyWith(
        quantity: existingItem.quantity + 1,
      );
      emit(
        cleanState.copyWith(
          cartItems: backendItems,
          error: null,
          saleRecorded: false,
          clearCompletedSale: true,
        ),
      );
      await _playCartAddSound();
    } else {
      final newItem = CartItem(product: event.product);
      emit(
        cleanState.copyWith(
          cartItems: [...cleanState.cartItems, newItem],
          error: null,
          saleRecorded: false,
          clearCompletedSale: true,
        ),
      );
      await _playCartAddSound();
    }
  }

  void _onRemoveProductFromCart(
    RemoveProductFromCartEvent event,
    Emitter<BillingState> emit,
  ) {
    final updatedList = state.cartItems
        .where((item) => item.product.id != event.productId)
        .toList();
    emit(
      state.copyWith(
        cartItems: updatedList,
        saleRecorded: false,
        clearCompletedSale: true,
      ),
    );
  }

  void _onUpdateQuantity(
    UpdateQuantityEvent event,
    Emitter<BillingState> emit,
  ) {
    if (event.quantity <= 0) {
      add(RemoveProductFromCartEvent(event.productId));
      return;
    }

    final index = state.cartItems.indexWhere(
      (item) => item.product.id == event.productId,
    );
    if (index >= 0) {
      final currentItem = state.cartItems[index];
      if (event.quantity > currentItem.product.stock) {
        emit(
          state.copyWith(
            error:
                'La cantidad supera la existencia disponible '
                '(${currentItem.product.stock}).',
          ),
        );
        return;
      }
      final items = List<CartItem>.from(state.cartItems);
      items[index] = items[index].copyWith(quantity: event.quantity);
      emit(
        state.copyWith(
          cartItems: items,
          saleRecorded: false,
          clearCompletedSale: true,
        ),
      );
    }
  }

  void _onClearCart(ClearCartEvent event, Emitter<BillingState> emit) {
    emit(const BillingState());
  }

  Future<void> _onCompleteSale(
    CompleteSaleEvent event,
    Emitter<BillingState> emit,
  ) async {
    if (state.cartItems.isEmpty) {
      emit(
        state.copyWith(error: 'Agrega productos antes de finalizar la venta.'),
      );
      return;
    }
    if (state.saleRecorded || state.isSavingSale) return;
    if (recordSaleUseCase == null) {
      emit(
        state.copyWith(
          error:
              'No se pudo guardar la venta porque el almacenamiento no está disponible.',
        ),
      );
      return;
    }
    if (!event.exchangeRate.isFinite || event.exchangeRate <= 0) {
      emit(
        state.copyWith(error: 'La tasa de cambio configurada no es válida.'),
      );
      return;
    }
    final saleTotal = state.totalAmount * event.exchangeRate;
    if (!saleTotal.isFinite) {
      emit(
        state.copyWith(error: 'El total convertido de la venta no es válido.'),
      );
      return;
    }
    final isCashPayment =
        !event.isCreditSale && event.paymentMethod.toLowerCase() == 'efectivo';
    if (isCashPayment &&
        (!event.amountTendered.isFinite ||
            event.amountTendered + 0.000001 < saleTotal)) {
      emit(
        state.copyWith(
          error:
              'El efectivo recibido debe ser igual o mayor al total de la venta.',
        ),
      );
      return;
    }
    final amountTendered = isCashPayment ? event.amountTendered : 0.0;

    emit(state.copyWith(isSavingSale: true, clearError: true));
    final sale = SaleRecord(
      id: const Uuid().v4(),
      soldAt: DateTime.now(),
      total: saleTotal,
      totalInCurrency: saleTotal,
      exchangeRate: event.exchangeRate,
      customerId: state.customer?.id,
      customerName: state.customer?.name,
      currencyCode:
          event.currencyCode ?? state.cartItems.first.product.currencyCode,
      paymentMethod: event.paymentMethod,
      amountTendered: amountTendered,
      changeAmount: (amountTendered - saleTotal)
          .clamp(0.0, double.infinity)
          .toDouble(),
      lines: state.cartItems
          .map(
            (item) => SaleLine(
              productId: item.product.id,
              productName: item.product.name,
              quantity: item.quantity,
              unitPrice: item.product.price * event.exchangeRate,
              category: item.product.category,
              barcode: item.product.barcode,
            ),
          )
          .toList(),
    );

    try {
      final result = await recordSaleUseCase!(sale);
      result.fold(
        (failure) => emit(
          state.copyWith(
            isSavingSale: false,
            error: 'No se pudo guardar la venta: ${failure.message}',
          ),
        ),
        (_) => emit(
          state.copyWith(
            isSavingSale: false,
            saleRecorded: true,
            completedSale: sale,
          ),
        ),
      );
    } catch (error) {
      emit(
        state.copyWith(
          isSavingSale: false,
          error: 'No se pudo guardar la venta: $error',
        ),
      );
    }
  }

  Future<void> _onUpdateSaleCustomer(
    UpdateSaleCustomerEvent event,
    Emitter<BillingState> emit,
  ) async {
    final sale = state.completedSale;
    if (sale == null || recordSaleUseCase == null) {
      emit(
        state.copyWith(error: 'No se pudo asociar el cliente a esta venta.'),
      );
      return;
    }
    emit(state.copyWith(clearError: true));

    final updatedSale = SaleRecord(
      id: sale.id,
      soldAt: sale.soldAt,
      total: sale.total,
      totalInCurrency: sale.totalInCurrency,
      exchangeRate: sale.exchangeRate,
      customerId: event.customer.id,
      customerName: event.customer.name,
      currencyCode: sale.currencyCode,
      paymentMethod: sale.paymentMethod,
      amountTendered: sale.amountTendered,
      changeAmount: sale.changeAmount,
      lines: sale.lines,
    );
    final result = await recordSaleUseCase!(updatedSale);
    result.fold(
      (failure) => emit(
        state.copyWith(
          error: 'No se pudo asociar el cliente a la venta: ${failure.message}',
        ),
      ),
      (_) => emit(
        state.copyWith(
          customer: event.customer,
          completedSale: updatedSale,
          clearError: true,
        ),
      ),
    );
  }

  void _onSelectCustomer(
    SelectCustomerEvent event,
    Emitter<BillingState> emit,
  ) {
    emit(
      state.copyWith(
        customer: event.customer,
        clearCustomer: event.customer == null,
      ),
    );
  }

  Future<void> _onPrintReceipt(
    PrintReceiptEvent event,
    Emitter<BillingState> emit,
  ) async {
    final printerHelper = PrinterHelper();
    emit(
      state.copyWith(isPrinting: true, printSuccess: false, clearError: true),
    );

    try {
      if (!await printerHelper.checkConnection()) {
        final savedMac = HiveDatabase.settingsBox.get('printer_mac');
        if (savedMac == null) {
          throw const PrinterException(
            'La impresora no está conectada y no hay una impresora guardada.',
          );
        }
        if (!await printerHelper.connect(savedMac)) {
          throw const PrinterException(
            'No se pudo conectar automáticamente con la impresora. '
            'Comprueba que esté encendida y vinculada.',
          );
        }
      }

      final items = state.cartItems
          .map(
            (item) => {
              'name': item.product.name,
              'qty': item.quantity,
              'price': item.product.price * event.exchangeRate,
              'total': item.total * event.exchangeRate,
              'barcode': item.product.barcode,
            },
          )
          .toList();

      final printed = await printerHelper.printReceipt(
        shopName: event.shopName,
        address1: event.address1,
        address2: event.address2,
        phone: event.phone,
        rif: event.rif,
        qrData: event.qrData,
        customerName: event.customerName,
        logoData: event.logoData,
        items: items,
        total: state.totalAmount * event.exchangeRate,
        footer: event.footer,
        currencyCode: event.currencyCode,
        paymentMethod: event.paymentMethod,
        amountTendered: event.amountTendered,
        changeAmount: event.changeAmount,
        showAddress: event.showAddress,
        showPhone: event.showPhone,
        showRif: event.showRif,
        showInvoiceQr: event.showInvoiceQr,
        showDate: event.showDate,
        showBarcode: event.showBarcode,
        showUnitPrices: event.showUnitPrices,
      );
      if (!printed) {
        throw const PrinterException(
          'No se confirmó la impresión del ticket. La venta permanece guardada.',
        );
      }

      emit(state.copyWith(isPrinting: false, printSuccess: true));
    } catch (e) {
      emit(
        state.copyWith(
          isPrinting: false,
          error: e is PrinterException
              ? e.message
              : 'No se pudo imprimir el recibo. Comprueba la impresora y vuelve a intentarlo.',
          clearError: false,
        ),
      );
    }
  }
}
