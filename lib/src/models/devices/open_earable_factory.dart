import 'dart:async';

import 'package:open_earable_flutter/src/managers/sensor_handler.dart';
import 'package:open_earable_flutter/src/models/wearable_factory.dart';
import 'package:open_earable_flutter/src/utils/sensor_scheme_parser/sensor_scheme_reader.dart';
import 'package:open_earable_flutter/src/utils/sensor_scheme_parser/v2_sensor_scheme_reader.dart';
import 'package:universal_ble/universal_ble.dart';

import '../../../open_earable_flutter.dart' show logger;
import '../../managers/v2_sensor_handler.dart';
import '../../utils/sensor_value_parser/v2_sensor_value_parser.dart';
import '../capabilities/audio_mode_manager.dart';
import '../capabilities/sensor.dart';
import '../capabilities/sensor_configuration.dart';
import '../capabilities/sensor_configuration_specializations/recordable_sensor_configuration.dart';
import '../capabilities/sensor_configuration_specializations/sensor_configuration_open_earable_v2.dart';
import '../capabilities/sensor_configuration_specializations/streamable_sensor_configuration.dart';
import '../capabilities/system_device.dart';
import 'discovered_device.dart';
import 'open_earable_v1.dart';
import 'open_earable_v2.dart';
import 'wearable.dart';

const String _deviceInfoServiceUuid = "45622510-6468-465a-b141-0b9b0f96b468";
const String _deviceFirmwareVersionCharacteristicUuid =
    "45622512-6468-465a-b141-0b9b0f96b468";

class OpenEarableFactory extends WearableFactory {
  final _v1Regex = RegExp(r'^1\.\d+\.\d+$');
  final _v2Regex = RegExp(r'^2\.\d+\.\d+$');

  @override
  Future<bool> matches(
    DiscoveredDevice device,
    List<BleService> services,
  ) async {
    if (!services.any((service) => service.uuid == _deviceInfoServiceUuid)) {
      logger.d("'$device' has no service matching '$_deviceInfoServiceUuid'");
      return false;
    }
    String firmwareVersion = await _getFirmwareVersion(device);
    logger.d("Firmware Version: '$firmwareVersion'");

    logger.t("matches V2: ${_v2Regex.hasMatch(firmwareVersion)}");

    return _v1Regex.hasMatch(firmwareVersion) ||
        _v2Regex.hasMatch(firmwareVersion);
  }

