import 'dart:typed_data';

class DiscoveredDevice {
  /// The unique identifier of the device.
  final String id;
  final String name;

  /// Advertised services
  final List<String> serviceUuids;

  /// Manufacturer specific data. The first 2 bytes are the Company Identifier Codes.
  final Uint8List manufacturerData;

  final int rssi;

  const DiscoveredDevice({
    required this.id,
    required this.name,
    required this.manufacturerData,
    required this.rssi,
    required this.serviceUuids,
  });
}
