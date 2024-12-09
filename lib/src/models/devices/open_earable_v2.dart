import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:logger/logger.dart';

import '../../managers/open_earable_sensor_manager.dart';
import '../../utils/simple_kalman.dart';
import '../capabilities/device_firmware_version.dart';
import '../capabilities/device_hardware_version.dart';
import '../capabilities/device_identifier.dart';
import '../capabilities/rgb_led.dart';
import '../capabilities/sensor.dart';
import '../capabilities/sensor_configuration.dart';
import '../capabilities/sensor_configuration_manager.dart';
import '../capabilities/sensor_manager.dart';
import '../../managers/ble_manager.dart';
import 'discovered_device.dart';
import 'wearable.dart';

const String _ledServiceUuid = "81040a2e-4819-11ee-be56-0242ac120002";
const String _ledSetStateCharacteristic =
    "81040e7a-4819-11ee-be56-0242ac120002";

const String _deviceInfoServiceUuid = "45622510-6468-465a-b141-0b9b0f96b468";
const String _deviceIdentifierCharacteristicUuid =
    "45622511-6468-465a-b141-0b9b0f96b468";
const String _deviceFirmwareVersionCharacteristicUuid =
    "45622512-6468-465a-b141-0b9b0f96b468";
const String _deviceHardwareVersionCharacteristicUuid =
    "45622513-6468-465a-b141-0b9b0f96b468";

const String _deviceParseInfoServiceUuid =
    "caa25cb7-7e1b-44f2-adc9-e8c06c9ced43";
const String _deviceParseInfoCharacteristicUuid =
    "caa25cb8-7e1b-44f2-adc9-e8c06c9ced43";

Logger _logger = Logger();

Map<String, Object> _parseSchemeCharacteristic(List<int> data) {
  Map<String, Object> parsedData = {};
  
  int sensorCount = data.removeAt(0);
  for (int i = 0; i < sensorCount; i++) {
    Map<String, Object> sensorMap = _parseSensorScheme(data);
    parsedData.addAll(sensorMap);
  }

  return parsedData;
}

Map<String, Object> _parseSensorScheme(List<int> data) {
  int sensorID = data.removeAt(0);
  String sensorName = _parseString(data);
  int componentsCount = data.removeAt(0);

  Map<String, Object> componentsMap = {};
  for (int i = 0; i < componentsCount; i++) {
    Map<String, Object> comp = _parseComponentScheme(data);
    for (var group in comp.keys) {
      if (!componentsMap.containsKey(group)) {
        componentsMap[group] = <String, Object>{};
      }
      Map<String, Object> groupMap = comp[group] as Map<String, Object>;
      (componentsMap[group] as Map<String, Object>).addAll(groupMap);
    }
  }

  Map<String, Object> parsedSensorScheme = {
    sensorName : {
      'SensorID' : sensorID,
      'Components' : componentsMap,
    },
  };

  return parsedSensorScheme;
}

Map<String, Object> _parseComponentScheme(List<int> data) {
  int type = data.removeAt(0);
  String groupName = _parseString(data);
  String componentName = _parseString(data);
  String unitName = _parseString(data);
  
  Map<String, Object> parsedComponentScheme = {
    groupName : {
      componentName : {
        'type' : type,
        'unit' : unitName,
      },
    },
  };

  return parsedComponentScheme;
}

String _parseString(List<int> data) {
  int stringLength = data.removeAt(0);
  List<int> stringBytes = data.sublist(0, stringLength);
  data.removeRange(0, stringLength);
  return String.fromCharCodes(stringBytes);
}

