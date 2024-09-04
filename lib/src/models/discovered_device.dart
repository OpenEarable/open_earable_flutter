import 'dart:typed_data';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart'
    as flutter_reactive_ble;

class DiscoveredDevice {
  /// The unique identifier of the device.
  final String id;
  final String name;
  // final Map<String, Uint8List> serviceData;

  /// Advertised services
  final List<String> serviceUuids;

  /// Manufacturer specific data. The first 2 bytes are the Company Identifier Codes.
  final Uint8List manufacturerData;

  final int rssi;

  const DiscoveredDevice({
    required this.id,
    required this.name,
    // required this.serviceData,
    required this.manufacturerData,
    required this.rssi,
    required this.serviceUuids,
  });

  factory DiscoveredDevice.fromReactiveBle(
      flutter_reactive_ble.DiscoveredDevice flutterBleDevice) {
    List<String> serviceUuids =
        flutterBleDevice.serviceUuids.map((e) => e.toString()).toList();

    return DiscoveredDevice(
      id: flutterBleDevice.id,
      name: flutterBleDevice.name,
      // serviceData: serviceData,
      manufacturerData: flutterBleDevice.manufacturerData,
      rssi: flutterBleDevice.rssi,
      serviceUuids: serviceUuids,
    );
  }
}
