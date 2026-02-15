import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:typed_data';

import '../sensor_forwarder.dart';
import '../../models/capabilities/sensor.dart';
import 'udp/device_name/device_name_stub.dart'
    if (dart.library.io) 'udp/device_name/device_name_io.dart';
import 'udp/transport/udp_transport.dart';
import 'udp/transport/udp_transport_stub.dart'
    if (dart.library.io) 'udp/transport/udp_transport_io.dart';

const int defaultUdpBridgePort = 16571;
const String defaultUdpBridgeStreamPrefix = 'Phone';
const String _sourceIdPrefix = 'oe-v1';
const String _sourceIdSeparator = ':';
const String _emptySourceIdComponent = '-';

final String _autoStreamPrefix = _resolveAutoStreamPrefix();

String _resolveAutoStreamPrefix() {
  final name = createUdpDeviceNameProvider().deviceName.trim();
  if (name.isNotEmpty) {
    return name;
  }
  return defaultUdpBridgeStreamPrefix;
}

/// Configuration for UDP bridge forwarding.
///
/// The Flutter package forwards sensor samples as UDP JSON packets to a
/// middleware process which then publishes the data to LSL outlets.
class UdpBridgeForwardingConfig {
  final bool enabled;
  final String host;
  final int port;
  final String streamPrefix;

  const UdpBridgeForwardingConfig({
    this.enabled = false,
    this.host = '',
    this.port = defaultUdpBridgePort,
    this.streamPrefix = defaultUdpBridgeStreamPrefix,
  });

  bool get isConfigured => host.trim().isNotEmpty;

  UdpBridgeForwardingConfig copyWith({
    bool? enabled,
    String? host,
    int? port,
    String? streamPrefix,
  }) {
    return UdpBridgeForwardingConfig(
      enabled: enabled ?? this.enabled,
      host: host ?? this.host,
      port: port ?? this.port,
      streamPrefix: streamPrefix ?? this.streamPrefix,
    );
  }
}

