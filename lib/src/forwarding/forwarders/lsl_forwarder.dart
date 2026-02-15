import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:typed_data';

import '../sensor_forwarder.dart';
import '../../models/capabilities/sensor.dart';
import 'lsl/device_name/device_name_stub.dart'
    if (dart.library.io) 'lsl/device_name/device_name_io.dart';
import 'lsl/transport/lsl_transport.dart';
import 'lsl/transport/lsl_transport_stub.dart'
    if (dart.library.io) 'lsl/transport/lsl_transport_io.dart';

const int defaultLslBridgePort = 16571;
const String defaultLslStreamPrefix = 'Phone';
const String _sourceIdPrefix = 'oe-v1';
const String _sourceIdSeparator = ':';
const String _emptySourceIdComponent = '-';

final String _autoStreamPrefix = _resolveAutoStreamPrefix();

String _resolveAutoStreamPrefix() {
  final name = createLslDeviceNameProvider().deviceName.trim();
  if (name.isNotEmpty) {
    return name;
  }
  return defaultLslStreamPrefix;
}

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
  LslForwardingConfig _config =
      LslForwardingConfig(streamPrefix: _autoStreamPrefix);
  final Map<String, String> _deviceTokenById = {};
  int _nextDeviceToken = 1;

  DateTime? _lastForwardingError;
  bool _didLogUnsupportedPlatform = false;

  LslForwardingConfig get config => _config;
  String get defaultStreamPrefix => _autoStreamPrefix;
  bool get isSupported => _transport.isSupported;
  @override
  bool get isEnabled => _config.enabled;
  bool get isConfigured => _config.isConfigured;

  void configure({
    required String host,
    int port = defaultLslBridgePort,
    bool enabled = true,
    String? streamPrefix,
  }) {
    final trimmedHost = host.trim();
    if (trimmedHost.isEmpty) {
      throw ArgumentError.value(host, 'host', 'must not be empty');
    }
    if (port <= 0 || port > 65535) {
      throw ArgumentError.value(port, 'port', 'must be between 1 and 65535');
    }

    final trimmedPrefix = (streamPrefix ?? _autoStreamPrefix).trim();
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
    _config = LslForwardingConfig(streamPrefix: _autoStreamPrefix);
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
    final side = _normalizeSide(sample.deviceSide);
    final source = _buildSource(deviceId: sample.deviceId);
    final deviceToken = _resolveDeviceToken(sample.deviceId);

    final streamName = _buildStreamName(
      deviceName: sample.deviceName,
      deviceSide: side,
      sensorName: sensor.sensorName,
      source: source,
    );
    final sourceId = _buildSourceId(
      deviceName: sample.deviceName,
      deviceSide: side,
      sensorName: sensor.sensorName,
      source: source,
    );

    final map = <String, dynamic>{
      'type': 'open_earable_lsl_sample',
      'stream_name': streamName,
      'source_id': sourceId,
      'device_token': deviceToken,
      'device_id': sample.deviceId,
      'device_name': sample.deviceName,
      'device_source': source,
      'device_channel': side ?? '',
      'sensor_name': sensor.sensorName,
      'chart_title': sensor.chartTitle,
      'short_chart_title': sensor.shortChartTitle,
      'stream_prefix': streamPrefix,
      'axis_names': sensor.axisNames,
      'axis_units': sensor.axisUnits,
      'timestamp': value.timestamp,
      'timestamp_exponent': sensor.timestampExponent,
      'dimensions': value.dimensions,
      'values': _numericValues(value),
      'value_strings': value.valueStrings,
      'sent_at_unix_ms': DateTime.now().millisecondsSinceEpoch,
    };
    if (side != null) {
      map['device_side'] = side;
    }

    return Uint8List.fromList(utf8.encode(jsonEncode(map)));
  }

  String _buildSource({required String deviceId}) {
    final normalizedDeviceId = _normalizeDisplay(
      deviceId,
      fallback: 'unknown_device_source',
    );
    return normalizedDeviceId;
  }

  String _buildSourceId({
    required String deviceName,
    String? deviceSide,
    required String sensorName,
    required String source,
  }) {
    final side = _normalizeSide(deviceSide) ?? '';
    return [
      _sourceIdPrefix,
      _encodeSourceIdComponent(
        _normalizeDisplay(deviceName, fallback: 'unknown_device'),
      ),
      _encodeSourceIdComponent(side),
      _encodeSourceIdComponent(
        _normalizeDisplay(sensorName, fallback: 'unknown_sensor'),
      ),
      _encodeSourceIdComponent(source),
    ].join(_sourceIdSeparator);
  }

  String _encodeSourceIdComponent(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return _emptySourceIdComponent;
    }
    return Uri.encodeComponent(trimmed);
  }

  String _buildStreamName({
    required String deviceName,
    String? deviceSide,
    required String sensorName,
    required String source,
  }) {
    final normalizedDevice = _normalizeDisplay(
      deviceName,
      fallback: 'unknown_device',
    );
    final normalizedSensor = _normalizeDisplay(
      sensorName,
      fallback: 'unknown_sensor',
    );
    final normalizedSource = _normalizeDisplay(
      source,
      fallback: 'unknown_source',
    );
    final side = _normalizeSide(deviceSide);
    final sideSuffix = side == null ? '' : ' [$side]';
    return '$normalizedDevice$sideSuffix ($normalizedSource) - $normalizedSensor';
  }

  String _resolveDeviceToken(String deviceId) {
    final existing = _deviceTokenById[deviceId];
    if (existing != null) {
      return existing;
    }

    final nextToken = 'device_${_nextDeviceToken.toString().padLeft(2, '0')}';
    _nextDeviceToken += 1;
    _deviceTokenById[deviceId] = nextToken;
    return nextToken;
  }

  String? _normalizeSide(String? side) {
    if (side == null) {
      return null;
    }
    final trimmed = side.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    final lower = trimmed.toLowerCase();
    if (lower.startsWith('l')) {
      return 'L';
    }
    if (lower.startsWith('r')) {
      return 'R';
    }
    return trimmed;
  }

  String _normalizeDisplay(String value, {required String fallback}) {
    final compact = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (compact.isEmpty) {
      return fallback;
    }
    return compact;
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
