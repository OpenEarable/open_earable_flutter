import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:open_earable_flutter/open_earable_flutter.dart' show logger;
import 'package:open_earable_flutter/src/constants.dart';

import '../../managers/ble_gatt_manager.dart';
import 'edge_ml_sensor_scheme_reader.dart';
import 'sensor_scheme_reader.dart';

/// Reads OpenEarable V2 sensor schemes from the parse-info GATT service.
///
/// Newer firmware exposes a per-sensor request protocol: write a sensor id to
/// [requestSensorSchemeCharacteristicUuid], then receive the requested scheme
/// on [sensorSchemeCharacteristicUuid]. Some devices instead update the same
/// characteristic for synchronous reads, so this reader first waits for the
/// notification response and then falls back to a direct read if the
/// notification does not arrive.
class V2SensorSchemeReader extends SensorSchemeReader {
  /// Maximum time to wait for the notification-based scheme response.
  static const Duration _sensorSchemeResponseTimeout = Duration(seconds: 5);

  /// Small delay after enabling notifications and before sending requests.
  ///
  /// Some BLE stacks report subscription setup complete before firmware is
  /// ready to process the following request write.
  static const Duration _sensorSchemeRequestSettleDelay =
      Duration(milliseconds: 80);

  /// Limit for out-of-order notification responses kept in memory.
  static const int _maxBufferedSensorSchemeResponses = 12;

  final String _deviceId;
  final BleGattManager _bleManager;

  /// Sensor schemes that were already read, keyed by sensor id.
  final Map<int, SensorScheme> _sensorSchemes = {};

  /// Sensor ids reported by [sensorListCharacteristicUuid].
  final List<int> _sensorIds = [];

  /// Creates a reader for the connected device represented by [_deviceId].
  V2SensorSchemeReader(this._bleManager, this._deviceId);

  /// Reads and caches the list of sensor ids exposed by the device.
  ///
  /// The first byte of the characteristic is the advertised count; following
  /// bytes are the sensor ids. If the characteristic is shorter than reported,
  /// the available ids are still used so partially compatible firmware can
  /// continue to work.
  Future<void> _readSensorIds() async {
    List<int> sensorIdBuffer = await _bleManager.read(
      deviceId: _deviceId,
      serviceId: parseInfoServiceUuid,
      characteristicId: sensorListCharacteristicUuid,
    );

    if (sensorIdBuffer.isEmpty) {
      throw Exception("No sensor ids found.");
    }

    int sensorIdCount = sensorIdBuffer[0];
    if (sensorIdBuffer.length < 1 + sensorIdCount) {
      logger.w(
        "Sensor id buffer shorter than expected (count=$sensorIdCount, len=${sensorIdBuffer.length}).",
      );
    }

    List<int> sensorIds = sensorIdBuffer.length >= 1 + sensorIdCount
        ? sensorIdBuffer.sublist(1, sensorIdCount + 1)
        : sensorIdBuffer.sublist(1);

    _sensorIds.clear();
    _sensorIds.addAll(sensorIds);

    logger.d("Parsed sensor ids: $sensorIds (count: $sensorIdCount)");
  }

  @override
  Future<SensorScheme> getSchemeForSensor(int sensorId) async {
    if (_sensorIds.isEmpty) {
      await _readSensorIds();
    }
    if (!_sensorIds.contains(sensorId)) {
      throw Exception("Sensor with id $sensorId does not exist.");
    }

    if (_sensorSchemes.containsKey(sensorId)) {
      return _sensorSchemes[sensorId]!;
    }

    final notificationStream = await _bleManager.subscribe(
      deviceId: _deviceId,
      serviceId: parseInfoServiceUuid,
      characteristicId: sensorSchemeCharacteristicUuid,
    );
    final responseReader = _SensorSchemeResponseReader(
      notificationStream: notificationStream,
      parseSensorScheme: _parseSensorScheme,
    );

    try {
      final scheme = await _requestSensorScheme(
        sensorId: sensorId,
        responseReader: responseReader,
      );
      _sensorSchemes[scheme.sensorId] = scheme;
      return scheme;
    } finally {
      await responseReader.dispose();
    }
  }

