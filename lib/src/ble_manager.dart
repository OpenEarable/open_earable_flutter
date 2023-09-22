part of open_earable_flutter;

/// A class that establishes and manages Bluetooth Low Energy (BLE)
/// communication with OpenEarable devices.
class BleManager {
  FlutterReactiveBle _flutterReactiveBle = FlutterReactiveBle();

  /// Indicates whether the manager is currently connected to a device.
  bool get connected => _connected;
  bool _connected = false;

  /// A stream of discovered devices during scanning.
  Stream<DiscoveredDevice> get scanStream => _scanStream;
  late Stream<DiscoveredDevice> _scanStream;

  /// The currently connected device.
  DiscoveredDevice? get connectedDevice => _connectedDevice;
  DiscoveredDevice? _connectedDevice;

  late Stream<ConnectionStateUpdate> _connectionEventStream;

  final StreamController<bool> _connectionStateController =
      StreamController<bool>.broadcast();
  Stream<bool> get connectionStateStream => _connectionStateController.stream;

  /// Initiates the BLE device scan to discover nearby Bluetooth devices.
  void startScan() async {
    _flutterReactiveBle = FlutterReactiveBle();
    bool permGranted = false;
    PermissionStatus permission;
    if (Platform.isAndroid) {
      permission = await Permission.location.request();
      if (permission == PermissionStatus.granted) permGranted = true;
    } else if (Platform.isIOS) {
      permGranted = true;
    }

    if (permGranted) {
      _scanStream = _flutterReactiveBle.scanForDevices(withServices: []);
    }
  }

  /// Connects to the specified Earable device.
  connectToDevice(DiscoveredDevice device) {
    _connectedDevice = device;
    _connectionEventStream = _flutterReactiveBle.connectToAdvertisingDevice(
        id: device.id,
        prescanDuration: const Duration(seconds: 1),
        withServices: [sensorServiceUuid]);
    _connectionEventStream.listen((event) {
      switch (event.connectionState) {
        case DeviceConnectionState.connected:
          {
            _connected = true;
            _connectionStateController.add(true);
          }
        default:
          {
            _connected = false;
            _connectionStateController.add(false);
          }
      }
    });
  }

  /// Writes byte data to a specific characteristic of the connected Earable device.
  Future<void> write(
      {required Uuid serviceId,
      required Uuid characteristicId,
      required List<int> byteData}) async {
    if (!_connected) {
      Exception("Write failed because no Earable is connected");
    }
    final characteristic = QualifiedCharacteristic(
        serviceId: sensorServiceUuid,
        characteristicId: sensorConfigurationCharacteristicUuid,
        deviceId: _connectedDevice!.id);
    await _flutterReactiveBle.writeCharacteristicWithResponse(
      characteristic,
      value: byteData,
    );
  }

  /// Subscribes to a specific characteristic of the connected Earable device.
  Stream<List<int>> subscribe(
      {required Uuid serviceId, required Uuid characteristicId}) {
    if (!_connected) {
      Exception("Subscribing failed because no Earable is connected");
    }
    final characteristic = QualifiedCharacteristic(
        serviceId: serviceId,
        characteristicId: characteristicId,
        deviceId: _connectedDevice!.id);
    return _flutterReactiveBle.subscribeToCharacteristic(characteristic);
  }

  /// Reads data from a specific characteristic of the connected Earable device.
  Future<List<int>> read(
      {required Uuid serviceId, required Uuid characteristicId}) async {
    if (!_connected) {
      Exception("Read failed because no Earable is connected");
    }
    final characteristic = QualifiedCharacteristic(
        serviceId: serviceId,
        characteristicId: characteristicId,
        deviceId: _connectedDevice!.id);
    final response =
        await _flutterReactiveBle.readCharacteristic(characteristic);
    return response;
  }
}