class OpenEarableV2 extends Wearable
    implements
        SensorManager,
        SensorConfigurationManager,
        RgbLed,
        DeviceIdentifier,
        DeviceFirmwareVersion,
        DeviceHardwareVersion {
  final List<Sensor> _sensors;
  final List<SensorConfiguration> _sensorConfigurations;
  final BleManager _bleManager;
  final DiscoveredDevice _discoveredDevice;

  OpenEarableV2({
    required super.name,
    required super.disconnectNotifier,
    required BleManager bleManager,
    required DiscoveredDevice discoveredDevice,
  })  : _sensors = [],
        _sensorConfigurations = [],
        _bleManager = bleManager,
        _discoveredDevice = discoveredDevice {
    _initSensors();
  }

  void _initSensors() async {
    List<int> sensorParseSchemeData = await _bleManager.read(
      deviceId: _discoveredDevice.id,
      serviceId: _deviceParseInfoServiceUuid,
      characteristicId: _deviceParseInfoCharacteristicUuid,
    );
    _logger.d("Read raw parse info: $sensorParseSchemeData");
    Map<String, Object> parseInfo = _parseSchemeCharacteristic(sensorParseSchemeData);
    _logger.i("Found the following info about parsing: $parseInfo");

    OpenEarableSensorManager sensorManager = OpenEarableSensorManager(
      bleManager: _bleManager,
      deviceId: _discoveredDevice.id,
    );

    for (String sensorName in parseInfo.keys) {
      Map<String, Object> sensorDetail = parseInfo[sensorName] as Map<String, Object>;
      _logger.t("sensor detail: $sensorDetail");

      Map<String, Object> componentsMap = sensorDetail['Components'] as Map<String, Object>;
      _logger.t("components: $componentsMap");

      for (String groupName in componentsMap.keys) {
        _sensorConfigurations.add(
          _OpenEarableSensorConfiguration(
            sensorId: sensorDetail['SensorID'] as int,
            name: sensorName,
            sensorManager: sensorManager,
          ),
        );

        Map<String, Object> groupDetail = componentsMap[groupName] as Map<String, Object>;
        _logger.t("group detail: $groupDetail");
        List<(String, String)> axisDetails = groupDetail.entries.map((axis) {
          Map<String, Object> v = axis.value as Map<String, Object>;
          return (axis.key, v['unit'] as String);
        }).toList();

        _sensors.add(
          _OpenEarableSensor(
            sensorName: sensorName,
            chartTitle: groupName,
            shortChartTitle: groupName,
            axisNames: axisDetails.map((e) => e.$1).toList(),
            axisUnits: axisDetails.map((e) => e.$2).toList(),
            sensorManager: sensorManager,
          ),
        );
      }
    }

    _logger.d("Created sensors: $_sensors");
    _logger.d("Created sensor configurations: $_sensorConfigurations");
  }

  @override
  String get deviceId => _discoveredDevice.id;

  @override
  Future<void> writeLedColor({
    required int r,
    required int g,
    required int b,
  }) async {
    // if (!_bleManager.connected) {
    //   Exception("Can't write sensor config. Earable not connected");
    // }
    if (r < 0 || r > 255 || g < 0 || g > 255 || b < 0 || b > 255) {
      throw ArgumentError('The color values must be in range 0-255');
    }
    ByteData data = ByteData(3);
    data.setUint8(0, r);
    data.setUint8(1, g);
    data.setUint8(2, b);
    await _bleManager.write(
      deviceId: _discoveredDevice.id,
      serviceId: _ledServiceUuid,
      characteristicId: _ledSetStateCharacteristic,
      byteData: data.buffer.asUint8List(),
    );
  }

  /// Reads the device identifier from the connected OpenEarable device.
  ///
  /// Returns a `Future` that completes with the device identifier as a `String`.
  @override
  Future<String?> readDeviceIdentifier() async {
    List<int> deviceIdentifierBytes = await _bleManager.read(
      deviceId: _discoveredDevice.id,
      serviceId: _deviceInfoServiceUuid,
      characteristicId: _deviceIdentifierCharacteristicUuid,
    );
    return String.fromCharCodes(deviceIdentifierBytes);
  }

  /// Reads the device firmware version from the connected OpenEarable device.
  ///
  /// Returns a `Future` that completes with the device firmware version as a `String`.
  @override
  Future<String?> readDeviceFirmwareVersion() async {
    List<int> deviceGenerationBytes = await _bleManager.read(
      deviceId: _discoveredDevice.id,
      serviceId: _deviceInfoServiceUuid,
      characteristicId: _deviceFirmwareVersionCharacteristicUuid,
    );
    return String.fromCharCodes(deviceGenerationBytes);
  }

  /// Reads the device hardware version from the connected OpenEarable device.
  ///
  /// Returns a `Future` that completes with the device firmware version as a `String`.
  @override
  Future<String?> readDeviceHardwareVersion() async {
    List<int> hardwareGenerationBytes = await _bleManager.read(
      deviceId: _discoveredDevice.id,
      serviceId: _deviceInfoServiceUuid,
      characteristicId: _deviceHardwareVersionCharacteristicUuid,
    );
    return String.fromCharCodes(hardwareGenerationBytes);
  }

  @override
  Future<void> disconnect() {
    return _bleManager.disconnect(_discoveredDevice.id);
  }

  @override
  List<SensorConfiguration> get sensorConfigurations =>
      List.unmodifiable(_sensorConfigurations);

  @override
  List<Sensor> get sensors => List.unmodifiable(_sensors);
}

