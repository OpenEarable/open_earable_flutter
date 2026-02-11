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
  Future<Wearable> createFromDevice(DiscoveredDevice device, {Set<ConnectionOption> options = const {}}) {
    if (bleManager == null) {
      throw Exception("Can't create τ-Ring instance: bleManager not set in factory");
    }
    if (disconnectNotifier == null) {
      throw Exception("Can't create τ-Ring instance: disconnectNotifier not set in factory");
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
          OpenRingSensorConfigurationValue(key: "On", cmd: 0x40, subOpcode: 0x06),
          OpenRingSensorConfigurationValue(key: "Off", cmd: 0x40, subOpcode: 0x00),
        ],
        sensorHandler: sensorHandler,
      ),
      OpenRingSensorConfiguration(
        name: "PPG",
        values: [
          OpenRingSensorConfigurationValue(key: "On", cmd: OpenRingGatt.cmdPPGQ2, subOpcode: 0x01),
          OpenRingSensorConfigurationValue(key: "Off", cmd: OpenRingGatt.cmdPPGQ2, subOpcode: 0x00),
        ],
        sensorHandler: sensorHandler,
      ),
    ];
    List<Sensor> sensors = [
      OpenRingSensor(
        sensorId: 0x40,
        sensorName: "Accelerometer",
        chartTitle: "Accelerometer",
        shortChartTitle: "Accel",
        axisNames: ["X", "Y", "Z"],
        axisUnits: ["g", "g", "g"],
        sensorHandler: sensorHandler,
      ),
      OpenRingSensor(
        sensorId: 0x40,
        sensorName: "Gyroscope",
        chartTitle: "Gyroscope",
        shortChartTitle: "Gyro",
        axisNames: ["X", "Y", "Z"],
        axisUnits: ["dps", "dps", "dps"],
        sensorHandler: sensorHandler,
      ),
      OpenRingSensor(
        sensorId: OpenRingGatt.cmdPPGQ2,
        sensorName: "PPG",
        chartTitle: "PPG",
        shortChartTitle: "PPG",
        axisNames: ["Green", "Red", "Infrared"],
        axisUnits: ["raw", "raw", "raw"],
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
