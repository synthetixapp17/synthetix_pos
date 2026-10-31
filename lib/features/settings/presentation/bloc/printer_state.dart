import 'package:equatable/equatable.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

enum PrinterStatus {
  initial,
  scanning,
  scanSuccess,
  scanFailure,
  connecting,
  connected,
  connectionFailure,
  disconnected,
  testPrinting,
  testPrintFailure,
}

class PrinterState extends Equatable {
  final PrinterStatus status;
  final String? connectedMac;
  final String? connectedName;
  final List<BluetoothInfo> devices;
  final String? errorMessage;

  const PrinterState({
    this.status = PrinterStatus.initial,
    this.connectedMac,
    this.connectedName,
    this.devices = const [],
    this.errorMessage,
  });

  PrinterState copyWith({
    PrinterStatus? status,
    String? connectedMac,
    String? connectedName,
    List<BluetoothInfo>? devices,
    String? errorMessage,
    bool clearError = false,
    bool clearConnection = false,
  }) {
    return PrinterState(
      status: status ?? this.status,
      connectedMac: clearConnection ? null : connectedMac ?? this.connectedMac,
      connectedName: clearConnection
          ? null
          : connectedName ?? this.connectedName,
      devices: devices ?? this.devices,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  List<Object?> get props => [
    status,
    connectedMac,
    connectedName,
    devices,
    errorMessage,
  ];
}