class _OpenEarableSensor extends Sensor {
  final List<String> _axisNames;
  final List<String> _axisUnits;
  final OpenEarableSensorManager _sensorManager;

  StreamSubscription? _dataSubscription;

  _OpenEarableSensor({
    required String sensorName,
    required String chartTitle,
    required String shortChartTitle,
    required List<String> axisNames,
    required List<String> axisUnits,
    required OpenEarableSensorManager sensorManager,
  })  : _axisNames = axisNames,
        _axisUnits = axisUnits,
        _sensorManager = sensorManager,
        super(
          sensorName: sensorName,
          chartTitle: chartTitle,
          shortChartTitle: shortChartTitle,
        );

  @override
  List<String> get axisNames => _axisNames;

  @override
  List<String> get axisUnits => _axisUnits;

  Stream<SensorValue> _getAccGyroMagStream() {
    StreamController<SensorValue> streamController = StreamController();

    final errorMeasure = {"ACC": 5.0, "GYRO": 10.0, "MAG": 25.0};

    SimpleKalman kalmanX = SimpleKalman(
      errorMeasure: errorMeasure[sensorName]!,
      errorEstimate: errorMeasure[sensorName]!,
      q: 0.9,
    );
    SimpleKalman kalmanY = SimpleKalman(
      errorMeasure: errorMeasure[sensorName]!,
      errorEstimate: errorMeasure[sensorName]!,
      q: 0.9,
    );
    SimpleKalman kalmanZ = SimpleKalman(
      errorMeasure: errorMeasure[sensorName]!,
      errorEstimate: errorMeasure[sensorName]!,
      q: 0.9,
    );
    _dataSubscription?.cancel();
    _dataSubscription = _sensorManager.subscribeToSensorData(0).listen((data) {
      int timestamp = data["timestamp"];

      SensorValue sensorValue = SensorValue(
        values: [
          kalmanX.filtered(data[sensorName]["X"]),
          kalmanY.filtered(data[sensorName]["Y"]),
          kalmanZ.filtered(data[sensorName]["Z"]),
        ],
        timestamp: timestamp,
      );

      streamController.add(sensorValue);
    });

    return streamController.stream;
  }

  Stream<SensorValue> _createSingleDataSubscription(String componentName) {
    StreamController<SensorValue> streamController = StreamController();

    _dataSubscription?.cancel();
    _dataSubscription = _sensorManager.subscribeToSensorData(1).listen((data) {
      int timestamp = data["timestamp"];

      SensorValue sensorValue = SensorValue(
        values: [data[sensorName][componentName]],
        timestamp: timestamp,
      );

      streamController.add(sensorValue);
    });

    return streamController.stream;
  }

  @override
  Stream<SensorValue> get sensorStream {
    switch (sensorName) {
      case "ACC":
      case "GYRO":
      case "MAG":
        return _getAccGyroMagStream();
      case "BARO":
        return _createSingleDataSubscription("Pressure");
      case "TEMP":
        return _createSingleDataSubscription("Temperature");
      default:
        throw UnimplementedError();
    }
  }
}

class _ImuSensorConfiguration extends SensorConfiguration {
  final OpenEarableSensorManager _sensorManager;