  @override
  Future<List<SensorScheme>> readSensorSchemes({bool forceRead = false}) async {
    if (_sensorIds.isEmpty || forceRead) {
      await _readSensorIds();
    }

    if (!forceRead && _sensorIds.every(_sensorSchemes.containsKey)) {
      return _sensorSchemes.values.toList();
    }

    final sensorSchemeStream = await _bleManager.subscribe(
      deviceId: _deviceId,
      serviceId: parseInfoServiceUuid,
      characteristicId: sensorSchemeCharacteristicUuid,
    );
    final responseReader = _SensorSchemeResponseReader(
      notificationStream: sensorSchemeStream,
      parseSensorScheme: _parseSensorScheme,
    );

    try {
      for (int sensorId in _sensorIds) {
        if (!_sensorSchemes.containsKey(sensorId) || forceRead) {
          try {
            SensorScheme scheme = await _requestSensorScheme(
              sensorId: sensorId,
              responseReader: responseReader,
            );
            _sensorSchemes[scheme.sensorId] = scheme;
          } catch (e) {
            logger.e(
              "Failed to read sensor scheme for sensor $sensorId: $e${kIsWeb ? ' (on web platform)' : ''}",
            );
            if (kIsWeb) {
              logger.d(
                "Skipping sensor $sensorId due to read failure on web. "
                "This may be a BLE notification timeout or subscription issue.",
              );
            }
            // Continue with next sensor instead of failing entirely
            continue;
          }
        }
      }
    } finally {
      await responseReader.dispose();
    }

    if (_sensorSchemes.isEmpty) {
      await _readLegacySensorSchemesFallback(forceRead: forceRead);
    }

    logger.d(
      "Successfully read ${_sensorSchemes.length} sensor scheme(s): "
      "${_sensorSchemes.keys.join(', ')}",
    );
    return _sensorSchemes.values.toList();
  }

  /// Requests one sensor scheme using notification first, direct read second.
  ///
  /// The notification path is the preferred V2 protocol. If that path times out
  /// or fails, the method sends the same request again and reads
  /// [sensorSchemeCharacteristicUuid] synchronously. This supports firmware
  /// variants that update the characteristic value but do not emit the expected
  /// notification.
  Future<SensorScheme> _requestSensorScheme({
    required int sensorId,
    required _SensorSchemeResponseReader responseReader,
  }) async {
    try {
      return await _requestSensorSchemeViaNotification(
        sensorId: sensorId,
        responseReader: responseReader,
      );
    } catch (error) {
      logger.w(
        "Notification based sensor scheme request for sensor $sensorId failed: "
        "$error. Trying synchronous read.",
      );
    }

    return _requestSensorSchemeViaRead(sensorId);
  }

  /// Sends a scheme request and waits for the matching notification response.
  ///
  /// [responseReader] owns the active notification subscription and matches the
  /// next parsed scheme by sensor id. The pending response is explicitly
  /// cancelled when write or timeout errors occur, so the response reader can be
  /// reused for the next sensor id.
  Future<SensorScheme> _requestSensorSchemeViaNotification({
    required int sensorId,
    required _SensorSchemeResponseReader responseReader,
  }) async {
    final responseFuture = responseReader.nextMatchingScheme(
      sensorId,
      timeout: _sensorSchemeResponseTimeout,
    );

    try {
      await Future.delayed(_sensorSchemeRequestSettleDelay);

      await _writeSensorSchemeRequest(sensorId);

      final scheme = await responseFuture;
      logger.d(
        "Received notification for sensor scheme of sensor $sensorId: $scheme",
      );

      return _normalizeRequestedSensorScheme(
        requestedSensorId: sensorId,
        scheme: scheme,
      );
    } catch (error, stack) {
      responseReader.cancelPendingResponse(
        sensorId: sensorId,
        error: error,
        stackTrace: stack,
      );
      try {
        await responseFuture;
      } catch (_) {
        // The response future is intentionally drained after cancellation.
      }
      rethrow;
    }
  }

  /// Sends a scheme request and reads the scheme characteristic directly.
  ///
  /// This is the compatibility fallback for devices where the request updates
  /// [sensorSchemeCharacteristicUuid] but no notification arrives.
  Future<SensorScheme> _requestSensorSchemeViaRead(int sensorId) async {
    await Future.delayed(_sensorSchemeRequestSettleDelay);

    await _writeSensorSchemeRequest(sensorId);

    final value = await _bleManager.read(
      deviceId: _deviceId,
      serviceId: parseInfoServiceUuid,
      characteristicId: sensorSchemeCharacteristicUuid,
    );
    final scheme = _parseSensorScheme(value);
    logger.d("Read sensor scheme for sensor $sensorId synchronously: $scheme");

    return _normalizeRequestedSensorScheme(
      requestedSensorId: sensorId,
      scheme: scheme,
      allowOmittedSensorId: true,
      throwOnMismatch: true,
    );
  }

  /// Writes the requested sensor id to the V2 scheme request characteristic.
  Future<void> _writeSensorSchemeRequest(int sensorId) {
    return _bleManager.write(
      deviceId: _deviceId,
      serviceId: parseInfoServiceUuid,
      characteristicId: requestSensorSchemeCharacteristicUuid,
      byteData: [sensorId],
    );
  }

