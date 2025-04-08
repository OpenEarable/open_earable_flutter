import 'dart:async';

import 'package:open_earable_flutter/open_earable_flutter.dart';
import 'package:open_earable_flutter/src/managers/sensor_handler.dart';
import 'package:open_earable_flutter/src/models/capabilities/sensor_configuration_specializations/sensor_configuration_v2.dart';
import 'package:open_earable_flutter/src/models/devices/open_earable_v1.dart';
import 'package:open_earable_flutter/src/models/devices/open_earable_v2.dart';
import 'package:open_earable_flutter/src/models/wearable_factory.dart';
import 'package:open_earable_flutter/src/utils/sensor_scheme_parser/sensor_scheme_reader.dart';
import 'package:open_earable_flutter/src/utils/sensor_scheme_parser/v2_sensor_scheme_reader.dart';
import 'package:universal_ble/universal_ble.dart';

import '../../managers/v2_sensor_handler.dart';
import '../../utils/sensor_value_parser/v2_sensor_value_parser.dart';

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
    SensorSchemeReader schemeParser = V2SensorSchemeReader(bleManager!, device.id);

    V2SensorHandler sensorManager = V2SensorHandler(
      bleManager: bleManager!,
      discoveredDevice: device,
      sensorSchemeParser: schemeParser,
      sensorValueParser: V2SensorValueParser(),
    );

    List<SensorScheme> sensorSchemes = await schemeParser.readSensorSchemes();

    for (SensorScheme scheme in sensorSchemes) {
      List<SensorConfigurationValueV2> sensorConfigurationValues = [];
      //TODO: make sure the frequencies are specified
      for (int index = 0; index < scheme.options!.frequencies!.frequencies.length; index++) {
        double frequency = scheme.options!.frequencies!.frequencies[index];

        if (index == 0) {
          // One "off" option is enough
          sensorConfigurationValues.add(
            SensorConfigurationValueV2(
              frequency: frequency,
              frequencyIndex: index,
              streamData: false,
              recordData: false,
            ),
          );
        }

        sensorConfigurationValues.add(
          SensorConfigurationValueV2(
            frequency: frequency,
            frequencyIndex: index,
            streamData: true,
            recordData: false,
          ),
        );

        if (index <= scheme.options!.frequencies!.maxStreamingFreqIndex) {
          // Add stream options
          sensorConfigurationValues.add(
            SensorConfigurationValueV2(
              frequency: frequency,
              frequencyIndex: index,
              streamData: false,
              recordData: true,
            ),
          );
          sensorConfigurationValues.add(
            SensorConfigurationValueV2(
              frequency: frequency,
              frequencyIndex: index,
              streamData: true,
              recordData: true,
            ),
          );
        }
      }

      SensorConfigurationV2 sensorConfiguration = SensorConfigurationV2(
        name: scheme.sensorName,
        values: sensorConfigurationValues,
        maxStreamingFreqIndex: scheme.options!.frequencies!.maxStreamingFreqIndex,
        sensorHandler: sensorManager,
        sensorId: scheme.sensorId,
      );

      sensorConfigurations.add(sensorConfiguration);

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
          sensorName: groupName,
          chartTitle: groupName,
          shortChartTitle: groupName,
          axisNames: axisNames,
          axisUnits: axisUnits,
          sensorManager: sensorManager,
          relatedConfigurations: [sensorConfiguration],
        );

        sensors.add(sensor);
      }
    }

    logger.d("Created sensors: $sensors");
    logger.d("Created sensor configurations: $sensorConfigurations");

    return (sensors, sensorConfigurations);
  }
}

class _OpenEarableSensorV2 extends Sensor<SensorDoubleValue> {
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
          timestampExponent: -6,
          relatedConfigurations: relatedConfigurations,
        );

  @override
  List<String> get axisNames => _axisNames;

  @override
  List<String> get axisUnits => _axisUnits;

  Stream<SensorDoubleValue> _createSingleDataSubscription(String componentName) {
    StreamController<SensorDoubleValue> streamController = StreamController();

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

      SensorDoubleValue sensorValue = SensorDoubleValue(
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
  Stream<SensorDoubleValue> get sensorStream {
    return _createSingleDataSubscription(sensorName);
  }
}
