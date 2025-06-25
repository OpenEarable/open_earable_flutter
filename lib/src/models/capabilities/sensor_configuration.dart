/// A configuration for a sensor that defines its possible values and behavior.
/// This class is designed to be extended by specific sensor configuration implementations.
abstract class SensorConfiguration<SCV extends SensorConfigurationValue> {
  /// Name of the configuration
  /// This is used to identify the configuration in the UI or logs.
  final String name;
  /// A list of possible values for the sensor behavior.
  final List<SCV> values;

  /// Optional value that indicates the off state of the sensor.
  final SCV? offValue;

  /// Optional unit of the sensor configuration.
  /// For example, "Hz" for frequency when dealing with frequency configurations.
  final String? unit;

  const SensorConfiguration({
    required this.name,
    required this.values,
    this.offValue,
    this.unit,
  });

  /// Sets the configuration to the specified value.
  /// This method should be implemented by subclasses to apply the configuration.
  /// It is expected that the implementation will handle the specifics of how the configuration is applied.
  void setConfiguration(SCV configuration);

  @override
  String toString() {
    return 'SensorConfiguration(name: $name, values: $values, unit: $unit)';
  }
}

/// A value for a sensor configuration.
/// This class is designed to be extended by specific sensor configuration value implementations.
/// It represents a single possible behavior for a sensor configuration.
class SensorConfigurationValue {
  /// The key of the configuration value.
  /// This key is used to identify the configuration value in the UI or logs.
  final String key;

  SensorConfigurationValue({
    required this.key,
  });

  @override
  String toString() {
    return key;
  }
}
