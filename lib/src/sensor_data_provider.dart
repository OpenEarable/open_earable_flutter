part of open_earable_flutter;

class SensorManager {
  final BleManager _bleManager;
  final Map<int, StreamController<List<int>>> _sensorDataControllers = {};

  SensorManager({required BleManager bleManager}) : _bleManager = bleManager;

  Stream<List<int>> subscribeToSensorData(int sensorId) {
    if (!_sensorDataControllers.containsKey(sensorId)) {
      _sensorDataControllers[sensorId] = StreamController<List<int>>();

      _bleManager
          .subscribe(
              serviceId: sensorServiceUuid,
              characteristicId: sensorDataCharacteristicUuid)
          .listen((data) {
        if (data.isNotEmpty && data[0] == sensorId) {
          _sensorDataControllers[sensorId]?.add(data);
        }
      }, onError: (error) {});
    }

    return _sensorDataControllers[sensorId]!.stream;
  }

  void disposeStreamController(int id) {
    final controller = _sensorDataControllers[id];
    if (controller != null) {
      controller.close();
      _sensorDataControllers.remove(id);
    }
  }

  void disposeAll() {
    for (final controller in _sensorDataControllers.values) {
      controller.close();
    }
    _sensorDataControllers.clear();
  }
}
