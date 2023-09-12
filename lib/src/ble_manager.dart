part of open_earable_flutter;

class BleManager {
  final FlutterReactiveBle _flutterReactiveBle = FlutterReactiveBle();

  bool _foundDeviceWaitingToConnect = false;
  bool _scanStarted = false;
  bool _connected = false;
  bool get connected => _connected;

  late Stream<DiscoveredDevice> _scanStream;
  Stream<DiscoveredDevice> get scanStream => _scanStream;

  DiscoveredDevice? _connectedDevice;
  DiscoveredDevice? get connectedDevice => _connectedDevice;

  late Stream<ConnectionStateUpdate> _connectionEventStream;

  final StreamController<bool> _connectionStateController =
      StreamController<bool>.broadcast();
  Stream<bool> get connectionStateStream => _connectionStateController.stream;

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
      _scanStream = _flutterReactiveBle
          .scanForDevices(withServices: []).asBroadcastStream();
    }
  }

  connectToDevice(DiscoveredDevice device) {
    _connectedDevice = device;
    _scanStarted = false;
    _connectionEventStream = _flutterReactiveBle.connectToAdvertisingDevice(
        id: device.id,
        prescanDuration: const Duration(seconds: 1),
        withServices: [sensorServiceUuid]);
    _connectionEventStream.listen((event) {
      switch (event.connectionState) {
        case DeviceConnectionState.connected:
          {
            _foundDeviceWaitingToConnect = false;
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

  Future<void> write(
      {required Uuid serviceId,
      required Uuid characteristicId,
      required List<int> value}) async {
    if (!_connected) {
      Exception("Write failed because no Earable is connected");
    }
    final characteristic = QualifiedCharacteristic(
        serviceId: sensorServiceUuid,
        characteristicId: sensorConfigurationCharacteristicUuid,
        deviceId: _connectedDevice!.id);
    await _flutterReactiveBle.writeCharacteristicWithResponse(
      characteristic,
      value: value,
    );
  }

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
