import '../models/capabilities/sensor_configuration.dart';
import '../models/capabilities/sensor_configuration_specializations/configurable_sensor_configuration.dart';
import '../models/capabilities/sensor_configuration_specializations/sensor_frequency_configuration.dart';
import '../models/capabilities/sensor_configuration_specializations/streamable_sensor_configuration.dart';

/// A selectable raw-sensor rate, with streaming independently enabled or disabled.
class OmniBudsRateValue extends SensorFrequencyConfigurationValue
    implements ConfigurableSensorConfigurationValue {
  /// The rates are those advertised by the official app, not throughput promises.
  OmniBudsRateValue(double frequencyHz, {this.enabled = true})
      : super(
          frequencyHz: frequencyHz,
          key: '$frequencyHz Hz ${enabled ? "stream" : "off"}',
        );
  final bool enabled;
  @override
  Set<SensorConfigurationOption> get options =>
      {if (enabled) const StreamSensorConfigOption()};
  @override
  OmniBudsRateValue withoutOptions() =>
      OmniBudsRateValue(frequencyHz, enabled: false);
  @override
  bool operator ==(Object other) =>
      other is OmniBudsRateValue &&
      other.frequencyHz == frequencyHz &&
      other.enabled == enabled;
  @override
  int get hashCode => Object.hash(frequencyHz, enabled);
}

/// Frequency configuration using the common library UI, plus an awaitable API.
class OmniBudsRateConfiguration
    extends SensorFrequencyConfiguration<OmniBudsRateValue>
    implements ConfigurableSensorConfiguration<OmniBudsRateValue> {
  /// Creates the supported on/off combinations for one ear and sensor.
  OmniBudsRateConfiguration({
    required super.name,
    required List<double> rates,
    required Future<void> Function(OmniBudsRateValue) apply,
    required void Function(Object) reportError,
  })  : _apply = apply,
        _reportError = reportError,
        super(
          values: [
            for (final hz in rates) ...[
              OmniBudsRateValue(hz),
              OmniBudsRateValue(hz, enabled: false),
            ],
          ],
          offValue: OmniBudsRateValue(rates.first, enabled: false),
        );

  final Future<void> Function(OmniBudsRateValue) _apply;
  final void Function(Object) _reportError;
  @override
  Set<SensorConfigurationOption> get availableOptions =>
      {const StreamSensorConfigOption()};

  /// Completes after the device acknowledges the change; rejects invalid values.
  Future<void> apply(OmniBudsRateValue value) {
    if (!values.contains(value)) throw ArgumentError.value(value, 'value');
    return _apply(value);
  }

  @override
  void setConfiguration(OmniBudsRateValue configuration) {
    apply(configuration).catchError(_reportError);
  }
}

/// On/off value for an on-device algorithm with no verified fixed sample rate.
class OmniBudsToggleValue extends SensorConfigurationValue
    implements ConfigurableSensorConfigurationValue {
  /// Creates a streaming switch; no artificial Hz value is assigned.
  OmniBudsToggleValue(this.enabled) : super(key: enabled ? 'Stream' : 'Off');
  final bool enabled;
  @override
  Set<SensorConfigurationOption> get options =>
      {if (enabled) const StreamSensorConfigOption()};
  @override
  OmniBudsToggleValue withoutOptions() => OmniBudsToggleValue(false);
  @override
  bool operator ==(Object other) =>
      other is OmniBudsToggleValue && other.enabled == enabled;
  @override
  int get hashCode => enabled.hashCode;
}

/// Enables a vendor algorithm without claiming a raw sampling frequency.
class OmniBudsToggleConfiguration
    extends SensorConfiguration<OmniBudsToggleValue>
    implements ConfigurableSensorConfiguration<OmniBudsToggleValue> {
  /// Creates an awaitable configuration for one vital-sign stream.
  OmniBudsToggleConfiguration({
    required super.name,
    required Future<void> Function(OmniBudsToggleValue) apply,
    required void Function(Object) reportError,
  })  : _apply = apply,
        _reportError = reportError,
        super(
          values: [OmniBudsToggleValue(false), OmniBudsToggleValue(true)],
          offValue: OmniBudsToggleValue(false),
        );
  final Future<void> Function(OmniBudsToggleValue) _apply;
  final void Function(Object) _reportError;
  @override
  Set<SensorConfigurationOption> get availableOptions =>
      {const StreamSensorConfigOption()};

  /// Completes only after the configuration response confirms success.
  Future<void> apply(OmniBudsToggleValue value) {
    if (!values.contains(value)) throw ArgumentError.value(value, 'value');
    return _apply(value);
  }

  @override
  void setConfiguration(OmniBudsToggleValue configuration) {
    apply(configuration).catchError(_reportError);
  }
}
