import 'dart:async';

import 'package:open_earable_flutter/open_earable_flutter.dart';
import 'package:open_earable_flutter/src/managers/open_earable_sensor_manager.dart';
import 'package:open_earable_flutter/src/models/devices/open_earable_v1.dart';
import 'package:open_earable_flutter/src/models/devices/open_earable_v2.dart';
import 'package:open_earable_flutter/src/models/wearable_factory.dart';
import 'package:open_earable_flutter/src/utils/simple_kalman.dart';
import 'package:universal_ble/universal_ble.dart';

const String _deviceInfoServiceUuid = "45622510-6468-465a-b141-0b9b0f96b468";
const String _deviceFirmwareVersionCharacteristicUuid =
    "45622512-6468-465a-b141-0b9b0f96b468";

const String _deviceParseInfoServiceUuid =
    "caa25cb7-7e1b-44f2-adc9-e8c06c9ced43";
const String _deviceParseInfoCharacteristicUuid =
    "caa25cb8-7e1b-44f2-adc9-e8c06c9ced43";


class OpenEarableFactory extends WearableFactory {
  final _v1Regex = RegExp(r'^1\.\d+\.\d+$');
  final _v2Regex = RegExp(r'^2\.\d+\.\d+$');

  @override
  Future<bool> matches(DiscoveredDevice device, List<BleService> services) async {
    if (!services.any((service) => service.uuid == _deviceInfoServiceUuid)) {
      logger.d("'$device' has no service matching '$_deviceInfoServiceUuid'");
      return false;
    }
    String firmwareVersion = await _getFirmwareVersion(device);
    logger.d("Firmware Version: '$firmwareVersion'");

    logger.t("matches V2: ${_v2Regex.hasMatch(firmwareVersion)}");

    return _v1Regex.hasMatch(firmwareVersion) || _v2Regex.hasMatch(firmwareVersion);
  }
  
  @override
  Future<Wearable> createFromDevice(DiscoveredDevice device) async {
    if (bleManager == null) {
      throw Exception("bleManager needs to be set before using the factory");
    }
    if (disconnectNotifier == null) {
      throw Exception("disconnectNotifier needs to be set before using the factory");
    }
    String firmwareVersion = await _getFirmwareVersion(device);


    if (_v1Regex.hasMatch(firmwareVersion)) {
      return OpenEarableV1(
        name: device.name,
        disconnectNotifier: disconnectNotifier!,
        bleManager: bleManager!,
        discoveredDevice: device,
      );
    } else if (_v2Regex.hasMatch(firmwareVersion)) {
      (List<Sensor>, List<SensorConfiguration>) sensorInfo = await _initSensors(device);
      return OpenEarableV2(
        name: device.name,
        disconnectNotifier: disconnectNotifier!,
        sensors: sensorInfo.$1,
        sensorConfigurations: sensorInfo.$2,
        bleManager: bleManager!,
        discoveredDevice: device,
      );
    } else {
      throw Exception('OpenEarable version is not supported');
    }
  }

  Future<String> _getFirmwareVersion(DiscoveredDevice device) async {
    List<int> softwareGenerationBytes = await bleManager!.read(
      deviceId: device.id,
      serviceId: _deviceInfoServiceUuid,
      characteristicId: _deviceFirmwareVersionCharacteristicUuid,
    );
    logger.d("Raw Firmware Version: $softwareGenerationBytes");
    int firstZeroIndex = softwareGenerationBytes.indexOf(0);
    if (firstZeroIndex != -1) {
      softwareGenerationBytes = softwareGenerationBytes.sublist(0, firstZeroIndex);
    }
    return String.fromCharCodes(softwareGenerationBytes);
  }

