import 'package:open_earable_flutter/src/managers/open_ring_sensor_handler.dart';

import '../sensor_configuration.dart';

class OpenRingSensorConfiguration extends SensorConfiguration<OpenRingSensorConfigurationValue> {

  final OpenRingSensorHandler _sensorHandler;

  OpenRingSensorConfiguration({required super.name, required super.values, required OpenRingSensorHandler sensorHandler})
      : _sensorHandler = sensorHandler;

  @override
  void setConfiguration(OpenRingSensorConfigurationValue value) {
    OpenRingSensorConfig config = OpenRingSensorConfig(
      cmd: value.cmd,
      subOpcode: value.subOpcode,
    );

    _sensorHandler.writeSensorConfig(config);
  }
}

class OpenRingSensorConfigurationValue extends SensorConfigurationValue {
  final int cmd;
  final int subOpcode;

  OpenRingSensorConfigurationValue({
    required super.key,
    required this.cmd,
    required this.subOpcode,
  });

  @override
  String toString() {
    return key;
  }
}
