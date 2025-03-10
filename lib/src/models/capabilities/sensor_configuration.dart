abstract class SensorConfiguration<SCV extends SensorConfigurationValue> {
  // Name of the configuration
  final String name;
  final List<SCV> values;

  final String? unit;

  const SensorConfiguration({
    required this.name,
    required this.values,
    this.unit,
  });

  void setConfiguration(SCV configuration);

  @override
  String toString() {
    return 'SensorConfiguration(name: $name, values: $values, unit: $unit)';
  }
}

class SensorConfigurationValue {
  final String key;

  SensorConfigurationValue({
    required this.key,
  });

  @override
  String toString() {
    return key;
  }
}