  Future<(List<Sensor>, List<SensorConfiguration>)> _initSensors(DiscoveredDevice device) async {
    List<Sensor> sensors = [];
    List<SensorConfiguration> sensorConfigurations = [];

    List<int> sensorParseSchemeData = await bleManager!.read(
      deviceId: device.id,
      serviceId: _deviceParseInfoServiceUuid,
      characteristicId: _deviceParseInfoCharacteristicUuid,
    );
    logger.d("Read raw parse info: $sensorParseSchemeData");
    Map<String, Object> parseInfo = _parseSchemeCharacteristic(sensorParseSchemeData);
    logger.i("Found the following info about parsing: $parseInfo");

    OpenEarableSensorManager sensorManager = OpenEarableSensorManager(
      bleManager: bleManager!,
      deviceId: device.id,
    );

    for (String sensorName in parseInfo.keys) {
      Map<String, Object> sensorDetail = parseInfo[sensorName] as Map<String, Object>;
      logger.t("sensor detail: $sensorDetail");

      Map<String, Object> componentsMap = sensorDetail['Components'] as Map<String, Object>;
      logger.t("components: $componentsMap");
      
      sensorConfigurations.add(
        _OpenEarableSensorConfiguration(
          sensorId: sensorDetail['SensorID'] as int,
          name: sensorName,
          sensorManager: sensorManager,
        ),
      );

      for (String groupName in componentsMap.keys) {

        Map<String, Object> groupDetail = componentsMap[groupName] as Map<String, Object>;
        logger.t("group detail: $groupDetail");
        List<(String, String)> axisDetails = groupDetail.entries.map((axis) {
          Map<String, Object> v = axis.value as Map<String, Object>;
          return (axis.key, v['unit'] as String);
        }).toList();

        sensors.add(
          _OpenEarableSensor(
            sensorId: sensorDetail['SensorID'] as int,
            sensorName: groupName,
            chartTitle: groupName,
            shortChartTitle: groupName,
            axisNames: axisDetails.map((e) => e.$1).toList(),
            axisUnits: axisDetails.map((e) => e.$2).toList(),
            sensorManager: sensorManager,
          ),
        );
      }
    }

    logger.d("Created sensors: $sensors");
    logger.d("Created sensor configurations: $sensorConfigurations");

    return (sensors, sensorConfigurations);
  }
}


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

class _OpenEarableSensor extends Sensor {
  final int _sensorId;
  final List<String> _axisNames;
  final List<String> _axisUnits;
  final OpenEarableSensorManager _sensorManager;

  StreamSubscription? _dataSubscription;

  int _listenersCount = 0;

  final StreamController<SensorValue> _streamController = StreamController.broadcast();

  _OpenEarableSensor({
    required int sensorId,
    required String sensorName,
    required String chartTitle,
    required String shortChartTitle,
    required List<String> axisNames,
    required List<String> axisUnits,
    required OpenEarableSensorManager sensorManager,
  })  : _sensorId = sensorId,
        _axisNames = axisNames,
        _axisUnits = axisUnits,
        _sensorManager = sensorManager,
        super(
          sensorName: sensorName,
          chartTitle: chartTitle,
          shortChartTitle: shortChartTitle,
        ) {
    _streamController.onListen = () {
      _listenersCount++;
      logger.t("Sensor stream listener added from $sensorName, $_listenersCount listeners");
      if (_listenersCount > 0) {
        _dataSubscription?.resume();
      }
    };
    _streamController.onCancel = () {
      _listenersCount--;
      logger.t("Sensor stream listener removed from $sensorName, $_listenersCount listeners");
      if (_listenersCount == 0) {
        _dataSubscription?.pause();
      }
    };
  }

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

      SensorValue sensorValue = SensorDoubleValue(
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
    _dataSubscription?.cancel();
    _dataSubscription = _sensorManager.subscribeToSensorData(_sensorId).listen((data) {
      int timestamp = data["timestamp"];
      logger.t("SensorData: $data");

      logger.t("componentData of $componentName: ${data[componentName]}");

      //TODO: use int for integer based values
      List<double> values = [];
      for (var entry in (data[componentName] as Map).entries) {
        if (entry.key == 'units') {
          continue;
        }

        values.add(entry.value.toDouble());
      }

      SensorValue sensorValue = SensorDoubleValue(
        values: values,
        timestamp: timestamp,
      );

      _streamController.add(sensorValue);
    });

    return _streamController.stream;
  }

  @override
  Stream<SensorValue> get sensorStream {
    switch (sensorName) {
      // case "ACC":
      // case "GYRO":
      // case "MAG":
      //   return _getAccGyroMagStream();
      // case "BARO":
      //   return _createSingleDataSubscription("Pressure");
      // case "TEMP":
      //   return _createSingleDataSubscription("Temperature");
      default:
        return _createSingleDataSubscription(sensorName);
    }
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
      values: [
        const SensorConfigurationValue(key: "0"),
        const SensorConfigurationValue(key: "10"),
      ], //TODO: fill with values
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
