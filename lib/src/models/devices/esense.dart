import 'package:open_earable_flutter/src/models/capabilities/sensor.dart';

import 'package:open_earable_flutter/src/models/capabilities/sensor_configuration.dart';

import '../../managers/ble_gatt_manager.dart';
import '../capabilities/sensor_configuration_manager.dart';
import '../capabilities/sensor_manager.dart';
import 'discovered_device.dart';
import 'wearable.dart';

const String esenseServiceUuid = "ff06";
const String esenseSensorConfigCharacteristicUuid = "ff07";
const String esenseSensorDataCharacteristicUuid = "0000ff08-0000-1000-8000-00805f9b34fb";

class Esense extends Wearable
    implements SensorManager, SensorConfigurationManager {
  final DiscoveredDevice _discoveredDevice;
  final BleGattManager _bleManager;

  final List<SensorConfiguration<SensorConfigurationValue>> _sensorConfigs;
  final List<Sensor<SensorValue>> _sensors;

  @override
  String get deviceId => _discoveredDevice.id;

  Esense({
    required super.name,
    required super.disconnectNotifier,
    required BleGattManager bleManager,
    required DiscoveredDevice discoveredDevice,
    List<SensorConfiguration<SensorConfigurationValue>> sensorConfigurations = const [],
    List<Sensor<SensorValue>> sensors = const [],
  })  : _discoveredDevice = discoveredDevice,
        _bleManager = bleManager,
        _sensorConfigs = sensorConfigurations,
        _sensors = sensors;

  @override
  Future<void> disconnect() {
    return _bleManager.disconnect(deviceId);
  }

  @override
  // TODO: implement sensorConfigurationStream
  Stream<
      Map<SensorConfiguration<SensorConfigurationValue>,
          SensorConfigurationValue>> get sensorConfigurationStream =>
      Stream.empty();

  @override
  // TODO: implement sensorConfigurations
  List<SensorConfiguration<SensorConfigurationValue>>
      get sensorConfigurations => _sensorConfigs;

  @override
  // TODO: implement sensors
  List<Sensor<SensorValue>> get sensors => _sensors;
}