/// Forwarder implementation that sends samples to a UDP bridge endpoint.
class UdpBridgeForwarder
    implements
        SensorForwarder,
        SensorForwarderConnectionStateProvider,
        SensorForwarderConnectionErrorProvider {
  UdpBridgeForwarder._internal() : _transport = createUdpTransport();

  static final UdpBridgeForwarder instance = UdpBridgeForwarder._internal();

  final UdpTransport _transport;
  UdpBridgeForwardingConfig _config =
      UdpBridgeForwardingConfig(streamPrefix: _autoStreamPrefix);
  final Map<String, String> _deviceTokenById = {};
  int _nextDeviceToken = 1;

  DateTime? _lastForwardingError;
  bool _didLogUnsupportedPlatform = false;
  final StreamController<SensorForwarderConnectionState>
      _connectionStateController =
      StreamController<SensorForwarderConnectionState>.broadcast();
  final StreamController<String?> _connectionErrorMessageController =
      StreamController<String?>.broadcast();
  SensorForwarderConnectionState _connectionState =
      SensorForwarderConnectionState.active;
  String? _connectionErrorMessage;
  int _probeGeneration = 0;
  bool _probeInFlight = false;
  Timer? _healthProbeTimer;

  static const Duration _healthProbeInterval = Duration(seconds: 1);

  UdpBridgeForwardingConfig get config => _config;
  String get defaultStreamPrefix => _autoStreamPrefix;
  bool get isSupported => _transport.isSupported;
  @override
  bool get isEnabled => _config.enabled;
  bool get isConfigured => _config.isConfigured;
  @override
  SensorForwarderConnectionState get connectionState => _connectionState;
  @override
  Stream<SensorForwarderConnectionState> get connectionStateStream =>
      _connectionStateController.stream;
  @override
  String? get connectionErrorMessage => _connectionErrorMessage;
  @override
  Stream<String?> get connectionErrorMessageStream =>
      _connectionErrorMessageController.stream;

  void configure({
    required String host,
    int port = defaultUdpBridgePort,
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
    _syncHealthProbeLoop();
    _scheduleConnectionProbe();
  }

  @override
  void setEnabled(bool enabled) {
    _config = _config.copyWith(enabled: enabled);
    if (!enabled) {
      _probeGeneration += 1;
      _setConnectionState(SensorForwarderConnectionState.active);
      _setConnectionErrorMessage(null);
      _syncHealthProbeLoop();
      return;
    }
    _syncHealthProbeLoop();
    _scheduleConnectionProbe();
  }

  void reset() {
    _probeGeneration += 1;
    _config = UdpBridgeForwardingConfig(streamPrefix: _autoStreamPrefix);
    _setConnectionState(SensorForwarderConnectionState.active);
    _setConnectionErrorMessage(null);
    _syncHealthProbeLoop();
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
          'UDP bridge forwarding is not available on this platform. Sensor data stays local.',
          name: 'open_earable_flutter',
        );
      }
      return;
    }

    final payload = _buildPayload(sample, localConfig.streamPrefix);

    try {
      await _transport.send(payload, localConfig.host, localConfig.port);
      if (!_matchesCurrentConfig(localConfig)) {
        return;
      }
      _setConnectionState(SensorForwarderConnectionState.active);
      _setConnectionErrorMessage(null);
    } catch (error, stackTrace) {
      if (!_matchesCurrentConfig(localConfig)) {
        return;
      }
      _setConnectionState(SensorForwarderConnectionState.unreachable);
      _setConnectionErrorMessage(error.toString());
      _logForwardingError(
        'Failed to forward sensor data to UDP bridge (${localConfig.host}:${localConfig.port}): $error',
        stackTrace,
      );
    }
  }

  void _setConnectionState(SensorForwarderConnectionState nextState) {
    if (_connectionState == nextState) {
      _syncHealthProbeLoop();
      return;
    }
    _connectionState = nextState;
    if (!_connectionStateController.isClosed) {
      _connectionStateController.add(nextState);
    }
    _syncHealthProbeLoop();
  }

  void _setConnectionErrorMessage(String? nextMessage) {
    if (_connectionErrorMessage == nextMessage) {
      return;
    }
    _connectionErrorMessage = nextMessage;
    if (!_connectionErrorMessageController.isClosed) {
      _connectionErrorMessageController.add(nextMessage);
    }
  }

  void _scheduleConnectionProbe() {
    final localConfig = _config;

    if (!localConfig.enabled || !localConfig.isConfigured) {
      _probeGeneration += 1;
      _setConnectionState(SensorForwarderConnectionState.active);
      _setConnectionErrorMessage(null);
      return;
    }

    if (!_transport.isSupported) {
      _setConnectionState(SensorForwarderConnectionState.active);
      _setConnectionErrorMessage(null);
      return;
    }

    if (_probeInFlight) {
      return;
    }

    final probeGeneration = ++_probeGeneration;
    _probeInFlight = true;
    unawaited(_probeConnection(localConfig, probeGeneration));
  }

  Future<void> _probeConnection(
    UdpBridgeForwardingConfig config,
    int probeGeneration,
  ) async {
    try {
      await _transport.probe(config.host, config.port);
      if (!_isCurrentProbe(config, probeGeneration)) {
        return;
      }
      _setConnectionState(SensorForwarderConnectionState.active);
      _setConnectionErrorMessage(null);
    } catch (error, stackTrace) {
      if (!_isCurrentProbe(config, probeGeneration)) {
        return;
      }
      _setConnectionState(SensorForwarderConnectionState.unreachable);
      _setConnectionErrorMessage(error.toString());
      _logForwardingError(
        'Failed to reach UDP bridge during probe (${config.host}:${config.port}): $error',
        stackTrace,
      );
    } finally {
      _probeInFlight = false;
      _syncHealthProbeLoop();
    }
  }

  bool _shouldRunHealthProbeLoop() {
    return _config.enabled && _config.isConfigured && _transport.isSupported;
  }

  void _syncHealthProbeLoop() {
    if (!_shouldRunHealthProbeLoop()) {
      _healthProbeTimer?.cancel();
      _healthProbeTimer = null;
      return;
    }

    _healthProbeTimer ??= Timer.periodic(_healthProbeInterval, (_) {
      if (!_shouldRunHealthProbeLoop()) {
        _healthProbeTimer?.cancel();
        _healthProbeTimer = null;
        return;
      }
      _scheduleConnectionProbe();
    });
  }

  bool _isCurrentProbe(UdpBridgeForwardingConfig config, int probeGeneration) {
    return probeGeneration == _probeGeneration &&
        config.host == _config.host &&
        config.port == _config.port &&
        config.enabled == _config.enabled;
  }

  bool _matchesCurrentConfig(UdpBridgeForwardingConfig config) {
    return config.host == _config.host &&
        config.port == _config.port &&
        config.enabled == _config.enabled;
  }

  void _logForwardingError(String message, StackTrace stackTrace) {
    final now = DateTime.now();
    final shouldLog = _lastForwardingError == null ||
        now.difference(_lastForwardingError!) >= const Duration(seconds: 5);
    if (!shouldLog) {
      return;
    }
    _lastForwardingError = now;
    developer.log(
      message,
      name: 'open_earable_flutter',
      stackTrace: stackTrace,
    );
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
      'type': 'open_earable_udp_sample',
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
  Future<void> close() {
    _probeGeneration += 1;
    _probeInFlight = false;
    _healthProbeTimer?.cancel();
    _healthProbeTimer = null;
    _setConnectionErrorMessage(null);
    return _transport.close();
  }
}
