import 'package:open_earable_flutter/src/managers/tau_sensor_handler.dart';

import '../sensor_configuration.dart';

class TauRingSensorConfiguration extends SensorConfiguration<TauRingSensorConfigurationValue> {

  final TauSensorHandler _sensorHandler;

  TauRingSensorConfiguration({required super.name, required super.values, required TauSensorHandler sensorHandler})
      : _sensorHandler = sensorHandler;

  @override
  void setConfiguration(TauRingSensorConfigurationValue value) {
    TauSensorConfig config = TauSensorConfig(
      cmd: value.cmd,
      subOpcode: value.subOpcode,
    );

    _sensorHandler.writeSensorConfig(config);
  }
}

class TauRingSensorConfigurationValue extends SensorConfigurationValue {
  final int cmd;
  final int subOpcode;

  TauRingSensorConfigurationValue({
    required super.key,
    required this.cmd,
    required this.subOpcode,
  });

  @override
  String toString() {
    return key;
  }
}
