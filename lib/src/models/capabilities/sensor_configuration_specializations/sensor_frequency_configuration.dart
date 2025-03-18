import '../sensor_configuration.dart';

abstract class SensorFrequencyConfiguration extends SensorConfiguration {
  const SensorFrequencyConfiguration({
    required String name,
    required List<SensorFrequencyConfigurationValue> values,
    required String unit,
  }) : super(
          name: name,
          values: values,
          unit: unit,
        );

  @override
  String toString() {
    return 'SensorFrequencyConfiguration(name: $name, values: $values, unit: $unit)';
  }

  void setMaximumFrequency() {
    if (values.isEmpty) {
      return;
    }

    SensorFrequencyConfigurationValue maxFrequency =
        (values.first as SensorFrequencyConfigurationValue);

    for (final value in values) {
      if ((value as SensorFrequencyConfigurationValue).frequency >
          maxFrequency.frequency) {
        maxFrequency = value;
      }
    }

    setConfiguration(maxFrequency);
  }
}

class SensorFrequencyConfigurationValue extends SensorConfigurationValue {
  final int frequency;

  SensorFrequencyConfigurationValue({
    required this.frequency,
  }) : super(key: frequency.toString());

  @override
  String toString() {
    return key;
  }
}
