part of open_earable_flutter;

/// A class that establishes and manages Bluetooth Low Energy (BLE)
/// communication with OpenEarable devices.
class BleManager {
  int mtu = 60; // Largest Byte package sent is 42 bytes for IMU
  FlutterReactiveBle _flutterReactiveBle = FlutterReactiveBle();

  /// A stream of discovered devices during scanning.
  Stream<DiscoveredDevice> get scanStream => _scanStream;
  late Stream<DiscoveredDevice> _scanStream;

  /// The device that is currently being connected to.
  DiscoveredDevice? get connectingDevice => _connectingDevice;
  DiscoveredDevice? _connectingDevice;

  /// The currently connected device.
  DiscoveredDevice? get connectedDevice => _connectedDevice;
  DiscoveredDevice? _connectedDevice;

  // Returns false if no device is connected
  bool get connected => _connectedDevice != null;

  /// The info of the currently connected device.
  String? get deviceIdentifier => _deviceIdentifier;
  String? _deviceIdentifier;
  String? get deviceFirmwareVersion => _deviceFirmwareVersion;
  String? _deviceFirmwareVersion;
  String? get deviceHardwareVersion => _deviceHardwareVersion;
  String? _deviceHardwareVersion;

  StreamSubscription? _connectionStateSubscription;

  final StreamController<bool> _connectionStateController =
      StreamController<bool>.broadcast();
  Stream<bool> get connectionStateStream => _connectionStateController.stream;

  /// Initiates the BLE device scan to discover nearby Bluetooth devices.
  Future<void> startScan() async {
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
    _connectingDevice = device;
    _connectionStateController.add(false);

    _connectionStateSubscription?.cancel();

    _connectionStateSubscription = _retryConnection(2, device);
  }

  StreamSubscription? _retryConnection(int retries, DiscoveredDevice device) {
    if (retries <= 0) {
      _connectingDevice = null;
      return null;
    }
    return _flutterReactiveBle
        .connectToAdvertisingDevice(
            id: device.id,
            prescanDuration: const Duration(seconds: 1),
            withServices: [sensorServiceUuid]).listen((event) async {
      switch (event.connectionState) {
        case DeviceConnectionState.connected:
          _connectedDevice = device;
          _flutterReactiveBle.requestMtu(deviceId: device.id, mtu: mtu);
          if (deviceIdentifier == null || deviceFirmwareVersion == null) {
            await readDeviceIdentifier();
            await readDeviceFirmwareVersion();
            await readDeviceHardwareVersion();
          }
          _connectionStateController.add(true);
          _connectingDevice = null;
          return;
        case DeviceConnectionState.disconnected:
          _connectedDevice = null;
          _connectingDevice = null;
          _deviceFirmwareVersion = null;
          _deviceIdentifier = null;
          _connectionStateController.add(false);
        default:
      }
      _connectionStateSubscription = _retryConnection(retries - 1, device);
    });
  }

  /// Writes byte data to a specific characteristic of the connected Earable device.
  Future<void> write(
      {required Uuid serviceId,
      required Uuid characteristicId,
      required List<int> byteData}) async {
    if (_connectedDevice == null) {
      throw Exception("Write failed because no Earable is connected");
    }
    final characteristic = QualifiedCharacteristic(
        serviceId: serviceId,
        characteristicId: characteristicId,
        deviceId: _connectedDevice!.id);
    await _flutterReactiveBle.writeCharacteristicWithResponse(
      characteristic,
      value: byteData,
    );
  }

  /// Subscribes to a specific characteristic of the connected Earable device.
  Stream<List<int>> subscribe(
      {required Uuid serviceId, required Uuid characteristicId}) {
    if (_connectedDevice == null) {
      throw Exception("Subscribing failed because no Earable is connected");
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
    if (_connectedDevice == null) {
      throw Exception("Read failed because no Earable is connected");
    }
    final characteristic = QualifiedCharacteristic(
        serviceId: serviceId,
        characteristicId: characteristicId,
        deviceId: _connectedDevice!.id);
    final response =
        await _flutterReactiveBle.readCharacteristic(characteristic);
    return response;
  }

  /// Reads the device identifier from the connected OpenEarable device.
  ///
  /// Returns a `Future` that completes with the device identifier as a `String`.
  Future<String?> readDeviceIdentifier() async {
    List<int> deviceIdentifierBytes = await read(
        serviceId: deviceInfoServiceUuid,
        characteristicId: deviceIdentifierCharacteristicUuid);
    _deviceIdentifier = String.fromCharCodes(deviceIdentifierBytes);
    return _deviceIdentifier;
  }

  /// Reads the device firmware version from the connected OpenEarable device.
  ///
  /// Returns a `Future` that completes with the device firmware version as a `String`.
  Future<String?> readDeviceFirmwareVersion() async {
    List<int> deviceGenerationBytes = await read(
        serviceId: deviceInfoServiceUuid,
        characteristicId: deviceFirmwareVersionCharacteristicUuid);
    _deviceFirmwareVersion = String.fromCharCodes(deviceGenerationBytes);
    return _deviceFirmwareVersion;
  }

  /// Reads the device hardware version from the connected OpenEarable device.
  ///
  /// Returns a `Future` that completes with the device firmware version as a `String`.
  Future<String?> readDeviceHardwareVersion() async {
    List<int> hardwareGenerationBytes = await read(
        serviceId: deviceInfoServiceUuid,
        characteristicId: deviceHardwareVersionCharacteristicUuid);
    _deviceHardwareVersion = String.fromCharCodes(hardwareGenerationBytes);
    return _deviceHardwareVersion;
  }

  /// Cancel connection state subscription
  dispose() {
    _connectionStateSubscription?.cancel();
  }
}
