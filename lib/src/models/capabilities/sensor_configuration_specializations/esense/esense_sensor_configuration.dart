import 'package:flutter/foundation.dart';
import 'package:open_earable_flutter/src/models/devices/esense.dart';

import '../../../../managers/esense_sensor_handler.dart';
import '../../../../managers/sensor_handler.dart';
import '../configurable_sensor_configuration.dart';
import '../sensor_frequency_configuration.dart';
import '../streamable_sensor_configuration.dart';

class EsenseSensorConfiguration extends SensorFrequencyConfiguration<EsenseSensorConfigurationValue>
    implements ConfigurableSensorConfiguration<EsenseSensorConfigurationValue> {
  final int _sensorCommand;
  final Set<SensorConfigurationOption> _availableOptions;

  final SensorHandler _sensorHandler;

  @override
  Set<SensorConfigurationOption> get availableOptions => _availableOptions;

  EsenseSensorConfiguration({
    required super.name,
    required super.values,
    required int sensorCommand,
    required SensorHandler sensorHandler,
    Set<SensorConfigurationOption> availableOptions = const {},
    super.offValue,
  }) : _sensorCommand = sensorCommand,
       _sensorHandler = sensorHandler,
       _availableOptions = availableOptions;

  @override
  void setConfiguration(EsenseSensorConfigurationValue configuration) {
    EsenseSensorConfig sensorConfig = EsenseSensorConfig(
      sensorId: _sensorCommand,
      sampleRate: configuration.frequencyHz.round(),
      streamData: configuration.options.any((option) => option is StreamSensorConfigOption),
    );
    _sensorHandler.writeSensorConfig(sensorConfig);
  }
}

// MARK: Value

class EsenseSensorConfigurationValue extends SensorFrequencyConfigurationValue
    implements ConfigurableSensorConfigurationValue {
  @override
  final Set<SensorConfigurationOption> options;

  EsenseSensorConfigurationValue({
    required super.frequencyHz,
    this.options = const {},
  }) : super(key: '${frequencyHz}Hz ${_optionsToString(options)}');

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is EsenseSensorConfigurationValue &&
        other.frequencyHz == frequencyHz &&
        other.options.length == options.length &&
        setEquals(other.options, options);
  }
  @override
  int get hashCode => frequencyHz.hashCode ^ options.hashCode;

  static String _optionsToString(Set<SensorConfigurationOption> options) {
    String trailer = "off";
    if (options.any((option) => option is StreamSensorConfigOption)) {
      trailer = "stream";
    }
    return trailer;
  }
  
  @override
  ConfigurableSensorConfigurationValue withoutOptions() {
    return EsenseSensorConfigurationValue(
      frequencyHz: frequencyHz,
      options: {},
    );
  }

  EsenseSensorConfigurationValue copyWith({
    double? frequencyHz,
    Set<SensorConfigurationOption>? options,
  }) {
    return EsenseSensorConfigurationValue(
      frequencyHz: frequencyHz ?? this.frequencyHz,
      options: options ?? this.options,
    );
  }
}
