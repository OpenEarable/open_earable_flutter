import 'package:open_earable_flutter/src/managers/open_ring_sensor_handler.dart';

import '../sensor_configuration.dart';

class OpenRingSensorConfiguration
    extends SensorConfiguration<OpenRingSensorConfigurationValue> {
  final OpenRingSensorHandler _sensorHandler;

  OpenRingSensorConfiguration({
    required super.name,
    required super.values,
    super.offValue,
    required OpenRingSensorHandler sensorHandler,
  }) : _sensorHandler = sensorHandler;

  @override
  void setConfiguration(OpenRingSensorConfigurationValue value) {
    if (value.temperatureStreamEnabled != null) {
      _sensorHandler.setTemperatureStreamEnabled(
        value.temperatureStreamEnabled!,
      );
      return;
    }

    final config = OpenRingSensorConfig(cmd: value.cmd, payload: value.payload);

    _sensorHandler.writeSensorConfig(config);
  }
}

class OpenRingSensorConfigurationValue extends SensorConfigurationValue {
  final int cmd;
  final List<int> payload;
  final bool? temperatureStreamEnabled;

  OpenRingSensorConfigurationValue({
    required super.key,
    required this.cmd,
    required this.payload,
    this.temperatureStreamEnabled,
  });

  @override
  String toString() => key;
}
