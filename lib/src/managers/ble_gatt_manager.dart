/// An interface for managing Bluetooth Low Energy (BLE) GATT operations.
abstract class BleGattManager {
  /// Check if a device is connected.
  bool isConnected(String deviceId);

  /// Checks if a specific service is available on the connected device.
  Future<bool> hasService({
    required String deviceId,
    required String serviceId,
  });

  Future<bool> hasCharacteristic({
    required String deviceId,
    required String serviceId,
    required String characteristicId,
  });

  /// Writes byte data to a specific characteristic of a device.
  Future<void> write({
    required String deviceId,
    required String serviceId,
    required String characteristicId,
    required List<int> byteData,
  });

  /// Subscribes to a specific characteristic of the connected device.
  Stream<List<int>> subscribe({
    required String deviceId,
    required String serviceId,
    required String characteristicId,
  });

  /// Reads data from a specific characteristic of the connected device.
  Future<List<int>> read({
    required String deviceId,
    required String serviceId,
    required String characteristicId,
  });

  /// Disconnects from a device.
  Future<void> disconnect(String deviceId);
}
