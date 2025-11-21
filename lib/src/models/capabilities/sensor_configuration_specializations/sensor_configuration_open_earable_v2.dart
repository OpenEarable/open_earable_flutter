import 'package:flutter/foundation.dart';

import 'configurable_sensor_configuration.dart';
import 'recordable_sensor_configuration.dart';
import 'streamable_sensor_configuration.dart';
import '../../../managers/v2_sensor_handler.dart';
import 'sensor_frequency_configuration.dart';

class SensorConfigurationOpenEarableV2 extends SensorFrequencyConfiguration<SensorConfigurationOpenEarableV2Value> implements ConfigurableSensorConfiguration<SensorConfigurationOpenEarableV2Value> {
  final int sensorId;

  final int maxStreamingFreqIndex;
  final V2SensorHandler _sensorHandler;

  final Set<SensorConfigurationOption> _availableOptions;

  @override
  Set<SensorConfigurationOption> get availableOptions => _availableOptions;

  SensorConfigurationOpenEarableV2({
    required super.name,
    required this.sensorId,
    required super.values,
    required this.maxStreamingFreqIndex,
    required V2SensorHandler sensorHandler,
    Set<SensorConfigurationOption> availableOptions = const {},
    super.offValue,
  })  : _sensorHandler = sensorHandler,
        _availableOptions = availableOptions;

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
      if (value.streamData != streamData ||
          value.recordData != recordData) {
        continue;
      }

      maxFrequencyAllEnabled ??= value;
      if (maxFrequencyAllEnabled.frequencyHz < value.frequencyHz) {
        maxFrequencyAllEnabled = value;
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
  SensorConfigurationOpenEarableV2Value? setFrequencyBestEffort(
    int targetFrequencyHz, {
    bool streamData = true,
    bool recordData = true,
  }) {
    SensorConfigurationOpenEarableV2Value? nextSmaller;
    SensorConfigurationOpenEarableV2Value? nextBigger;

    for (final value in values) {
      if (value.streamData != streamData ||
          value.recordData != recordData) {
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

    SensorConfigurationOpenEarableV2Value? newValue = nextBigger ?? nextSmaller;
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

// MARK: - Value

class SensorConfigurationOpenEarableV2Value
    extends SensorFrequencyConfigurationValue implements ConfigurableSensorConfigurationValue {
  final int frequencyIndex;
  bool get streamData => options.any((option) => option is StreamSensorConfigOption);
  bool get recordData => options.any((option) => option is RecordSensorConfigOption);

  @override
  final Set<SensorConfigurationOption> options;

  SensorConfigurationOpenEarableV2Value({
    required super.frequencyHz,
    required this.frequencyIndex,
    this.options = const {},
  }) : super(key: "${frequencyHz.toString()} ${_optionsToString(options)}");

  @override
  String toString() {
    String trailer = _optionsToString(options);
    return "${frequencyHz.toStringAsPrecision(4)} $trailer";
  }

  @override
  SensorConfigurationOpenEarableV2Value withoutOptions() {
    return SensorConfigurationOpenEarableV2Value(
      frequencyHz: frequencyHz,
      frequencyIndex: frequencyIndex,
      options: {},
    );
  }

  SensorConfigurationOpenEarableV2Value copyWith({
    double? frequencyHz,
    int? frequencyIndex,
    Set<SensorConfigurationOption>? options,
  }) {
    return SensorConfigurationOpenEarableV2Value(
      frequencyHz: frequencyHz ?? this.frequencyHz,
      frequencyIndex: frequencyIndex ?? this.frequencyIndex,
      options: options ?? this.options,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is SensorConfigurationOpenEarableV2Value &&
        other.frequencyHz == frequencyHz &&
        other.frequencyIndex == frequencyIndex &&
        setEquals(other.options, options);
  }
  @override
  int get hashCode => frequencyHz.hashCode ^ frequencyIndex.hashCode ^ options.hashCode;

  static String _optionsToString(Set<SensorConfigurationOption> options) {
    String trailer = "off";
    if (options.any((option) => option is StreamSensorConfigOption) &&
        options.any((option) => option is RecordSensorConfigOption)) {
      trailer = "stream&record";
    } else if (options.any((option) => option is StreamSensorConfigOption)) {
      trailer = "stream";
    } else if (options.any((option) => option is RecordSensorConfigOption)) {
      trailer = "record";
    }
    return trailer;
  }
}