  /// Normalizes known firmware quirks in returned sensor schemes.
  ///
  /// Current firmware is expected to always return the requested sensor id.
  /// The `sensorId == 0` handling is kept as a defensive compatibility fallback
  /// for older firmware variants. Mismatched non-zero ids are logged, or
  /// rejected when [throwOnMismatch] is enabled for stale-read-sensitive paths.
  SensorScheme _normalizeRequestedSensorScheme({
    required int requestedSensorId,
    required SensorScheme scheme,
    bool allowOmittedSensorId = true,
    bool throwOnMismatch = false,
  }) {
    if (scheme.sensorId == 0 &&
        requestedSensorId != 0 &&
        allowOmittedSensorId) {
      logger.w(
        "Sensor scheme response for sensor $requestedSensorId omitted the sensor id. Using the requested id.",
      );
      scheme.sensorId = requestedSensorId;
    } else if (scheme.sensorId != requestedSensorId) {
      if (throwOnMismatch) {
        throw StateError(
          "Sensor scheme response for sensor $requestedSensorId reported "
          "sensor id ${scheme.sensorId}. Refusing to cache mismatched scheme.",
        );
      }
      logger.w(
        "Sensor scheme response for sensor $requestedSensorId reported sensor id ${scheme.sensorId}. Using the returned scheme.",
      );
    }

    return scheme;
  }

  /// Attempts the older full-scheme characteristic format as a final fallback.
  ///
  /// This is only used when no V2 per-sensor scheme could be read at all.
  /// Devices with older firmware can still be initialized if they expose the
  /// legacy [schemeCharacteristicUuid] payload.
  Future<void> _readLegacySensorSchemesFallback({
    required bool forceRead,
  }) async {
    logger.w(
      "Per-sensor V2 scheme reads failed for $_deviceId. "
      "Trying legacy full sensor scheme characteristic.",
    );

    try {
      final legacySchemes = await EdgeMlSensorSchemeReader(
        _bleManager,
        _deviceId,
      ).readSensorSchemes(forceRead: forceRead);
      _sensorSchemes
        ..clear()
        ..addEntries(
          legacySchemes.map((scheme) => MapEntry(scheme.sensorId, scheme)),
        );
      logger.i(
        "Loaded ${legacySchemes.length} sensor scheme(s) from legacy fallback.",
      );
    } catch (error) {
      logger.e("Legacy sensor scheme fallback failed: $error");
    }
  }

  /// Parses a single V2 sensor scheme payload.
  ///
  /// The payload contains the sensor id, sensor name, component definitions,
  /// and optional sensor configuration metadata such as supported features and
  /// frequency definitions.
  SensorScheme _parseSensorScheme(List<int> byteStream) {
    int currentIndex = 0;
    int sensorId = byteStream[currentIndex++];

    int nameLength = byteStream[currentIndex++];

    List<int> nameBytes =
        byteStream.sublist(currentIndex, currentIndex + nameLength);
    String sensorName = utf8.decode(nameBytes);
    currentIndex += nameLength;

    int componentCount = byteStream[currentIndex++];

    SensorScheme sensorScheme =
        SensorScheme(sensorId, sensorName, componentCount, null);

    for (int j = 0; j < componentCount; j++) {
      int componentType = byteStream[currentIndex++];

      int groupNameLength = byteStream[currentIndex++];

      List<int> groupNameBytes =
          byteStream.sublist(currentIndex, currentIndex + groupNameLength);
      String groupName = utf8.decode(groupNameBytes);
      currentIndex += groupNameLength;

      int componentNameLength = byteStream[currentIndex++];

      List<int> componentNameBytes = byteStream.sublist(
        currentIndex,
        currentIndex + componentNameLength,
      );
      String componentName = utf8.decode(componentNameBytes);
      currentIndex += componentNameLength;

      int unitNameLength = byteStream[currentIndex++];

      List<int> unitNameBytes =
          byteStream.sublist(currentIndex, currentIndex + unitNameLength);
      String unitName = utf8.decode(unitNameBytes);
      currentIndex += unitNameLength;

      Component component = Component(
        ParseType.fromInt(componentType),
        groupName,
        componentName,
        unitName,
      );
      sensorScheme.components.add(component);
    }

    //Parse config options
    int availableFeatures = byteStream[currentIndex++];
    List<SensorConfigFeatures> features = [];
    for (SensorConfigFeatures f in SensorConfigFeatures.values) {
      if (availableFeatures & f.value == f.value) {
        features.add(f);
      }
    }

    SensorConfigFrequencies? frequencies;
    if (features.contains(SensorConfigFeatures.frequencyDefinition)) {
      int frequencyCount = byteStream[currentIndex++];
      int defaultFreqIndex = byteStream[currentIndex++];
      int maxStreamingFreqIndex = byteStream[currentIndex++];
      List<int> frequenciesBytes = byteStream.sublist(
        currentIndex,
        currentIndex + frequencyCount * 4,
      );
      List<double> freqs = [];
      for (int k = 0; k < frequencyCount; k++) {
        ByteData byteData = ByteData.sublistView(
          Uint8List.fromList(frequenciesBytes.sublist(k * 4, (k + 1) * 4)),
        );
        freqs.add(byteData.getFloat32(0, Endian.little));
      }
      currentIndex += frequencyCount * 4;
      frequencies = SensorConfigFrequencies(
        maxStreamingFreqIndex,
        defaultFreqIndex,
        freqs,
      );
    }
    sensorScheme.options = SensorConfigOptions(features, frequencies);

    return sensorScheme;
  }
}

