import '../../../managers/v2_sensor_handler.dart';
import 'sensor_frequency_configuration.dart';

class SensorConfigurationOpenEarableV2 extends SensorFrequencyConfiguration {
  final int sensorId;

  final int maxStreamingFreqIndex;
  final V2SensorHandler _sensorHandler;

  SensorConfigurationOpenEarableV2({
    required String name,
    required this.sensorId,
    required List<SensorConfigurationOpenEarableV2Value> values,
    required this.maxStreamingFreqIndex,
    required V2SensorHandler sensorHandler,
    String? unit,
  })  : _sensorHandler = sensorHandler,
        super(
          name: name,
          values: values,
        );

  @override
  String toString() {
    return 'SensorConfigurationV2(name: $name, values: $values, unit: $unit, maxStreamingFreqIndex: $maxStreamingFreqIndex)';
  }

  /// Sets the maximum frequency that supports the specified flags.
  ///
  /// Returns the value set or null.
  @override
  SensorConfigurationOpenEarableV2Value? setMaximumFrequency({
    bool streamData = true,
    bool recordData = true,
  }) {
    if (values.isEmpty) {
      return null;
    }

    SensorConfigurationOpenEarableV2Value? maxFrequencyAllEnabled;

    for (final value in values) {
      SensorConfigurationOpenEarableV2Value valueCasted =
          value as SensorConfigurationOpenEarableV2Value;
      if (valueCasted.streamData != streamData ||
          valueCasted.recordData != recordData) {
        continue;
      }

      maxFrequencyAllEnabled ??= valueCasted;
      if (maxFrequencyAllEnabled.frequencyHz < valueCasted.frequencyHz) {
        maxFrequencyAllEnabled = valueCasted;
      }
    }

    if (maxFrequencyAllEnabled != null) {
      setConfiguration(maxFrequencyAllEnabled);
    }
    return maxFrequencyAllEnabled;
  }

  /// Sets the frequency close to [targetFrequencyHz] that supports the
  /// specified flags.
  /// Either the next biggest or the maximum frequency.
  ///
  /// Returns the value set or null.
  @override
  SensorFrequencyConfigurationValue? setFrequencyBestEffort(
    double targetFrequencyHz, {
    bool streamData = true,
    bool recordData = true,
  }) {
    SensorFrequencyConfigurationValue? nextSmaller;
    SensorFrequencyConfigurationValue? nextBigger;

    for (final value in values) {
      SensorConfigurationOpenEarableV2Value valueCasted =
          value as SensorConfigurationOpenEarableV2Value;
      if (valueCasted.streamData != streamData ||
          valueCasted.recordData != recordData) {
        continue;
      }

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

    SensorFrequencyConfigurationValue? newValue = nextBigger ?? nextSmaller;
    if (newValue != null) {
      setConfiguration(newValue);
    }
    return newValue;
  }

  @override
  void setConfiguration(SensorFrequencyConfigurationValue configuration) {
    if (configuration is! SensorConfigurationOpenEarableV2Value) {
      throw ArgumentError("Expects SensorConfigurationValueV2");
    }

    V2SensorConfig sensorConfig = V2SensorConfig(
      sensorId: sensorId,
      sampleRateIndex: configuration.frequencyIndex,
      streamData: configuration.streamData,
      storeData: configuration.recordData,
    );
    _sensorHandler.writeSensorConfig(sensorConfig);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is SensorConfigurationOpenEarableV2) {
      return name == other.name &&
          values == other.values &&
          unit == other.unit &&
          maxStreamingFreqIndex == other.maxStreamingFreqIndex;
    }
    return false;
  }

  @override
  int get hashCode =>
      name.hashCode ^
      values.hashCode ^
      unit.hashCode ^
      maxStreamingFreqIndex.hashCode;
}

class SensorConfigurationOpenEarableV2Value
    extends SensorFrequencyConfigurationValue {
  final int frequencyIndex;
  final bool streamData;
  final bool recordData;

  SensorConfigurationOpenEarableV2Value({
    required double frequencyHz,
    required this.frequencyIndex,
    required this.streamData,
    required this.recordData,
  }) : super(frequencyHz: frequencyHz);

  @override
  String toString() {
    String trailer = "off";
    if (streamData && recordData) {
      trailer = "stream&record";
    } else if (streamData) {
      trailer = "stream";
    } else if (recordData) {
      trailer = "record";
    }

    return "${frequencyHz.toStringAsPrecision(4)} $trailer";
  }
}
