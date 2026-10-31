import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/utils/printer_helper.dart';
import '../../domain/repositories/printer_repository.dart';
import 'printer_event.dart';
import 'printer_state.dart';

class PrinterBloc extends Bloc<PrinterEvent, PrinterState> {
  final PrinterRepository repository;

  PrinterBloc({required this.repository}) : super(const PrinterState()) {
    on<InitPrinterEvent>(_onInit);
    on<RefreshPrinterEvent>(_onRefresh);
    on<ScanPrintersEvent>(_onScan);
    on<ConnectPrinterEvent>(_onConnect);
    on<DisconnectPrinterEvent>(_onDisconnect);
    on<TestPrintEvent>(_onTestPrint);
  }

  Future<void> _onInit(
    InitPrinterEvent event,
    Emitter<PrinterState> emit,
  ) async {
    final mac = repository.getSavedPrinterMac();
    final name = repository.getSavedPrinterName();
    if (mac == null) {
      emit(
        const PrinterState(
          status: PrinterStatus.disconnected,
          errorMessage: null,
        ),
      );
      return;
    }

    emit(
      state.copyWith(
        status: PrinterStatus.connecting,
        connectedMac: mac,
        connectedName: name,
        clearError: true,
      ),
    );
    try {
      final connected =
          await repository.isConnected() || await repository.connect(mac);
      if (connected) {
        emit(
          state.copyWith(
            status: PrinterStatus.connected,
            connectedMac: mac,
            connectedName: name,
            clearError: true,
          ),
        );
      } else {
        emit(
          state.copyWith(
            status: PrinterStatus.connectionFailure,
            connectedMac: mac,
            connectedName: name,
            errorMessage:
                'No se pudo reconectar con la impresora guardada. Comprueba que esté encendida y vinculada.',
          ),
        );
      }
    } catch (error) {
      emit(
        state.copyWith(
          status: PrinterStatus.connectionFailure,
          connectedMac: mac,
          connectedName: name,
          errorMessage: _localizedError(error),
        ),
      );
    }
  }

  Future<void> _onRefresh(
    RefreshPrinterEvent event,
    Emitter<PrinterState> emit,
  ) async {
    await _scan(emit);
  }

  Future<void> _onScan(
    ScanPrintersEvent event,
    Emitter<PrinterState> emit,
  ) async {
    await _scan(emit);
  }

  Future<void> _scan(Emitter<PrinterState> emit) async {
    emit(state.copyWith(status: PrinterStatus.scanning, clearError: true));
    try {
      final devices = await repository.scanDevices();
      final connectionActive = await repository.isConnected();
      if (devices.isEmpty) {
        emit(
          state.copyWith(
            status: connectionActive
                ? PrinterStatus.connected
                : PrinterStatus.scanSuccess,
            errorMessage:
                'No se encontraron impresoras vinculadas. Vincula una impresora en los ajustes de Bluetooth y vuelve a buscar.',
            devices: [],
          ),
        );
        return;
      }
      emit(
        state.copyWith(
          status: connectionActive
              ? PrinterStatus.connected
              : PrinterStatus.scanSuccess,
          devices: devices,
          clearError: true,
        ),
      );
    } catch (error) {
      emit(
        state.copyWith(
          status: PrinterStatus.scanFailure,
          errorMessage: _localizedError(error),
        ),
      );
    }
  }

  Future<void> _onConnect(
    ConnectPrinterEvent event,
    Emitter<PrinterState> emit,
  ) async {
    emit(state.copyWith(status: PrinterStatus.connecting, clearError: true));
    try {
      final success = await repository.connect(event.mac);
      if (!success || !await repository.isConnected()) {
        emit(
          state.copyWith(
            status: PrinterStatus.connectionFailure,
            errorMessage:
                'No se pudo conectar. Verifica que la impresora esté encendida y vinculada.',
          ),
        );
        return;
      }
      await repository.savePrinterData(event.mac, event.name);
      emit(
        state.copyWith(
          status: PrinterStatus.connected,
          connectedMac: event.mac,
          connectedName: event.name,
          clearError: true,
        ),
      );
    } catch (error) {
      emit(
        state.copyWith(
          status: PrinterStatus.connectionFailure,
          errorMessage: _localizedError(error),
        ),
      );
    }
  }

  Future<void> _onDisconnect(
    DisconnectPrinterEvent event,
    Emitter<PrinterState> emit,
  ) async {
    try {
      final disconnected = await repository.disconnect();
      if (!disconnected) {
        emit(
          state.copyWith(
            status: PrinterStatus.connectionFailure,
            errorMessage: 'No se pudo desconectar la impresora.',
          ),
        );
        return;
      }
      await repository.clearPrinterData();
      emit(
        PrinterState(
          status: PrinterStatus.disconnected,
          devices: state.devices,
        ),
      );
    } catch (error) {
      emit(
        state.copyWith(
          status: PrinterStatus.connectionFailure,
          errorMessage: _localizedError(error),
        ),
      );
    }
  }

  Future<void> _onTestPrint(
    TestPrintEvent event,
    Emitter<PrinterState> emit,
  ) async {
    emit(state.copyWith(status: PrinterStatus.testPrinting, clearError: true));
    try {
      await repository.testPrint(event.shopName);
      final stillConnected = await repository.isConnected();
      emit(
        state.copyWith(
          status: stillConnected
              ? PrinterStatus.connected
              : PrinterStatus.disconnected,
          errorMessage: stillConnected
              ? null
              : 'La impresora se desconectó después de la prueba.',
          clearError: stillConnected,
        ),
      );
    } catch (error) {
      var stillConnected = false;
      String? connectionError;
      try {
        stillConnected = await repository.isConnected();
      } catch (checkError) {
        connectionError = _localizedError(checkError);
      }
      emit(
        state.copyWith(
          status: stillConnected
              ? PrinterStatus.connected
              : PrinterStatus.testPrintFailure,
          errorMessage: connectionError == null
              ? _localizedError(error)
              : '${_localizedError(error)} $connectionError',
        ),
      );
    }
  }

  String _localizedError(Object error) {
    if (error is PrinterException) return error.message;
    return 'Ocurrió un error al comunicarse con la impresora. '
        'Comprueba Bluetooth y vuelve a intentarlo.';
  }
}
