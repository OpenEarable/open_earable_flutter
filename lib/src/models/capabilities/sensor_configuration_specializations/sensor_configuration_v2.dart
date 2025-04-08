import '../../../managers/v2_sensor_handler.dart';
import 'sensor_frequency_configuration.dart';

class SensorConfigurationV2 extends SensorFrequencyConfiguration {
  final int sensorId;

  final int maxStreamingFreqIndex;
  final V2SensorHandler _sensorHandler;

  SensorConfigurationV2({
    required String name,
    required this.sensorId,
    required List<SensorConfigurationValueV2> values,
    required this.maxStreamingFreqIndex,
    required V2SensorHandler sensorHandler,
    String? unit,
  })  : _sensorHandler = sensorHandler,
        super(
          name: name,
          values: values,
          unit: "Hz",
        );

  @override
  String toString() {
    return 'SensorConfigurationV2(name: $name, values: $values, unit: $unit, maxStreamingFreqIndex: $maxStreamingFreqIndex)';
  }

  /// Sets the maximum frequency that supports streaming and recording
  @override
  void setMaximumFrequency({
    bool streamData = true,
    bool recordData = true,
  }) {
    if (values.isEmpty) {
      return;
    }

    SensorConfigurationValueV2? maxFrequencyAllEnabled;

    for (final value in values) {
      SensorConfigurationValueV2 valueCasted =
          value as SensorConfigurationValueV2;
      if (valueCasted.streamData != streamData ||
          valueCasted.recordData != recordData) {
        continue;
      }

      maxFrequencyAllEnabled ??= valueCasted;
      if (maxFrequencyAllEnabled.frequency < valueCasted.frequency) {
        maxFrequencyAllEnabled = valueCasted;
      }
    }

    if (maxFrequencyAllEnabled != null) {
      setConfiguration(maxFrequencyAllEnabled);
    }
  }

  @override
  void setConfiguration(SensorFrequencyConfigurationValue configuration) {
    if (configuration is! SensorConfigurationValueV2) {
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
    if (other is SensorConfigurationV2) {
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

class SensorConfigurationValueV2 extends SensorFrequencyConfigurationValue {
  final int frequencyIndex;
  final bool streamData;
  final bool recordData;

  SensorConfigurationValueV2({
    required double frequency,
    required this.frequencyIndex,
    required this.streamData,
    required this.recordData,
  }) : super(frequency: frequency);

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

    return "${frequency.toStringAsPrecision(4)} $trailer";
  }
}
