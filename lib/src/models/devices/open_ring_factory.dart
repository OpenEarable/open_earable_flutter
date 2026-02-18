import 'dart:async';

import 'package:open_earable_flutter/src/models/capabilities/sensor_configuration_specializations/open_ring_sensor_configuration.dart';
import 'package:open_earable_flutter/src/models/capabilities/sensor_configuration_specializations/streamable_sensor_configuration.dart';
import 'package:open_earable_flutter/src/models/capabilities/sensor_specializations/open_ring/open_ring_sensor.dart';
import 'package:universal_ble/universal_ble.dart';
import '../../../open_earable_flutter.dart' show logger;

import '../../managers/open_ring_sensor_handler.dart';
import '../../utils/sensor_value_parser/open_ring_value_parser.dart';
import '../capabilities/sensor_configuration_specializations/configurable_sensor_configuration.dart';
import '../capabilities/time_synchronizable.dart';
import '../capabilities/sensor.dart';
import '../capabilities/sensor_configuration.dart';
import '../wearable_factory.dart';
import 'discovered_device.dart';
import 'open_ring.dart';
import 'wearable.dart';

class OpenRingFactory extends WearableFactory {
  @override
  Future<Wearable> createFromDevice(
    DiscoveredDevice device, {
    Set<ConnectionOption> options = const {},
  }) async {
    if (bleManager == null) {
      throw Exception(
        "Can't create OpenRing instance: bleManager not set in factory",
      );
    }
    if (disconnectNotifier == null) {
      throw Exception(
        "Can't create OpenRing instance: disconnectNotifier not set in factory",
      );
    }

    final sensorHandler = OpenRingSensorHandler(
      discoveredDevice: device,
      bleManager: bleManager!,
      sensorValueParser: OpenRingValueParser(),
    );

    // OpenRing exposes one realtime rate per stream; represent it as fixed Hz.
    const double imuFrequencyHz = 50.0;
    const double ppgFrequencyHz = 50.0;
    const double temperatureFrequencyHz = 50.0;
    final streamOnly = Set<SensorConfigurationOption>.unmodifiable({
      StreamSensorConfigOption(),
    });

    List<OpenRingSensorConfigurationValue> singleRateValues({
      required double frequencyHz,
      required int cmd,
      required List<int> startPayload,
      required List<int> stopPayload,
      bool softwareToggleOnly = false,
    }) {
      final base = OpenRingSensorConfigurationValue(
        frequencyHz: frequencyHz,
        cmd: cmd,
        startPayload: startPayload,
        stopPayload: stopPayload,
        softwareToggleOnly: softwareToggleOnly,
      );
      return [base, base.copyWith(options: streamOnly)];
    }

    final imuConfigValues = singleRateValues(
      frequencyHz: imuFrequencyHz,
      cmd: OpenRingGatt.cmdIMU,
      // 6-axis standalone mode (accel + gyro).
      // When PPG is active, motion channels are sourced from cmdPPGQ2 packets.
      startPayload: [0x06],
      stopPayload: [0x00],
    );
    final imuSensorConfig = OpenRingSensorConfiguration(
      name: "6-Axis IMU",
      values: imuConfigValues,
      offValue: imuConfigValues.firstWhere((value) => value.options.isEmpty),
      sensorHandler: sensorHandler,
      availableOptions: streamOnly,
    );

    final ppgConfigValues = singleRateValues(
      frequencyHz: ppgFrequencyHz,
      cmd: OpenRingGatt.cmdPPGQ2,
      startPayload: [
        0x00, // start Q2 collection (LmAPI GET_HEART_Q2)
        0x00, // collectionTime = 0s (continuous streaming mode)
        0x19, // acquisition parameter (firmware-fixed)
        0x01, // enable waveform streaming
        0x01, // enable progress packets
      ],
      stopPayload: [
        0x06, // stop Q2 collection (LmAPI STOP_Q2)
      ],
    );
    final ppgSensorConfig = OpenRingSensorConfiguration(
      name: "PPG",
      values: ppgConfigValues,
      offValue: ppgConfigValues.firstWhere((value) => value.options.isEmpty),
      sensorHandler: sensorHandler,
      availableOptions: streamOnly,
    );

    final temperatureConfigValues = singleRateValues(
      frequencyHz: temperatureFrequencyHz,
      cmd: OpenRingGatt.cmdPPGQ2,
      startPayload: const [],
      stopPayload: const [],
      softwareToggleOnly: true,
    );
    final temperatureSensorConfig = OpenRingSensorConfiguration(
      name: "Temperature",
      values: temperatureConfigValues,
      offValue: temperatureConfigValues.firstWhere(
        (value) => value.options.isEmpty,
      ),
      sensorHandler: sensorHandler,
      availableOptions: streamOnly,
    );

    List<SensorConfiguration> sensorConfigs = [
      imuSensorConfig,
      ppgSensorConfig,
      temperatureSensorConfig,
    ];
    List<Sensor> sensors = [
      OpenRingSensor(
        sensorId: OpenRingGatt.cmdIMU,
        sensorName: "Accelerometer",
        chartTitle: "Accelerometer",
        shortChartTitle: "Acc.",
        axisNames: ["X", "Y", "Z"],
        axisUnits: ["g", "g", "g"],
        sensorHandler: sensorHandler,
        relatedConfigurations: [imuSensorConfig],
      ),
      OpenRingSensor(
        sensorId: OpenRingGatt.cmdIMU,
        sensorName: "Gyroscope",
        chartTitle: "Gyroscope",
        shortChartTitle: "Gyr.",
        axisNames: ["X", "Y", "Z"],
        axisUnits: ["dps", "dps", "dps"],
        sensorHandler: sensorHandler,
        relatedConfigurations: [imuSensorConfig],
      ),
      OpenRingSensor(
        sensorId: OpenRingGatt.cmdPPGQ2,
        sensorName: "PPG",
        chartTitle: "PPG",
        shortChartTitle: "PPG",
        axisNames: ["Infrared", "Red", "Green"],
        axisUnits: ["raw", "raw", "raw"],
        sensorHandler: sensorHandler,
        relatedConfigurations: [ppgSensorConfig],
      ),
      OpenRingSensor(
        sensorId: OpenRingGatt.cmdPPGQ2,
        sensorName: "Temperature",
        chartTitle: "Temperature",
        shortChartTitle: "Temp",
        axisNames: ["Temp0", "Temp1", "Temp2"],
        axisUnits: ["°C", "°C", "°C"],
        sensorHandler: sensorHandler,
        // Temperature uses software on/off and enables PPG transport automatically.
        relatedConfigurations: [temperatureSensorConfig],
      ),
    ];

    final w = OpenRing(
      discoveredDevice: device,
      deviceId: device.id,
      name: device.name,
      sensors: sensors,
      sensorConfigs: sensorConfigs,
      disconnectNotifier: disconnectNotifier!,
      bleManager: bleManager!,
      isSensorStreamingActive: () => sensorHandler.hasActiveRealtimeStreaming,
    );
    for (final config
        in sensorConfigs.whereType<OpenRingSensorConfiguration>()) {
      config.onConfigurationApplied = (configuration, value) {
        w.assumeConfigurationApplied(
          configuration: configuration,
          value: value,
        );
      };
    }

    final timeSync = OpenRingTimeSyncImp(
      bleManager: bleManager!,
      deviceId: device.id,
    );
    w.registerCapability<TimeSynchronizable>(timeSync);

    unawaited(
      _synchronizeTimeOnConnect(
        timeSync: timeSync,
        deviceId: device.id,
      ),
    );

    return w;
  }

  Future<void> _synchronizeTimeOnConnect({
    required TimeSynchronizable timeSync,
    required String deviceId,
  }) async {
    try {
      await timeSync.synchronizeTime();
      logger.i('OpenRing time synchronized on connect for $deviceId');
    } catch (error, stack) {
      logger.w('OpenRing time sync on connect failed for $deviceId: $error');
      logger.t(stack);
    }
  }

  @override
  Future<bool> matches(
    DiscoveredDevice device,
    List<BleService> services,
  ) async {
    return services.any((s) => s.uuid.toLowerCase() == OpenRingGatt.service);
  }
}
