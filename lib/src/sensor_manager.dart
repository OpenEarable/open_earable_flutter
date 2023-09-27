part of open_earable_flutter;

/// Manages sensor-related functionality for the OpenEarable device.
class SensorManager {
  final BleManager _bleManager;
  List<SensorScheme>? _sensorSchemes;

  /// Creates a [SensorManager] instance with the specified [bleManager].
  SensorManager({required BleManager bleManager}) : _bleManager = bleManager;

  /// Writes the sensor configuration to the OpenEarable device.
  ///
  /// The [sensorConfig] parameter contains the sensor id, sampling rate
  /// and latency of the sensor.
  void writeSensorConfig(OpenEarableSensorConfig sensorConfig) async {
    if (!_bleManager.connected) {
      Exception("Can't write sensor config. Earable not connected");
    }
    await _bleManager.write(
        serviceId: sensorServiceUuid,
        characteristicId: sensorConfigurationCharacteristicUuid,
        byteData: sensorConfig.byteList);
    if (_sensorSchemes == null) {
      await _readSensorScheme();
    }
  }

  /// Subscribes to sensor data for a specific sensor.
  ///
  /// The [sensorId] parameter specifies the ID of the sensor to subscribe to.
  /// - 0: IMU data
  /// - 1: Barometer data
  /// Returns a [Stream] of sensor data as a [Map] of sensor values.
  Stream<Map<String, dynamic>> subscribeToSensorData(int sensorId) {
    if (!_bleManager.connected) {
      Exception("Can't subscribe to sensor data. Earable not connected");
    }
    StreamController<Map<String, dynamic>> streamController =
        StreamController();
    _bleManager
        .subscribe(
            serviceId: sensorServiceUuid,
            characteristicId: sensorDataCharacteristicUuid)
        .listen((data) async {
      if (data.isNotEmpty && data[0] == sensorId) {
        Map<String, dynamic> parsedData = await _parseData(data);
        streamController.add(parsedData);
      }
    }, onError: (error) {});

    return streamController.stream;
  }

  // Parses raw sensor data bytes into a [Map] of sensor values.
  Future<Map<String, dynamic>> _parseData(data) async {
    ByteData byteData = ByteData.sublistView(Uint8List.fromList(data));
    var byteIndex = 0;
    final sensorId = byteData.getUint8(byteIndex);
    byteIndex += 1;
    final timestamp = byteData.getUint32(byteIndex, Endian.little);
    byteIndex += 4;
    Map<String, dynamic> parsedData = {};
    if (_sensorSchemes == null) {
      _readSensorScheme();
    }
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
        case ParseType.int8:
          parsedValue = byteData.getInt8(byteIndex);
          byteIndex += 1;
          break;
        case ParseType.uint8:
          parsedValue = byteData.getUint8(byteIndex);
          byteIndex += 1;
          break;
        case ParseType.int16:
          parsedValue = byteData.getInt16(byteIndex, Endian.little);
          byteIndex += 2;
          break;
        case ParseType.uint16:
          parsedValue = byteData.getUint16(byteIndex, Endian.little);
          byteIndex += 2;
          break;
        case ParseType.int32:
          parsedValue = byteData.getInt32(byteIndex, Endian.little);
          byteIndex += 4;
          break;
        case ParseType.uint32:
          parsedValue = byteData.getUint32(byteIndex, Endian.little);
          byteIndex += 4;
          break;
        case ParseType.float:
          parsedValue = byteData.getFloat32(byteIndex, Endian.little);
          byteIndex += 4;
          break;
        case ParseType.double:
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

  /// Returns a [Stream] of battery level updates.
  /// Battery level is provided as percent values (0-100).
  Stream getBatteryLevelStream() {
    return _bleManager.subscribe(
        serviceId: batteryServiceUuid,
        characteristicId: batteryLevelCharacteristicUuid);
  }

  /// Returns a [Stream] of button state updates.
  /// - 0: Idle
  /// - 1: Pressed
  /// - 2: Held
  Stream getButtonStateStream() {
    return _bleManager.subscribe(
        serviceId: buttonServiceUuid,
        characteristicId: buttonStateCharacteristicUuid);
  }

  /// Reads the sensor scheme that is needed to parse the raw sensor
  /// data bytes
  Future<void> _readSensorScheme() async {
    List<int> byteStream = await _bleManager.read(
        serviceId: parseInfoServiceUuid,
        characteristicId: schemeCharacteristicUuid);

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

/// Represents a sensor component with its type, group name, component name, and unit name.
class Component {
  int type;
  String groupName;
  String componentName;
  String unitName;

  /// Creates a [Component] instance with the specified parameters.
  Component(this.type, this.groupName, this.componentName, this.unitName);

  @override
  String toString() {
    return 'Component(type: $type, groupName: $groupName, componentName: $componentName, unitName: $unitName)';
  }
}

/// Represents a sensor scheme that contains the components for a sensor.
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

/// Represents the configuration for an OpenEarable sensor, including sensor ID, sampling rate, and latency.
class OpenEarableSensorConfig {
  int sensorId; // 8-bit unsigned integer
  double samplingRate; // 4-byte float
  int latency; // 32-bit unsigned integer

  /// Creates an [OpenEarableSensorConfig] instance with the specified properties.
  OpenEarableSensorConfig({
    required this.sensorId,
    required this.samplingRate,
    required this.latency,
  });

  /// Returns a byte list representing the sensor configuration for writing to the device.
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
  int8,
  uint8,

  int16,
  uint16,

  int32,
  uint32,

  float,
  double
}
