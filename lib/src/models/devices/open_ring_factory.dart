import 'dart:async';

import 'package:open_earable_flutter/src/models/capabilities/sensor_configuration_specializations/open_ring_sensor_configuration.dart';
import 'package:open_earable_flutter/src/models/capabilities/sensor_specializations/open_ring/open_ring_sensor.dart';
import 'package:universal_ble/universal_ble.dart';
import '../../../open_earable_flutter.dart' show logger;

import '../../managers/open_ring_sensor_handler.dart';
import '../../utils/sensor_value_parser/open_ring_value_parser.dart';
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

    final imuSensorConfig = OpenRingSensorConfiguration(
      name: "6-Axis IMU",
      values: [
        OpenRingSensorConfigurationValue(key: "On", cmd: 0x40, payload: [0x06]),
        OpenRingSensorConfigurationValue(
          key: "Off",
          cmd: 0x40,
          payload: [0x00],
        ),
      ],
      sensorHandler: sensorHandler,
    );

    final ppgSensorConfig = OpenRingSensorConfiguration(
      name: "PPG",
      values: [
        OpenRingSensorConfigurationValue(
          key: "On",
          cmd: OpenRingGatt.cmdPPGQ2,
          payload: [
            0x00, // start Q2 collection (LmAPI GET_HEART_Q2)
            0x1E, // collectionTime = 30s (LmAPI default)
            0x19, // acquisition parameter (firmware-fixed)
            0x01, // enable waveform streaming
            0x01, // enable progress packets
          ],
        ),
        OpenRingSensorConfigurationValue(
          key: "Off",
          cmd: OpenRingGatt.cmdPPGQ2,
          payload: [
            0x06, // stop Q2 collection (LmAPI STOP_Q2)
          ],
        ),
      ],
      sensorHandler: sensorHandler,
    );

    final temperatureSensorConfig = OpenRingSensorConfiguration(
      name: "Temperature",
      values: [
        OpenRingSensorConfigurationValue(
          key: "On",
          cmd: OpenRingGatt.cmdPPGQ2,
          payload: const [],
          temperatureStreamEnabled: true,
        ),
        OpenRingSensorConfigurationValue(
          key: "Off",
          cmd: OpenRingGatt.cmdPPGQ2,
          payload: const [],
          temperatureStreamEnabled: false,
        ),
      ],
      sensorHandler: sensorHandler,
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
      ),
      OpenRingSensor(
        sensorId: OpenRingGatt.cmdIMU,
        sensorName: "Gyroscope",
        chartTitle: "Gyroscope",
        shortChartTitle: "Gyr.",
        axisNames: ["X", "Y", "Z"],
        axisUnits: ["dps", "dps", "dps"],
        sensorHandler: sensorHandler,
      ),
      OpenRingSensor(
        sensorId: OpenRingGatt.cmdPPGQ2,
        sensorName: "PPG",
        chartTitle: "PPG",
        shortChartTitle: "PPG",
        axisNames: ["Infrared", "Red", "Green"],
        axisUnits: ["raw", "raw", "raw"],
        sensorHandler: sensorHandler,
      ),
      OpenRingSensor(
        sensorId: OpenRingGatt.cmdPPGQ2,
        sensorName: "Temperature",
        chartTitle: "Temperature",
        shortChartTitle: "Temp",
        axisNames: ["Temp0", "Temp1", "Temp2"],
        axisUnits: ["°C", "°C", "°C"],
        sensorHandler: sensorHandler,
        // Temperature uses software on/off. PPG must be enabled separately.
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