  _ImuSensorConfiguration({
    required OpenEarableSensorManager sensorManager,
  })  : _sensorManager = sensorManager,
        super(
          name: 'IMU',
          unit: 'Hz',
          values: const [
            SensorConfigurationValue(key: '0'),
            SensorConfigurationValue(key: '10'),
            SensorConfigurationValue(key: '20'),
            SensorConfigurationValue(key: '30'),
          ],
        );

  @override
  void setConfiguration(SensorConfigurationValue configuration) {
    if (!super.values.contains(configuration)) {
      throw UnimplementedError();
    }

    double imuSamplingRate = double.parse(configuration.key);
    OpenEarableSensorConfig imuConfig = OpenEarableSensorConfig(
      sensorId: 0,
      samplingRate: imuSamplingRate,
      latency: 0,
    );

    _sensorManager.writeSensorConfig(imuConfig);
  }
}

class _BarometerSensorConfiguration extends SensorConfiguration {
  final OpenEarableSensorManager _sensorManager;

  _BarometerSensorConfiguration({
    required OpenEarableSensorManager sensorManager,
  })  : _sensorManager = sensorManager,
        super(
          name: 'Barometer',
          unit: 'Hz',
          values: const [
            SensorConfigurationValue(key: '0'),
            SensorConfigurationValue(key: '10'),
            SensorConfigurationValue(key: '20'),
            SensorConfigurationValue(key: '30'),
          ],
        );

  @override
  void setConfiguration(SensorConfigurationValue configuration) {
    if (!super.values.contains(configuration)) {
      throw UnimplementedError();
    }

    double? barometerSamplingRate = double.parse(configuration.key);
    OpenEarableSensorConfig barometerConfig = OpenEarableSensorConfig(
      sensorId: 1,
      samplingRate: barometerSamplingRate,
      latency: 0,
    );

    _sensorManager.writeSensorConfig(barometerConfig);
  }
}

class _MicrophoneSensorConfiguration extends SensorConfiguration {
  final OpenEarableSensorManager _sensorManager;

  _MicrophoneSensorConfiguration({
    required OpenEarableSensorManager sensorManager,
  })  : _sensorManager = sensorManager,
        super(
          name: 'Microphone',
          unit: 'Hz',
          values: const [
            SensorConfigurationValue(key: "0"),
            SensorConfigurationValue(key: "16000"),
            SensorConfigurationValue(key: "20000"),
            SensorConfigurationValue(key: "25000"),
            SensorConfigurationValue(key: "31250"),
            SensorConfigurationValue(key: "33333"),
            SensorConfigurationValue(key: "40000"),
            SensorConfigurationValue(key: "41667"),
            SensorConfigurationValue(key: "50000"),
            SensorConfigurationValue(key: "62500"),
          ],
        );

  @override
  void setConfiguration(SensorConfigurationValue configuration) {
    if (!super.values.contains(configuration)) {
      throw UnimplementedError();
    }

    double? microphoneSamplingRate = double.parse(configuration.key);
    OpenEarableSensorConfig microphoneConfig = OpenEarableSensorConfig(
      sensorId: 2,
      samplingRate: microphoneSamplingRate,
      latency: 0,
    );

    _sensorManager.writeSensorConfig(microphoneConfig);
  }
}

class _OpenEarableSensorConfiguration extends SensorConfiguration {
  final OpenEarableSensorManager _sensorManager;
  final int _sensorId;

  _OpenEarableSensorConfiguration({required int sensorId, required String name, required OpenEarableSensorManager sensorManager}):
    _sensorManager = sensorManager,
    _sensorId = sensorId,
    super(
      name: name,
      unit: "Hz",
      values: [], //TODO: fill with values
    );

  @override
  void setConfiguration(SensorConfigurationValue configuration) {
    if (!super.values.contains(configuration)) {
      throw UnimplementedError();
    }

    double? microphoneSamplingRate = double.parse(configuration.key);
    OpenEarableSensorConfig microphoneConfig = OpenEarableSensorConfig(
      sensorId: _sensorId,
      samplingRate: microphoneSamplingRate,
      latency: 0,
    );

    _sensorManager.writeSensorConfig(microphoneConfig);
  }
}
