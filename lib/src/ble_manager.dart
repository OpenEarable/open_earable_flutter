part of open_earable_flutter;

class BleManager {
  final FlutterReactiveBle _flutterReactiveBle = FlutterReactiveBle();

  bool _foundDeviceWaitingToConnect = false;
  bool _scanStarted = false;
  bool _connected = false;
  bool get connected => _connected;

  late Stream<DiscoveredDevice> _scanStream;
  Stream<DiscoveredDevice> get scanStream => _scanStream;

  late DiscoveredDevice _connectedDevice;
  DiscoveredDevice get connectedDevice => _connectedDevice;

  late Stream<ConnectionStateUpdate> _currentConnectionStream;
  Stream<ConnectionStateUpdate> get currentConnectionStream =>
      _currentConnectionStream;

  void startScan() async {
    if (_scanStarted) {
      return;
    }
    bool permGranted = false;
    //setState
    _scanStarted = true;
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

  void connectToDevice(DiscoveredDevice device) async {
    _scanStarted = false;
    _currentConnectionStream = _flutterReactiveBle.connectToAdvertisingDevice(
        id: device.id,
        prescanDuration: const Duration(seconds: 1),
        withServices: [sensorServiceUuid]);
    _currentConnectionStream.listen((event) async {
      print(event.connectionState);
      switch (event.connectionState) {
        case DeviceConnectionState.connected:
          {
            _connectedDevice = device;
            await _flutterReactiveBle.discoverAllServices(_connectedDevice.id);
            var services = await _flutterReactiveBle
                .getDiscoveredServices(_connectedDevice.id);
            for (final service in services) {
              print('Service UUID: ${service.id.toString()}');
            }

            _flutterReactiveBle.characteristicValueStream.listen((values) {
              print("characteristic value:");
              print(values);
            });

            // setState
            _foundDeviceWaitingToConnect = false;
            _connected = true;
          }
        case DeviceConnectionState.disconnected:
          {
            _connected = false;
            break;
          }
        default:
      }
    });
  }

  Future<void> write(
      {required Uuid serviceId,
      required Uuid characteristicId,
      required List<int> value}) async {
    final characteristic = QualifiedCharacteristic(
        serviceId: sensorServiceUuid,
        characteristicId: sensorConfigurationCharacteristicUuid,
        deviceId: _connectedDevice.id);
    await _flutterReactiveBle.writeCharacteristicWithResponse(
      characteristic,
      value: value,
    );
  }

  Stream<List<int>> subscribe(
      {required Uuid serviceId, required Uuid characteristicId}) {
    final characteristic = QualifiedCharacteristic(
        serviceId: serviceId,
        characteristicId: characteristicId,
        deviceId: _connectedDevice.id);
    return _flutterReactiveBle.subscribeToCharacteristic(characteristic);
  }

  Future<List<int>> read(
      {required Uuid serviceId, required Uuid characteristicId}) async {
    final characteristic = QualifiedCharacteristic(
        serviceId: serviceId,
        characteristicId: characteristicId,
        deviceId: _connectedDevice.id);
    final response =
        await _flutterReactiveBle.readCharacteristic(characteristic);
    return response;
  }
}
