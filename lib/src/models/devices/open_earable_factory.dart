import 'dart:async';

import 'package:open_earable_flutter/open_earable_flutter.dart';
import 'package:open_earable_flutter/src/managers/sensor_handler.dart';
import 'package:open_earable_flutter/src/models/capabilities/sensor_configuration_specializations/sensor_configuration_v2.dart';
import 'package:open_earable_flutter/src/models/devices/open_earable_v1.dart';
import 'package:open_earable_flutter/src/models/devices/open_earable_v2.dart';
import 'package:open_earable_flutter/src/models/wearable_factory.dart';
import 'package:open_earable_flutter/src/utils/sensor_scheme_parser/sensor_scheme_parser.dart';
import 'package:open_earable_flutter/src/utils/sensor_scheme_parser/v2_sensor_scheme_parser.dart';
import 'package:open_earable_flutter/src/utils/sensor_value_parser/edge_ml_sensor_value_parser.dart';
import 'package:universal_ble/universal_ble.dart';

import '../../managers/v2_sensor_handler.dart';
import '../../constants.dart';

const String _deviceInfoServiceUuid = "45622510-6468-465a-b141-0b9b0f96b468";
const String _deviceFirmwareVersionCharacteristicUuid =
    "45622512-6468-465a-b141-0b9b0f96b468";

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
      serviceId: parseInfoServiceUuid,
      characteristicId: schemeCharacteristicV2Uuid,
    );

    SensorSchemeParser schemeParser = V2SensorSchemeParser();

    V2SensorHandler sensorManager = V2SensorHandler(
      bleManager: bleManager!,
      discoveredDevice: device,
      sensorSchemeParser: schemeParser,
      sensorValueParser: EdgeMlSensorValueParser(),
    );

    List<SensorScheme> sensorSchemes = schemeParser.parse(sensorParseSchemeData);

    for (SensorScheme scheme in sensorSchemes) {
      List<SensorConfigurationValueV2> sensorConfigurationValues = [];
      //TODO: make sure the frequencies are specified
      for (int index = 0; index < scheme.options!.frequencies!.frequencies.length; index++) {
        double frequency = scheme.options!.frequencies!.frequencies[index];
        sensorConfigurationValues.add(
          SensorConfigurationValueV2(
            sensorId: scheme.sensorId,
            frequency: frequency,
            frequencyIndex: index,
          ),
        );
      }

      sensorConfigurations.add(
        SensorConfigurationV2(
          name: scheme.sensorName,
          values: sensorConfigurationValues,
          maxStreamingFreqIndex: scheme.options!.frequencies!.maxStreamingFreqIndex,
          sensorHandler: sensorManager,
        ),
      );

      Map<String, List<Component>> sensorGroups = {};
      for (Component component in scheme.components) {
        if (!sensorGroups.containsKey(component.groupName)) {
          sensorGroups[component.groupName] = [];
        }
        sensorGroups[component.groupName]!.add(component);
      }

      for (String groupName in sensorGroups.keys) {
        List<String> axisNames = [];
        List<String> axisUnits = [];
        for (Component component in sensorGroups[groupName]!) {
          axisNames.add(component.componentName);
          axisUnits.add(component.unitName);
        }

        Sensor sensor = _OpenEarableSensorV2(
          sensorId: scheme.sensorId,
          sensorName: scheme.sensorName,
          chartTitle: scheme.sensorName,
          shortChartTitle: scheme.sensorName,
          axisNames: axisNames,
          axisUnits: axisUnits,
          sensorManager: sensorManager,
        );

        sensors.add(sensor);
      }
    }

    logger.d("Created sensors: $sensors");
    logger.d("Created sensor configurations: $sensorConfigurations");

    return (sensors, sensorConfigurations);
  }
}


// Map<String, Object> _parseSchemeCharacteristic(List<int> data) {
//   Map<String, Object> parsedData = {};
  
//   int sensorCount = data.removeAt(0);
//   for (int i = 0; i < sensorCount; i++) {
//     Map<String, Object> sensorMap = _parseSensorScheme(data);
//     parsedData.addAll(sensorMap);
//   }

//   return parsedData;
// }

// Map<String, Object> _parseSensorScheme(List<int> data) {
//   int sensorID = data.removeAt(0);
//   String sensorName = _parseString(data);
//   int componentsCount = data.removeAt(0);

