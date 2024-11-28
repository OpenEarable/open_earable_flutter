abstract class SensorConfiguration {
  // Name of the configuration
  final String name;
  final List<SensorConfigurationValue> values;

  final String? unit;

  const SensorConfiguration({
    required this.name,
    required this.values,
    this.unit,
  });

  void setConfiguration(SensorConfigurationValue configuration);

  @override
  String toString() {
    return 'SensorConfiguration(name: $name, values: $values, unit: $unit)';
  }
}

class SensorConfigurationValue {
  final String key;

  const SensorConfigurationValue({
    required this.key,
  });

  @override
  String toString() {
    return key;
  }
}
