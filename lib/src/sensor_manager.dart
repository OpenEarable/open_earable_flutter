part of open_earable_flutter;

class SensorManager {
  final BleManager _bleManager;
  final Map<int, StreamController<List<int>>> _sensorDataControllers = {};

  SensorManager({required BleManager bleManager}) : _bleManager = bleManager;

  void writeSensorConfig(OpenEarableSensorConfig sensorConfig) async {
    _bleManager.write(
        serviceId: sensorServiceUuid,
        characteristicId: sensorConfigurationCharacteristicUuid,
        value: sensorConfig.byteList);
  }

  Stream<List<int>> subscribeToSensorData(int sensorId) {
    print("subscribing to sensor");
    if (!_sensorDataControllers.containsKey(sensorId)) {
      _sensorDataControllers[sensorId] = StreamController<List<int>>();
      _bleManager
          .subscribe(
              serviceId: sensorServiceUuid,
              characteristicId: sensorDataCharacteristicUuid)
          .listen((data) {
        print("Data from sensorManager $data");
        if (data.isNotEmpty && data[0] == sensorId) {
          _sensorDataControllers[sensorId]?.add(data);
        }
      }, onError: (error) {});
    }

    return _sensorDataControllers[sensorId]!.stream;
  }

  void disposeSensorDataController(int sensorId) {
    final controller = _sensorDataControllers[sensorId];
    if (controller != null) {
      controller.close();
      _sensorDataControllers.remove(sensorId);
    }
  }

  void disposeAllSensorDataControllers() {
    for (final controller in _sensorDataControllers.values) {
      controller.close();
    }
    _sensorDataControllers.clear();
  }

  Stream getBatteryLevelStream() {
    return _bleManager.subscribe(
        serviceId: batteryServiceUuid,
        characteristicId: batteryLevelCharacteristicUuid);
  }

  Stream getButtonStateStream() {
    return _bleManager.subscribe(
        serviceId: buttonServiceUuid,
        characteristicId: buttonStateCharacteristicUuid);
  }
}

class OpenEarableSensorConfig {
  // Properties
  int sensorId; // 8-bit unsigned integer
  double samplingRate; // 4-byte float
  int latency; // 32-bit unsigned integer

  OpenEarableSensorConfig({
    required this.sensorId,
    required this.samplingRate,
    required this.latency,
  });

  List<int> get byteList {
    ByteData data = ByteData(9);
    data.setUint8(0, sensorId);
    data.setFloat32(1, samplingRate, Endian.little);
    data.setUint32(5, latency, Endian.little);
    return data.buffer.asUint8List();
  }

  @override
  String toString() {
    return 'OpenEarableSensorConfig(sensorId: $sensorId, sampleRate: $samplingRate, latency: $latency)';
  }
}
