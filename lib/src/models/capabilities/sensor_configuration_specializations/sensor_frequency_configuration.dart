import '../sensor_configuration.dart';

abstract class SensorFrequencyConfiguration<
        SFC extends SensorFrequencyConfigurationValue>
    extends SensorConfiguration<SFC> {
  const SensorFrequencyConfiguration({
    required String name,
    required List<SFC> values,
  }) : super(
          name: name,
          values: values,
          unit: "Hz",
        );

  @override
  String toString() {
    return 'SensorFrequencyConfiguration(name: $name, values: $values, unit: $unit)';
  }

  /// Sets the frequency close to [targetFrequencyHz].
  /// Either the next biggest or the maximum frequency.
  ///
  /// Returns the value set or null.
  SFC? setFrequencyBestEffort(
    int targetFrequencyHz,
  ) {
    SFC? nextSmaller;
    SFC? nextBigger;

    for (final value in values) {
      if (value.frequencyHz < targetFrequencyHz) {
        nextSmaller ??= value;
        if (value.frequencyHz > nextSmaller.frequencyHz) {
          nextSmaller = value;
        }
      }

      if (value.frequencyHz >= targetFrequencyHz) {
        nextBigger ??= value;
        if (value.frequencyHz < nextBigger.frequencyHz) {
          nextBigger = value;
        }
      }
    }

    SFC? newValue = nextBigger ?? nextSmaller;
    if (newValue != null) {
      setConfiguration(newValue);
    }
    return newValue;
  }

  /// Sets the maximum frequency.
  ///
  /// Returns the value set or null.
  SFC? setMaximumFrequency() {
    if (values.isEmpty) {
      return null;
    }

    SFC maxFrequency = values.first;

    for (final value in values) {
      if (value.frequencyHz > maxFrequency.frequencyHz) {
        maxFrequency = value;
      }
    }

    setConfiguration(maxFrequency);

    return maxFrequency;
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
