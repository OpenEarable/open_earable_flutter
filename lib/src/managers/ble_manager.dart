part of open_earable_flutter;

/// A class that establishes and manages Bluetooth Low Energy (BLE)
/// communication with OpenEarable devices.
class BleManager {
  int mtu = 60; // Largest Byte package sent is 42 bytes for IMU

  final Map<String, List<StreamController<List<int>>>> _streamControllers = {};

  /// A stream of discovered devices during scanning.
  Stream<DiscoveredDevice> get scanStream => _scanStream;
  late Stream<DiscoveredDevice> _scanStream;
  StreamController<DiscoveredDevice>? _scanStreamController;

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

  final StreamController<bool> _connectionStateController =
      StreamController<bool>.broadcast();

  Stream<bool> get connectionStateStream => _connectionStateController.stream;

  String _getCharacteristicKey(String deviceId, String characteristicId) =>
      "$deviceId||$characteristicId";

  bool _inited = false;

  void _init() {
    if (_inited) {
      return;
    }
    _inited = true;

    UniversalBle.onValueChange = (
      String deviceId,
      String characteristicId,
      Uint8List value,
    ) {
      String streamIdentifier =
          _getCharacteristicKey(deviceId, characteristicId);
      if (!_streamControllers.containsKey(streamIdentifier)) {
        return;
      }
      for (var e in _streamControllers[streamIdentifier]!) {
        e.add(value);
      }
    };
  }

  /// Initiates the BLE device scan to discover nearby Bluetooth devices.
  Future<void> startScan() async {
    _init();

    // The example code does not await this function before getting `scanStream`.
    // Because of this, we need to set the stream early for keeping the behavior
    // before switching the bluetooth lib
    StreamController<DiscoveredDevice>? oldController = _scanStreamController;
    _scanStreamController = StreamController<DiscoveredDevice>();
    _scanStream = _scanStreamController!.stream;
    if (oldController != null) {
      await oldController.close();
    }

    bool permGranted = false;
    // Don't run `Platform.is*` on web
    if (!kIsWeb && Platform.isAndroid) {
      Map<Permission, PermissionStatus> statuses = await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.location,
      ].request();

      permGranted = (statuses[Permission.bluetoothScan]!.isGranted &&
          statuses[Permission.bluetoothConnect]!.isGranted &&
          statuses[Permission.location]!.isGranted);
    } else {
      permGranted = true;
    }

    if (permGranted) {
      for (int i = 0;
          // Run this two times on MacOS if it's the first run.
          // Needed on MacOS on an M1 Pro.
          i < ((!kIsWeb && Platform.isMacOS && oldController == null) ? 2 : 1);
          ++i) {
        // Sleep before the second run
        if (i == 1) {
          await Future.delayed(const Duration(milliseconds: 200));
        }

        await UniversalBle.stopScan();

        UniversalBle.onScanResult = (bleDevice) {
          _scanStreamController?.add(DiscoveredDevice(
            id: bleDevice.deviceId,
            name: bleDevice.name ?? "",
            manufacturerData:
                bleDevice.manufacturerData ?? Uint8List.fromList([]),
            rssi: bleDevice.rssi ?? -1,
            serviceUuids: bleDevice.services,
          ));
        };

        await UniversalBle.startScan(
          scanFilter: ScanFilter(
            // Needs to be passed for web, can be empty for the rest
            withServices: kIsWeb ? allUuids : [],
          ),
        );
      }
    }
  }

  /// Connects to the specified Earable device.
  connectToDevice(DiscoveredDevice device) {
    for (var list in _streamControllers.values) {
      for (var e in list) {
        e.close();
      }
    }
    _connectingDevice = device;

    UniversalBle.onConnectionChange = (String deviceId, bool isConnected) {};

    _retryConnection(2, device);
  }

  void _retryConnection(
    int retries,
    DiscoveredDevice device,
  ) {
    if (retries <= 0) {
      _connectingDevice = null;
      return;
    }
    UniversalBle.onConnectionChange =
        (String deviceId, bool isConnected) async {
      if (device.id != deviceId) {
        return;
      }

      if (isConnected) {
        _connectedDevice = device;
        if (!kIsWeb) {
          UniversalBle.requestMtu(device.id, mtu);
        }
        UniversalBle.discoverServices(device.id);
        if (deviceIdentifier == null || deviceFirmwareVersion == null) {
          await readDeviceIdentifier();
          await readDeviceFirmwareVersion();
          await readDeviceHardwareVersion();
        }
        _connectionStateController.add(true);
        _connectingDevice = null;
      } else {
        _connectedDevice = null;
        _connectingDevice = null;
        _deviceIdentifier = null;
        _deviceFirmwareVersion = null;
        _deviceHardwareVersion = null;
        _connectionStateController.add(false);
        _retryConnection(retries - 1, device);
      }
    };
    UniversalBle.connect(device.id);
  }

  /// Writes byte data to a specific characteristic of the connected Earable device.
  Future<void> write({
    required String serviceId,
    required String characteristicId,
    required List<int> byteData,
  }) async {
    if (_connectedDevice == null) {
      throw Exception("Write failed because no Earable is connected");
    }
    await UniversalBle.writeValue(
      _connectedDevice!.id,
      serviceId,
      characteristicId,
      Uint8List.fromList(byteData),
      BleOutputProperty.withResponse,
    );
  }

  /// Subscribes to a specific characteristic of the connected Earable device.
  Stream<List<int>> subscribe({
    required String serviceId,
    required String characteristicId,
  }) {
    _init();
    if (_connectedDevice == null) {
      throw Exception("Subscribing failed because no Earable is connected");
    }

    final streamController = StreamController<List<int>>();
    String streamIdentifier =
        _getCharacteristicKey(_connectedDevice!.id, characteristicId);
    if (!_streamControllers.containsKey(streamIdentifier)) {
      UniversalBle.setNotifiable(
        _connectedDevice!.id,
        serviceId,
        characteristicId,
        BleInputProperty.notification,
      );
      _streamControllers[streamIdentifier] = [streamController];
    } else {
      _streamControllers[streamIdentifier]!.add(streamController);
    }

    streamController.onCancel = () {
      if (_streamControllers.containsKey(streamIdentifier)) {
        _streamControllers[streamIdentifier]!.remove(streamController);
        if (_streamControllers[streamIdentifier]!.isEmpty) {
          UniversalBle.setNotifiable(
            _connectedDevice!.id,
            serviceId,
            characteristicId,
            BleInputProperty.disabled,
          );
          _streamControllers.remove(streamIdentifier);
        }
      }
    };

    return streamController.stream;
  }

  /// Reads data from a specific characteristic of the connected Earable device.
  Future<List<int>> read({
    required String serviceId,
    required String characteristicId,
  }) async {
    if (_connectedDevice == null) {
      throw Exception("Read failed because no Earable is connected");
    }

    final response = await UniversalBle.readValue(
      _connectedDevice!.id,
      serviceId,
      characteristicId,
    );
    return response.toList();
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
    UniversalBle.onConnectionChange = (String deviceId, bool isConnected) {};
    UniversalBle.stopScan();
    UniversalBle.onScanResult = (_) {};
    _scanStreamController?.close();

    for (var list in _streamControllers.values) {
      for (var e in list) {
        e.close();
      }
    }
  }
}
