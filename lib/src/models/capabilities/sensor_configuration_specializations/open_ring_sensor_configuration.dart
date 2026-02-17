import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:open_earable_flutter/src/managers/open_ring_sensor_handler.dart';
import 'package:open_earable_flutter/open_earable_flutter.dart' show logger;

import 'configurable_sensor_configuration.dart';
import 'sensor_frequency_configuration.dart';
import 'streamable_sensor_configuration.dart';

typedef OpenRingConfigurationAppliedCallback = void Function(
  OpenRingSensorConfiguration configuration,
  OpenRingSensorConfigurationValue value,
);

class OpenRingSensorConfiguration
    extends SensorFrequencyConfiguration<OpenRingSensorConfigurationValue>
    implements
        ConfigurableSensorConfiguration<OpenRingSensorConfigurationValue> {
  final OpenRingSensorHandler _sensorHandler;
  final Set<SensorConfigurationOption> _availableOptions;
  OpenRingConfigurationAppliedCallback? onConfigurationApplied;

  @override
  Set<SensorConfigurationOption> get availableOptions => _availableOptions;

  OpenRingSensorConfiguration({
    required super.name,
    required super.values,
    super.offValue,
    required OpenRingSensorHandler sensorHandler,
    Set<SensorConfigurationOption>? availableOptions,
    this.onConfigurationApplied,
  })  : _sensorHandler = sensorHandler,
        _availableOptions = availableOptions ?? {StreamSensorConfigOption()};

  @override
  void setConfiguration(OpenRingSensorConfigurationValue value) {
    onConfigurationApplied?.call(this, value);

    if (value.softwareToggleOnly) {
      _sensorHandler.setTemperatureStreamEnabled(value.streamData);
      return;
    }

    final payload = value.streamData ? value.startPayload : value.stopPayload;
    final config = OpenRingSensorConfig(cmd: value.cmd, payload: payload);
    unawaited(
      _sensorHandler.writeSensorConfig(config).catchError((
        Object error,
        StackTrace stackTrace,
      ) {
        logger.e(
          'Failed to apply OpenRing sensor config '
          '(cmd=${value.cmd}, stream=${value.streamData}): $error',
        );
        logger.t(stackTrace);
      }),
    );
  }
}

class OpenRingSensorConfigurationValue extends SensorFrequencyConfigurationValue
    implements ConfigurableSensorConfigurationValue {
  final int cmd;
  final List<int> startPayload;
  final List<int> stopPayload;
  final bool softwareToggleOnly;

  @override
  final Set<SensorConfigurationOption> options;

  bool get streamData =>
      options.any((option) => option is StreamSensorConfigOption);

  OpenRingSensorConfigurationValue({
    required super.frequencyHz,
    required this.cmd,
    required List<int> startPayload,
    required List<int> stopPayload,
    this.softwareToggleOnly = false,
    this.options = const {},
  })  : startPayload = List<int>.unmodifiable(startPayload),
        stopPayload = List<int>.unmodifiable(stopPayload),
        super(key: '${frequencyHz}Hz ${_optionsToString(options)}');

  @override
  OpenRingSensorConfigurationValue withoutOptions() {
    return OpenRingSensorConfigurationValue(
      frequencyHz: frequencyHz,
      cmd: cmd,
      startPayload: startPayload,
      stopPayload: stopPayload,
      softwareToggleOnly: softwareToggleOnly,
      options: const {},
    );
  }

  OpenRingSensorConfigurationValue copyWith({
    double? frequencyHz,
    Set<SensorConfigurationOption>? options,
  }) {
    return OpenRingSensorConfigurationValue(
      frequencyHz: frequencyHz ?? this.frequencyHz,
      cmd: cmd,
      startPayload: startPayload,
      stopPayload: stopPayload,
      softwareToggleOnly: softwareToggleOnly,
      options: options ?? this.options,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is OpenRingSensorConfigurationValue &&
        other.frequencyHz == frequencyHz &&
        other.cmd == cmd &&
        listEquals(other.startPayload, startPayload) &&
        listEquals(other.stopPayload, stopPayload) &&
        other.softwareToggleOnly == softwareToggleOnly &&
        setEquals(other.options, options);
  }

  @override
  int get hashCode =>
      frequencyHz.hashCode ^
      cmd.hashCode ^
      Object.hashAll(startPayload) ^
      Object.hashAll(stopPayload) ^
      softwareToggleOnly.hashCode ^
      options.hashCode;

  static String _optionsToString(Set<SensorConfigurationOption> options) {
    String trailer = 'off';
    if (options.any((option) => option is StreamSensorConfigOption)) {
      trailer = 'stream';
    }
    return trailer;
  }
}