/// Tracks a single outstanding notification response request.
class _PendingSensorSchemeResponse {
  _PendingSensorSchemeResponse({
    required this.sensorId,
    required this.completer,
  });

  final int sensorId;
  final Completer<SensorScheme> completer;
}

/// Reads and matches sensor scheme notifications from one active subscription.
///
/// The V2 reader keeps one notification subscription open while requesting all
/// schemes. Notifications can arrive slightly out of order, so unmatched
/// schemes are buffered and checked before waiting for a new response.
class _SensorSchemeResponseReader {
  _SensorSchemeResponseReader({
    required Stream<List<int>> notificationStream,
    required SensorScheme Function(List<int>) parseSensorScheme,
  }) : _parseSensorScheme = parseSensorScheme {
    _subscription = notificationStream.listen(
      _handleNotification,
      onError: (error, stack) {
        final pending = _pending;
        if (pending != null && !pending.completer.isCompleted) {
          pending.completer.completeError(error, stack);
        }
      },
    );
  }

  final SensorScheme Function(List<int>) _parseSensorScheme;

  /// Parsed notifications that did not match the request pending at the time.
  final List<SensorScheme> _bufferedSchemes = [];

  /// The currently awaited sensor scheme response, if any.
  _PendingSensorSchemeResponse? _pending;

  /// Subscription to [sensorSchemeCharacteristicUuid] notifications.
  late final StreamSubscription<List<int>> _subscription;

  /// Returns the next buffered or future scheme matching [sensorId].
  Future<SensorScheme> nextMatchingScheme(
    int sensorId, {
    required Duration timeout,
  }) {
    final bufferedIndex = _bufferedSchemes.indexWhere(
      (scheme) => _matchesSensorId(scheme, sensorId),
    );
    if (bufferedIndex != -1) {
      return Future.value(_bufferedSchemes.removeAt(bufferedIndex));
    }

    final completer = Completer<SensorScheme>();
    _pending = _PendingSensorSchemeResponse(
      sensorId: sensorId,
      completer: completer,
    );

    return completer.future.timeout(
      timeout,
      onTimeout: () {
        if (identical(_pending?.completer, completer)) {
          _pending = null;
        }
        throw TimeoutException(
          "Timeout while waiting for sensor scheme response for sensor $sensorId",
          timeout,
        );
      },
    );
  }

  /// Cancels the notification subscription and clears transient state.
  Future<void> dispose() {
    _pending = null;
    _bufferedSchemes.clear();
    return _subscription.cancel();
  }

  /// Completes and clears the pending response after request-side failure.
  ///
  /// This prevents an abandoned pending completer from timing out later after
  /// the caller has already moved to the synchronous read fallback.
  void cancelPendingResponse({
    required int sensorId,
    required Object error,
    required StackTrace stackTrace,
  }) {
    final pending = _pending;
    if (pending == null || pending.sensorId != sensorId) {
      return;
    }
    _pending = null;
    if (!pending.completer.isCompleted) {
      pending.completer.completeError(error, stackTrace);
    }
  }

  /// Parses and routes one raw notification payload.
  ///
  /// Matching schemes complete the current pending request. Non-matching
  /// schemes are buffered because they may belong to a later request.
  void _handleNotification(List<int> value) {
    SensorScheme scheme;
    try {
      scheme = _parseSensorScheme(value);
    } catch (error) {
      logger.w("Ignoring malformed sensor scheme notification: $error");
      return;
    }

    final pending = _pending;
    if (pending != null && _matchesSensorId(scheme, pending.sensorId)) {
      _pending = null;
      if (!pending.completer.isCompleted) {
        pending.completer.complete(scheme);
      }
      return;
    }

    _bufferedSchemes.add(scheme);
    if (_bufferedSchemes.length >
        V2SensorSchemeReader._maxBufferedSensorSchemeResponses) {
      _bufferedSchemes.removeAt(0);
    }
  }

  /// Returns whether [scheme] can satisfy a request for [requestedSensorId].
  bool _matchesSensorId(SensorScheme scheme, int requestedSensorId) {
    return scheme.sensorId == requestedSensorId;
  }
}
