import 'package:open_earable_flutter/src/models/capabilities/sensor_configuration_specializations/tau_ring_sensor_configuration.dart';
import 'package:open_earable_flutter/src/models/capabilities/sensor_specializations/tau_ring/tau_ring_sensor.dart';
import 'package:universal_ble/universal_ble.dart';

import '../../managers/tau_sensor_handler.dart';
import '../../utils/sensor_value_parser/tau_ring_value_parser.dart';
import '../capabilities/sensor.dart';
import '../capabilities/sensor_configuration.dart';
import '../wearable_factory.dart';
import 'discovered_device.dart';
import 'tau_ring.dart';
import 'wearable.dart';

class TauRingFactory extends WearableFactory {
  @override
  Future<Wearable> createFromDevice(DiscoveredDevice device, {Set<ConnectionOption> options = const {}}) {
    if (bleManager == null) {
      throw Exception("Can't create τ-Ring instance: bleManager not set in factory");
    }
    if (disconnectNotifier == null) {
      throw Exception("Can't create τ-Ring instance: disconnectNotifier not set in factory");
    }
  
    final sensorHandler = TauSensorHandler(
      discoveredDevice: device,
      bleManager: bleManager!,
      sensorValueParser: TauRingValueParser(),
    );

    List<SensorConfiguration> sensorConfigs = [
      TauRingSensorConfiguration(
        name: "6-Axis IMU",
        values: [
          TauRingSensorConfigurationValue(key: "On", cmd: 0x40, subOpcode: 0x06),
          TauRingSensorConfigurationValue(key: "Off", cmd: 0x40, subOpcode: 0x00),
        ],
        sensorHandler: sensorHandler,
      ),
    ];
    List<Sensor> sensors = [
      TauRingSensor(
        sensorId: 0x40,
        sensorName: "Accelerometer",
        chartTitle: "Accelerometer",
        shortChartTitle: "Accel",
        axisNames: ["X", "Y", "Z"],
        axisUnits: ["g", "g", "g"],
        sensorHandler: sensorHandler,
      ),
      TauRingSensor(
        sensorId: 0x40,
        sensorName: "Gyroscope",
        chartTitle: "Gyroscope",
        shortChartTitle: "Gyro",
        axisNames: ["X", "Y", "Z"],
        axisUnits: ["dps", "dps", "dps"],
        sensorHandler: sensorHandler,
      ),
    ];

    final w = TauRing(
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
    return services.any((s) => s.uuid.toLowerCase() == TauRingGatt.service);
  }
}
