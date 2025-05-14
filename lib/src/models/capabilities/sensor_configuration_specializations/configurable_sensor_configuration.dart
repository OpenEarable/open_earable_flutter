import 'package:flutter/foundation.dart';

import '../sensor_configuration.dart';

abstract class SensorConfigurationOption {
  final String name;

  const SensorConfigurationOption({
    required this.name,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is SensorConfigurationOption &&
        other.name == name;
  }
  @override
  int get hashCode => name.hashCode;

  @override
  String toString() {
    return "$runtimeType: $name";
  }
}

abstract class ConfigurableSensorConfiguration<SCV extends ConfigurableSensorConfigurationValue> extends SensorConfiguration<SCV> {
  final List<SensorConfigurationOption> availableOptions;

  ConfigurableSensorConfiguration({required super.name, required super.values, this.availableOptions = const []});
}

abstract class ConfigurableSensorConfigurationValue extends SensorConfigurationValue {
  final List<SensorConfigurationOption> options;

  ConfigurableSensorConfigurationValue({
    required super.key,
    this.options = const [],
  });

  @override
  String toString() {
    return '${super.toString()} (options: $options)';
  }

  ConfigurableSensorConfigurationValue withoutOptions();

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is ConfigurableSensorConfigurationValue &&
        withoutOptions() == other.withoutOptions() &&
        listEquals(options, other.options);
  }
  
  @override
  int get hashCode => super.hashCode ^ options.hashCode;
}
