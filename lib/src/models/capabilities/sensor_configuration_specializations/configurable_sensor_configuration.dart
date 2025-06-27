import 'package:flutter/foundation.dart';

import '../sensor_configuration.dart';

/// Base class for sensor configuration options.
/// This class represents a configuration option that can be applied to a [ConfigurableSensorConfiguration].
abstract class SensorConfigurationOption {
  /// The name of the configuration option.
  /// This name is used to identify the option in the UI or logs.
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

/// A [SensorConfiguration] specialization that allows for configurable options.
/// This class extends [SensorConfiguration] and adds a set of available options that can be applied
/// to the configuration values. It is designed to be used with [ConfigurableSensorConfigurationValue].
/// This class provides a way to manage sensor configurations that can have multiple behaviors based on the options applied.
abstract class ConfigurableSensorConfiguration<SCV extends ConfigurableSensorConfigurationValue> extends SensorConfiguration<SCV> {
  /// A set of all available options for values of this configuration.
  final Set<SensorConfigurationOption> availableOptions;

  ConfigurableSensorConfiguration({required super.name, required super.values, this.availableOptions = const {}});
}

/// A base class for sensor configuration values that can be configured with options.
/// This class extends [SensorConfigurationValue] and adds a set of options that can be applied
/// to the configuration value. It is designed to be used with [ConfigurableSensorConfiguration].
abstract class ConfigurableSensorConfigurationValue extends SensorConfigurationValue {
  final Set<SensorConfigurationOption> options;

  ConfigurableSensorConfigurationValue({
    required super.key,
    this.options = const {},
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
        setEquals(options, other.options);
  }
  
  @override
  int get hashCode => super.hashCode ^ options.hashCode;
}
