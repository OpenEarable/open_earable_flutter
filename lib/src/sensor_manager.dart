part of open_earable_flutter;

class SensorManager {
  final BleManager _bleManager;
  final Map<int, StreamController<Map<String, dynamic>>>
      _sensorDataControllers = {};
  List<SensorScheme>? _sensorSchemes;
  SensorManager({required BleManager bleManager}) : _bleManager = bleManager;

  void writeSensorConfig(OpenEarableSensorConfig sensorConfig) async {
    if (!_bleManager.connected) {
      Exception("Can't write sensor config. Earable not connected");
    }
    await _bleManager.write(
        serviceId: sensorServiceUuid,
        characteristicId: sensorConfigurationCharacteristicUuid,
        value: sensorConfig.byteList);
    await readScheme();
  }

  Stream<Map<String, dynamic>> subscribeToSensorData(int sensorId) {
    if (!_bleManager.connected) {
      Exception("Can't subscribe to sensor data. Earable not connected");
    }
    if (!_sensorDataControllers.containsKey(sensorId)) {
      _sensorDataControllers[sensorId] =
          StreamController<Map<String, dynamic>>();
      _bleManager
          .subscribe(
              serviceId: sensorServiceUuid,
              characteristicId: sensorDataCharacteristicUuid)
          .listen((data) {
        if (data.isNotEmpty && data[0] == sensorId) {
          Map<String, dynamic> parsedData = parseData(data);
          _sensorDataControllers[sensorId]?.add(parsedData);
        }
      }, onError: (error) {});
    }

    return _sensorDataControllers[sensorId]!.stream;
  }

  Map<String, dynamic> parseData(data) {
    ByteData byteData = ByteData.sublistView(Uint8List.fromList(data));
    var byteIndex = 0;
    final sensorId = byteData.getUint8(byteIndex);
    byteIndex += 1;
    final timestamp = byteData.getUint32(byteIndex, Endian.little);
    byteIndex += 4;
    Map<String, dynamic> parsedData = {};
    if (_sensorSchemes == null) {}
    SensorScheme foundScheme = _sensorSchemes!.firstWhere(
      (scheme) => scheme.sensorId == sensorId,
    );
    parsedData["sensorId"] = sensorId;
    parsedData["timestamp"] = timestamp;
    parsedData["sensorName"] = foundScheme.sensorName;
    for (Component component in foundScheme.components) {
      if (parsedData[component.groupName] == null) {
        parsedData[component.groupName] = {};
      }
      if (parsedData[component.groupName]["units"] == null) {
        parsedData[component.groupName]["units"] = {};
      }
      final dynamic parsedValue;
      switch (ParseType.values[component.type]) {
        case ParseType.PARSE_TYPE_INT8:
          parsedValue = byteData.getInt8(byteIndex);
          byteIndex += 1;
          break;
        case ParseType.PARSE_TYPE_UINT8:
          parsedValue = byteData.getUint8(byteIndex);
          byteIndex += 1;
          break;
        case ParseType.PARSE_TYPE_INT16:
          parsedValue = byteData.getInt16(byteIndex, Endian.little);
          byteIndex += 2;
          break;
        case ParseType.PARSE_TYPE_UINT16:
          parsedValue = byteData.getUint16(byteIndex, Endian.little);
          byteIndex += 2;
          break;
        case ParseType.PARSE_TYPE_INT32:
          parsedValue = byteData.getInt32(byteIndex, Endian.little);
          byteIndex += 4;
          break;
        case ParseType.PARSE_TYPE_UINT32:
          parsedValue = byteData.getUint32(byteIndex, Endian.little);
          byteIndex += 4;
          break;
        case ParseType.PARSE_TYPE_FLOAT:
          parsedValue = byteData.getFloat32(byteIndex, Endian.little);
          byteIndex += 4;
          break;
        case ParseType.PARSE_TYPE_DOUBLE:
          parsedValue = byteData.getFloat64(byteIndex, Endian.little);
          byteIndex += 8;
          break;
      }
      parsedData[component.groupName][component.componentName] = parsedValue;
      parsedData[component.groupName]["units"][component.componentName] =
          component.unitName;
    }
    return parsedData;
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

  Future<void> readScheme() async {
    if (!_bleManager.connected) {
      Exception("Can't read sensor scheme. Earable not connected");
    }
    List<int> byteStream = await _bleManager.read(
        serviceId: ParseInfoServiceUuid,
        characteristicId: SchemeCharacteristicUuid);

    int currentIndex = 0;

    int numSensors = byteStream[currentIndex++];
    List<SensorScheme> sensorSchemes = [];
    for (int i = 0; i < numSensors; i++) {
      int sensorId = byteStream[currentIndex++];

      int nameLength = byteStream[currentIndex++];

      List<int> nameBytes =
          byteStream.sublist(currentIndex, currentIndex + nameLength);
      String sensorName = String.fromCharCodes(nameBytes);
      currentIndex += nameLength;

      int componentCount = byteStream[currentIndex++];

      SensorScheme sensorScheme =
          SensorScheme(sensorId, sensorName, componentCount);

      for (int j = 0; j < componentCount; j++) {
        int componentType = byteStream[currentIndex++];

        int groupNameLength = byteStream[currentIndex++];

        List<int> groupNameBytes =
            byteStream.sublist(currentIndex, currentIndex + groupNameLength);
        String groupName = String.fromCharCodes(groupNameBytes);
        currentIndex += groupNameLength;

        int componentNameLength = byteStream[currentIndex++];

        List<int> componentNameBytes = byteStream.sublist(
            currentIndex, currentIndex + componentNameLength);
        String componentName = String.fromCharCodes(componentNameBytes);
        currentIndex += componentNameLength;

        int unitNameLength = byteStream[currentIndex++];

        List<int> unitNameBytes =
            byteStream.sublist(currentIndex, currentIndex + unitNameLength);
        String unitName = String.fromCharCodes(unitNameBytes);
        currentIndex += unitNameLength;

        Component component =
            Component(componentType, groupName, componentName, unitName);
        sensorScheme.components.add(component);
      }

      sensorSchemes.add(sensorScheme);
    }
    _sensorSchemes = sensorSchemes;
  }
}

class Component {
  int type;
  String groupName;
  String componentName;
  String unitName;

  Component(this.type, this.groupName, this.componentName, this.unitName);

  @override
  String toString() {
    return 'Component(type: $type, groupName: $groupName, componentName: $componentName, unitName: $unitName)';
  }
}

class SensorScheme {
  int sensorId;
  String sensorName;
  int componentCount;
  List<Component> components = [];

  SensorScheme(this.sensorId, this.sensorName, this.componentCount);

  @override
  String toString() {
    return 'Sensorscheme(sensorId: $sensorId, sensorName: $sensorName, components: ${components.map((component) => component.toString()).toList()})';
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

enum ParseType {
  PARSE_TYPE_INT8,
  PARSE_TYPE_UINT8,

  PARSE_TYPE_INT16,
  PARSE_TYPE_UINT16,

  PARSE_TYPE_INT32,
  PARSE_TYPE_UINT32,

  PARSE_TYPE_FLOAT,
  PARSE_TYPE_DOUBLE
}
