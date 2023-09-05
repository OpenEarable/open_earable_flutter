part of open_earable_flutter;

class BleManager {
  final FlutterReactiveBle flutterReactiveBle = FlutterReactiveBle();
  late String deviceName;

  // Some state management stuff
  bool _foundDeviceWaitingToConnect = false;
  bool _scanStarted = false;
  bool _connected = false;
  // Bluetooth related variables
  late DiscoveredDevice discoveredDevice;
  late Stream<DiscoveredDevice> _scanStream;
  Stream<DiscoveredDevice> get scanStream => _scanStream;
  late Stream<ConnectionStateUpdate> _currentConnectionStream;
  Stream<ConnectionStateUpdate> get currentConnectionStream =>
      _currentConnectionStream;
  late QualifiedCharacteristic _rxCharacteristic;

  Future<Stream<DiscoveredDevice>> startScan() async {
    bool permGranted = false;
    //setState
    _scanStarted = true;
    PermissionStatus permission;
    if (Platform.isAndroid) {
      permission = await Location().requestPermission();
      if (permission == PermissionStatus.granted) permGranted = true;
    } else if (Platform.isIOS) {
      permGranted = true;
    }

    if (permGranted) {
      _scanStream =
          flutterReactiveBle.scanForDevices(withServices: [sensorServiceUuid]);
    }
    return _scanStream;
    /*
    if (permGranted) {
      _scanStream = flutterReactiveBle
          .scanForDevices(withServices: [sensorServiceUuid]).listen((device) {
        if (device.name == deviceName) {
          // setState
          discoveredDevice = device;
          _foundDeviceWaitingToConnect = true;
        }
      });
    }
    */
  }

  void connectToDevice(DiscoveredDevice device) {
    discoveredDevice = device;
    _foundDeviceWaitingToConnect = true;
    //_scanStream.cancel();
    // Listen to connection state
    Stream<ConnectionStateUpdate> _currentConnectionStream = flutterReactiveBle
        .connectToAdvertisingDevice(
            id: discoveredDevice.id,
            prescanDuration: const Duration(seconds: 1),
            withServices: [sensorServiceUuid]);
    _currentConnectionStream.listen((event) {
      switch (event.connectionState) {
        case DeviceConnectionState.connected:
          {
            _rxCharacteristic = QualifiedCharacteristic(
                serviceId: sensorServiceUuid,
                characteristicId: sensorConfigurationCharacteristicUuid,
                deviceId: event.deviceId);
            // setState
            _foundDeviceWaitingToConnect = false;
            _connected = true;

            break;
          }
        // Can add various state state updates on disconnect
        case DeviceConnectionState.disconnected:
          {
            break;
          }
        default:
      }
    });
  }

  void write(
      {required Uuid serviceId,
      required Uuid characteristicId,
      required List<int> value}) async {
    final characteristic = QualifiedCharacteristic(
        serviceId: sensorServiceUuid,
        characteristicId: sensorConfigurationCharacteristicUuid,
        deviceId: discoveredDevice.id);
    await flutterReactiveBle.writeCharacteristicWithResponse(
      characteristic,
      value: value,
    );
  }

  Stream<List<int>> subscribe(
      {required Uuid serviceId, required Uuid characteristicId}) {
    final characteristic = QualifiedCharacteristic(
        serviceId: sensorServiceUuid,
        characteristicId: sensorConfigurationCharacteristicUuid,
        deviceId: discoveredDevice.id);
    return flutterReactiveBle.subscribeToCharacteristic(characteristic);
  }

  Future<String> readString(
      {required Uuid serviceId, required Uuid characteristicId}) async {
    final characteristic = QualifiedCharacteristic(
        serviceId: serviceId,
        characteristicId: characteristicId,
        deviceId: discoveredDevice.id);
    final response =
        await flutterReactiveBle.readCharacteristic(characteristic);
    return String.fromCharCodes(response);
  }
}