  @override
  Future<Wearable> createFromDevice(DiscoveredDevice device, { Set<ConnectionOption> options = const {} }) async {
    if (bleManager == null) {
      throw Exception("bleManager needs to be set before using the factory");
    }
    if (disconnectNotifier == null) {
      throw Exception(
        "disconnectNotifier needs to be set before using the factory",
      );
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
      (List<Sensor>, List<SensorConfiguration>) sensorInfo =
          await _initSensors(device);
      return OpenEarableV2(
        name: device.name,
        disconnectNotifier: disconnectNotifier!,
        sensors: sensorInfo.$1,
        sensorConfigurations: sensorInfo.$2,
        bleManager: bleManager!,
        discoveredDevice: device,
        availableMicrophones: {
          const OpenEarableV2Mic(id: 0, key: "Outer Microphone"),
          const OpenEarableV2Mic(id: 1, key: "Inner Microphone"),
        },
        availableAudioModes: {
          const NormalMode(),
          const TransparencyMode(),
          const NoiseCancellationMode(),
        },
        isConnectedViaSystem: options.contains(const ConnectedViaSystem()),
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
      softwareGenerationBytes =
          softwareGenerationBytes.sublist(0, firstZeroIndex);
    }
    return String.fromCharCodes(softwareGenerationBytes);
  }

  Future<(List<Sensor>, List<SensorConfiguration>)> _initSensors(
    DiscoveredDevice device,
  ) async {
    List<Sensor> sensors = [];
    List<SensorConfiguration> sensorConfigurations = [];
    SensorSchemeReader schemeParser =
        V2SensorSchemeReader(bleManager!, device.id);

    V2SensorHandler sensorManager = V2SensorHandler(
      bleManager: bleManager!,
      discoveredDevice: device,
      sensorSchemeParser: schemeParser,
      sensorValueParser: V2SensorValueParser(),
    );

    List<SensorScheme> sensorSchemes = await schemeParser.readSensorSchemes();

    for (SensorScheme scheme in sensorSchemes) {
      List<SensorConfigurationOpenEarableV2Value> sensorConfigurationValues = [];

      final features = scheme.options?.features ?? [];
      final hasStreaming = features.contains(SensorConfigFeatures.streaming);
      final hasRecording = features.contains(SensorConfigFeatures.recording);
      final hasFrequencies = features.contains(SensorConfigFeatures.frequencyDefinition);
      final frequencies = scheme.options?.frequencies?.frequencies ?? [];
      final maxStreamingIndex = scheme.options?.frequencies?.maxStreamingFreqIndex ?? -1;

      //TODO: handle case where no frequencies are defined
      if (hasFrequencies && frequencies.isNotEmpty) {
        for (int index = 0; index < frequencies.length; index++) {
          final frequency = frequencies[index];

          // Create base prototype
          final base = SensorConfigurationOpenEarableV2Value(
            frequencyHz: frequency,
            frequencyIndex: index,
          );

          // OFF value (base prototype)
          sensorConfigurationValues.add(base);

          // Clone with record option
          if (hasRecording) {
            sensorConfigurationValues.add(
              base.copyWith(
                options: {const RecordSensorConfigOption()},
              ),
            );
          }

          // Clone with streaming and stream+record options
          if (hasStreaming && index <= maxStreamingIndex) {
            sensorConfigurationValues.add(
              base.copyWith(
                options: {const StreamSensorConfigOption()},
              ),
            );

            if (hasRecording) {
              sensorConfigurationValues.add(
                base.copyWith(
                  options: {
                    const StreamSensorConfigOption(),
                    const RecordSensorConfigOption(),
                  },
                ),
              );
            }
          }
        }
      }

      final offValue = sensorConfigurationValues
          .where((value) => value.options.isEmpty)
          .firstOrNull;

      if (sensorConfigurationValues.isEmpty) {
        logger.w("No configuration values generated for sensor: ${scheme.sensorName}");
      }

      final sensorConfiguration = SensorConfigurationOpenEarableV2(
        name: scheme.sensorName,
        values: sensorConfigurationValues,
        maxStreamingFreqIndex: maxStreamingIndex,
        sensorHandler: sensorManager,
        sensorId: scheme.sensorId,
        availableOptions: {
          if (hasStreaming) const StreamSensorConfigOption(),
          if (hasRecording) const RecordSensorConfigOption(),
        },
        offValue: offValue,
      );

      sensorConfigurations.add(sensorConfiguration);

      if (scheme.options?.features.contains(SensorConfigFeatures.streaming) ?? false) {
        // Group components by group name
        final sensorGroups = <String, List<Component>>{};
        for (final component in scheme.components) {
          sensorGroups.putIfAbsent(component.groupName, () => []).add(component);
        }

        for (final groupName in sensorGroups.keys) {
          final axisNames = sensorGroups[groupName]!.map((c) => c.componentName).toList();
          final axisUnits = sensorGroups[groupName]!.map((c) => c.unitName).toList();

          final sensor = _OpenEarableSensorV2(
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
    required super.sensorName,
    required super.chartTitle,
    required super.shortChartTitle,
    required List<String> axisNames,
    required List<String> axisUnits,
    required SensorHandler sensorManager,
    super.relatedConfigurations,
  })  : _sensorId = sensorId,
        _axisNames = axisNames,
        _axisUnits = axisUnits,
        _sensorManager = sensorManager,
        super(
          timestampExponent: -6,
        );

  @override
  List<String> get axisNames => _axisNames;

  @override
  List<String> get axisUnits => _axisUnits;

  Stream<SensorDoubleValue> _createSingleDataSubscription(
    String componentName,
  ) {
    StreamController<SensorDoubleValue> streamController = StreamController();

    StreamSubscription subscription =
        _sensorManager.subscribeToSensorData(_sensorId).listen((data) {
      BigInt timestamp = data["timestamp"];
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
