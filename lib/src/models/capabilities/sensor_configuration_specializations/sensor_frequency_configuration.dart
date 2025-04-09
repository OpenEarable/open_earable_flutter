import '../sensor_configuration.dart';

abstract class SensorFrequencyConfiguration<
        SFC extends SensorFrequencyConfigurationValue>
    extends SensorConfiguration<SensorFrequencyConfigurationValue> {
  const SensorFrequencyConfiguration({
    required String name,
    required List<SensorFrequencyConfigurationValue> values,
  }) : super(
          name: name,
          values: values,
          unit: "Hz",
        );

  @override
  String toString() {
    return 'SensorFrequencyConfiguration(name: $name, values: $values, unit: $unit)';
  }

  void setMaximumFrequency() {
    if (values.isEmpty) {
      return;
    }

    SensorFrequencyConfigurationValue maxFrequency = values.first;

    for (final value in values) {
      if (value.frequencyHz > maxFrequency.frequencyHz) {
        maxFrequency = value;
      }
    }

    setConfiguration(maxFrequency);
  }
}

class SensorFrequencyConfigurationValue extends SensorConfigurationValue {
  final double frequencyHz;

  SensorFrequencyConfigurationValue({
    required this.frequencyHz,
  }) : super(key: frequencyHz.toString());

  @override
  String toString() {
    return key;
  }
}