//   Map<String, Object> componentsMap = {};
//   for (int i = 0; i < componentsCount; i++) {
//     Map<String, Object> comp = _parseComponentScheme(data);
//     for (var group in comp.keys) {
//       if (!componentsMap.containsKey(group)) {
//         componentsMap[group] = <String, Object>{};
//       }
//       Map<String, Object> groupMap = comp[group] as Map<String, Object>;
//       (componentsMap[group] as Map<String, Object>).addAll(groupMap);
//     }
//   }

//   Map<String, Object> parsedSensorScheme = {
//     sensorName : {
//       'SensorID' : sensorID,
//       'Components' : componentsMap,
//     },
//   };

//   return parsedSensorScheme;
// }

// Map<String, Object> _parseComponentScheme(List<int> data) {
//   int type = data.removeAt(0);
//   String groupName = _parseString(data);
//   String componentName = _parseString(data);
//   String unitName = _parseString(data);
  
//   Map<String, Object> parsedComponentScheme = {
//     groupName : {
//       componentName : {
//         'type' : type,
//         'unit' : unitName,
//       },
//     },
//   };

//   return parsedComponentScheme;
// }

// String _parseString(List<int> data) {
//   int stringLength = data.removeAt(0);
//   List<int> stringBytes = data.sublist(0, stringLength);
//   data.removeRange(0, stringLength);
//   return String.fromCharCodes(stringBytes);
// }

class _OpenEarableSensorV2 extends Sensor {
  final int _sensorId;
  final List<String> _axisNames;
  final List<String> _axisUnits;
  final SensorHandler _sensorManager;

  _OpenEarableSensorV2({
    required int sensorId,
    required String sensorName,
    required String chartTitle,
    required String shortChartTitle,
    required List<String> axisNames,
    required List<String> axisUnits,
    required SensorHandler sensorManager,
    List<SensorConfiguration> relatedConfigurations = const [],
  })  : _sensorId = sensorId,
        _axisNames = axisNames,
        _axisUnits = axisUnits,
        _sensorManager = sensorManager,
        super(
          sensorName: sensorName,
          chartTitle: chartTitle,
          shortChartTitle: shortChartTitle,
          relatedConfigurations: relatedConfigurations,
        );

  @override
  List<String> get axisNames => _axisNames;

  @override
  List<String> get axisUnits => _axisUnits;

  Stream<SensorValue> _createSingleDataSubscription(String componentName) {
    StreamController<SensorValue> streamController = StreamController();

    StreamSubscription subscription = _sensorManager.subscribeToSensorData(_sensorId).listen((data) {
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

      streamController.add(sensorValue);
    });

    streamController.onCancel = () {
      subscription.cancel();
    };

    return streamController.stream;
  }

  @override
  Stream<SensorValue> get sensorStream {
    return _createSingleDataSubscription(sensorName);
  }
}

// class _OpenEarableSensorConfiguration extends SensorConfiguration {
//   final OpenEarableSensorHandler _sensorManager;
//   final int _sensorId;

//   _OpenEarableSensorConfiguration({required int sensorId, required String name, required OpenEarableSensorHandler sensorManager}):
//     _sensorManager = sensorManager,
//     _sensorId = sensorId,
//     super(
//       name: name,
//       unit: "Hz",
//       values: [
//         SensorFrequencyConfigurationValue(frequency: 0),
//         SensorFrequencyConfigurationValue(frequency: 10),
//         SensorFrequencyConfigurationValue(frequency: 30),
//         SensorFrequencyConfigurationValue(frequency: 50),
//         SensorFrequencyConfigurationValue(frequency: 100),
//       ], //TODO: fill with values
//     );

//   @override
//   void setConfiguration(SensorConfigurationValue configuration) {
//     if (!super.values.contains(configuration)) {
//       throw UnimplementedError();
//     }

//     double? microphoneSamplingRate = double.parse(configuration.key);
//     OpenEarableSensorConfig microphoneConfig = OpenEarableSensorConfig(
//       sensorId: _sensorId,
//       samplingRate: microphoneSamplingRate,
//       latency: 0,
//     );

//     _sensorManager.writeSensorConfig(microphoneConfig);
//   }
// }
