import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:typed_data';

import '../sensor_forwarder.dart';
import '../../models/capabilities/sensor.dart';
import 'lsl/transport/lsl_transport.dart';
import 'lsl/transport/lsl_transport_stub.dart'
    if (dart.library.io) 'lsl/transport/lsl_transport_io.dart';

const int defaultLslBridgePort = 16571;
const String defaultLslStreamPrefix = 'OpenEarable';

/// Configuration for LSL forwarding.
///
/// The Flutter package forwards sensor samples as UDP JSON packets to a
/// middleware process which then publishes the data to LSL outlets.
class LslForwardingConfig {
  final bool enabled;
  final String host;
  final int port;
  final String streamPrefix;

  const LslForwardingConfig({
    this.enabled = false,
    this.host = '',
    this.port = defaultLslBridgePort,
    this.streamPrefix = defaultLslStreamPrefix,
  });

  bool get isConfigured => host.trim().isNotEmpty;

  LslForwardingConfig copyWith({
    bool? enabled,
    String? host,
    int? port,
    String? streamPrefix,
  }) {
    return LslForwardingConfig(
      enabled: enabled ?? this.enabled,
      host: host ?? this.host,
      port: port ?? this.port,
      streamPrefix: streamPrefix ?? this.streamPrefix,
    );
  }
}

/// Forwarder implementation that sends samples to an LSL bridge endpoint.
class LslForwarder implements SensorForwarder {
  LslForwarder._internal() : _transport = createLslTransport();

  static final LslForwarder instance = LslForwarder._internal();

  final LslTransport _transport;
  LslForwardingConfig _config = const LslForwardingConfig();

  DateTime? _lastForwardingError;
  bool _didLogUnsupportedPlatform = false;

  LslForwardingConfig get config => _config;
  bool get isSupported => _transport.isSupported;
  @override
  bool get isEnabled => _config.enabled;
  bool get isConfigured => _config.isConfigured;

  void configure({
    required String host,
    int port = defaultLslBridgePort,
    bool enabled = true,
    String streamPrefix = defaultLslStreamPrefix,
  }) {
    final trimmedHost = host.trim();
    if (trimmedHost.isEmpty) {
      throw ArgumentError.value(host, 'host', 'must not be empty');
    }
    if (port <= 0 || port > 65535) {
      throw ArgumentError.value(port, 'port', 'must be between 1 and 65535');
    }

    final trimmedPrefix = streamPrefix.trim();
    if (trimmedPrefix.isEmpty) {
      throw ArgumentError.value(
        streamPrefix,
        'streamPrefix',
        'must not be empty',
      );
    }

    _config = _config.copyWith(
      host: trimmedHost,
      port: port,
      enabled: enabled,
      streamPrefix: trimmedPrefix,
    );
  }

  @override
  void setEnabled(bool enabled) {
    _config = _config.copyWith(enabled: enabled);
  }

  void reset() {
    _config = const LslForwardingConfig();
  }

  /// Backwards-compatible convenience API.
  Future<void> forwardSample<SV extends SensorValue>({
    required Sensor<SV> sensor,
    required SV value,
    required String deviceId,
    required String deviceName,
  }) {
    return forward(
      SensorForwardingSample(
        sensor: sensor,
        value: value,
        deviceId: deviceId,
        deviceName: deviceName,
      ),
    );
  }

  @override
  Future<void> forward(SensorForwardingSample sample) async {
    final localConfig = _config;

    if (!localConfig.enabled || !localConfig.isConfigured) {
      return;
    }

    if (!_transport.isSupported) {
      if (!_didLogUnsupportedPlatform) {
        _didLogUnsupportedPlatform = true;
        developer.log(
          'LSL forwarding is not available on this platform. Sensor data stays local.',
          name: 'open_earable_flutter',
        );
      }
      return;
    }

    final payload = _buildPayload(sample, localConfig.streamPrefix);

    try {
      await _transport.send(payload, localConfig.host, localConfig.port);
    } catch (error, stackTrace) {
      final now = DateTime.now();
      final shouldLog = _lastForwardingError == null ||
          now.difference(_lastForwardingError!) >= const Duration(seconds: 5);
      if (shouldLog) {
        _lastForwardingError = now;
        developer.log(
          'Failed to forward sensor data to LSL bridge (${localConfig.host}:${localConfig.port}): $error',
          name: 'open_earable_flutter',
          stackTrace: stackTrace,
        );
      }
    }
  }

  Uint8List _buildPayload(
    SensorForwardingSample sample,
    String streamPrefix,
  ) {
    final sensor = sample.sensor;
    final value = sample.value;

    final streamName = _buildStreamName(
      streamPrefix: streamPrefix,
      deviceName: sample.deviceName,
      sensorName: sensor.sensorName,
    );

    final map = <String, dynamic>{
      'type': 'open_earable_lsl_sample',
      'stream_name': streamName,
      'device_id': sample.deviceId,
      'device_name': sample.deviceName,
      'sensor_name': sensor.sensorName,
      'chart_title': sensor.chartTitle,
      'short_chart_title': sensor.shortChartTitle,
      'axis_names': sensor.axisNames,
      'axis_units': sensor.axisUnits,
      'timestamp': value.timestamp,
      'timestamp_exponent': sensor.timestampExponent,
      'dimensions': value.dimensions,
      'values': _numericValues(value),
      'value_strings': value.valueStrings,
      'sent_at_unix_ms': DateTime.now().millisecondsSinceEpoch,
    };

    return Uint8List.fromList(utf8.encode(jsonEncode(map)));
  }

  String _buildStreamName({
    required String streamPrefix,
    required String deviceName,
    required String sensorName,
  }) {
    return '${_sanitize(streamPrefix)}_'
        '${_sanitize(deviceName)}_'
        '${_sanitize(sensorName)}';
  }

  String _sanitize(String value) {
    final cleaned = value
        .replaceAll(RegExp(r'[^a-zA-Z0-9._-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    return cleaned.isEmpty ? 'unknown' : cleaned;
  }

  List<num> _numericValues(SensorValue value) {
    if (value is SensorDoubleValue) {
      return value.values;
    }
    if (value is SensorIntValue) {
      return value.values;
    }
    return value.valueStrings
        .map(num.tryParse)
        .whereType<num>()
        .toList(growable: false);
  }

  @override
  Future<void> close() => _transport.close();
}
