import 'package:open_earable_flutter/src/models/capabilities/sensor_configuration_specializations/open_ring_sensor_configuration.dart';
import 'package:open_earable_flutter/src/models/capabilities/sensor_specializations/open_ring/open_ring_sensor.dart';
import 'package:universal_ble/universal_ble.dart';

import '../../managers/open_ring_sensor_handler.dart';
import '../../utils/sensor_value_parser/open_ring_value_parser.dart';
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
  }) {
    if (bleManager == null) {
      throw Exception("Can't create OpenRing instance: bleManager not set in factory");
    }
    if (disconnectNotifier == null) {
      throw Exception("Can't create OpenRing instance: disconnectNotifier not set in factory");
    }

    final sensorHandler = OpenRingSensorHandler(
      discoveredDevice: device,
      bleManager: bleManager!,
      sensorValueParser: OpenRingValueParser(),
    );

    List<SensorConfiguration> sensorConfigs = [
        OpenRingSensorConfiguration(
        name: "6-Axis IMU",
        values: [
          OpenRingSensorConfigurationValue(
            key: "On",
            cmd: 0x40,
            payload: [0x06],
          ),
          OpenRingSensorConfigurationValue(
            key: "Off",
            cmd: 0x40,
            payload: [0x00],
          ),
        ],
        sensorHandler: sensorHandler,
      ),
      OpenRingSensorConfiguration(
        name: "PPG",
        values: [
          OpenRingSensorConfigurationValue(
            key: "On",
            cmd: OpenRingGatt.cmdPPGQ2,
            payload: [
              0x01, // start
              0x00, // collectionTime (continuous)
              0x19, // acquisition parameter (firmware-fixed)
              0x01, // enable waveform streaming
              0x01, // enable progress packets
            ],
          ),
          OpenRingSensorConfigurationValue(
            key: "Off",
            cmd: OpenRingGatt.cmdPPGQ2,
            payload: [
              0x00, // stop
              0x00, // collectionTime
              0x19, // acquisition parameter
              0x00, // disable waveform streaming
              0x00, // disable progress packets
            ],
          ),
        ],
        sensorHandler: sensorHandler,
      ),
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
        axisNames: ["Red", "Infrared", "AccX", "AccY", "AccZ"],
        axisUnits: ["raw", "raw", "raw", "raw", "raw"],
        sensorHandler: sensorHandler,
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
    );
    return Future.value(w);
  }

  @override
  Future<bool> matches(DiscoveredDevice device, List<BleService> services) async {
    return services.any((s) => s.uuid.toLowerCase() == OpenRingGatt.service);
  }
}
