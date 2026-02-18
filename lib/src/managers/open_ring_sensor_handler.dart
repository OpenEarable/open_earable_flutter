import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:open_earable_flutter/src/models/devices/open_ring.dart';

import '../../open_earable_flutter.dart';
import '../utils/sensor_value_parser/sensor_value_parser.dart';
import 'sensor_handler.dart';

class OpenRingSensorHandler extends SensorHandler<OpenRingSensorConfig> {
  final DiscoveredDevice _discoveredDevice;
  final BleGattManager _bleManager;
  final SensorValueParser _sensorValueParser;

  static const int _defaultSampleDelayMs = 20;
  static const int _minSampleDelayMs = 12;
  static const int _maxSampleDelayMs = 22;
  static const int _maxScheduleLagMs = 80;
  static const double _delayAlpha = 0.12;
  static const double _backlogCompressionPerPacket = 0.06;
  static const int _commandSettleDelayMs = 45;
  static const List<int> _ppgRealtimeStartPayload = <int>[
    0x00,
    0x00,
    0x19,
    0x01,
    0x01,
  ];
  static const List<int> _ppgRealtimeStopPayload = <int>[0x06];
  static const Set<int> _pacedStreamingCommands = {
    OpenRingGatt.cmdPPGQ2,
  };

  Stream<Map<String, dynamic>>? _sensorDataStream;
  Future<void> _commandQueue = Future<void>.value();
  final _OpenRingDesiredState _desiredState = _OpenRingDesiredState();
  int _applyVersion = 0;
  int _transportTimingResetCounter = 0;
  bool _isApplying = false;
  bool _hasRealtimeConfigurationWrite = false;
  bool _hasAdoptedInitialStreamingState = false;
  void Function()? _onInitialStreamingDetected;
  _OpenRingTransportCommand _lastAppliedTransport =
      _OpenRingTransportCommand.none;

  OpenRingSensorHandler({
    required DiscoveredDevice discoveredDevice,
    required BleGattManager bleManager,
    required SensorValueParser sensorValueParser,
  })  : _discoveredDevice = discoveredDevice,
        _bleManager = bleManager,
        _sensorValueParser = sensorValueParser;

  @override
  Stream<Map<String, dynamic>> subscribeToSensorData(int sensorId) {
    if (!_bleManager.isConnected(_discoveredDevice.id)) {
      throw Exception("Can't subscribe to sensor data. Earable not connected");
    }

    _sensorDataStream ??= _createSensorDataStream();

    return _sensorDataStream!.where((data) {
      final dynamic cmd = data['cmd'];
      return cmd is int && cmd == sensorId;
    });
  }

  @override
  Future<void> writeSensorConfig(OpenRingSensorConfig sensorConfig) async {
    if (!_bleManager.isConnected(_discoveredDevice.id)) {
      throw Exception("Can't write sensor config. Earable not connected");
    }

    if (!_isRealtimeStreamingCommand(sensorConfig.cmd)) {
      await _writeCommand(sensorConfig);
      return;
    }

    _hasRealtimeConfigurationWrite = true;
    _updateDesiredStateFromSensorConfig(sensorConfig);
    await _enqueueApplyDesiredTransport(
      reason: 'config-write-cmd-${sensorConfig.cmd}',
    );
  }

  Future<List<Map<String, dynamic>>> _parseData(List<int> data) async {
    final byteData = ByteData.sublistView(Uint8List.fromList(data));
    return _sensorValueParser.parse(byteData, []);
  }

  void setTemperatureStreamEnabled(bool enabled) {
    _hasRealtimeConfigurationWrite = true;
    _desiredState.temperatureEnabled = enabled;
    logger.d('OpenRing software toggle: temperatureStream=$enabled');

    unawaited(
      _enqueueApplyDesiredTransport(
        reason: 'temperature-set-$enabled',
      ),
    );
  }

  void setInitialStreamingDetectedCallback(void Function()? callback) {
    _onInitialStreamingDetected = callback;
  }

  bool get hasActiveRealtimeStreaming =>
      _desiredState.hasAnyEnabled ||
      _isApplying ||
      _lastAppliedTransport != _OpenRingTransportCommand.none;

  bool _isRealtimeStreamingCommand(int cmd) =>
      cmd == OpenRingGatt.cmdIMU || cmd == OpenRingGatt.cmdPPGQ2;

  void _updateDesiredStateFromSensorConfig(OpenRingSensorConfig sensorConfig) {
    final bool isStart = _isRealtimeStreamingStart(sensorConfig);
    final bool isStop = _isRealtimeStreamingStop(sensorConfig);
    if (!isStart && !isStop) {
      logger.d(
        'Ignoring OpenRing realtime config with unknown payload '
        '(cmd=${sensorConfig.cmd}, payload=${sensorConfig.payload})',
      );
      return;
    }

    if (sensorConfig.cmd == OpenRingGatt.cmdIMU) {
      if (isStart) {
        _desiredState.imuEnabled = true;
      } else {
        _desiredState.imuEnabled = false;
      }
      return;
    }

    if (sensorConfig.cmd == OpenRingGatt.cmdPPGQ2) {
      _desiredState.ppgEnabled = isStart;
    }
  }

  Future<void> _enqueueApplyDesiredTransport({
    required String reason,
  }) {
    _applyVersion += 1;
    final int requestVersion = _applyVersion;

    _commandQueue =
        _commandQueue.catchError((Object error, StackTrace stackTrace) {
      logger.e('OpenRing previous command failed: $error');
      logger.t(stackTrace);
    }).then((_) async {
      if (requestVersion != _applyVersion) {
        return;
      }
      await _applyDesiredTransport(
        requestVersion: requestVersion,
        reason: reason,
      );
    });

    return _commandQueue;
  }

  Future<void> _applyDesiredTransport({
    required int requestVersion,
    required String reason,
  }) async {
    if (!_bleManager.isConnected(_discoveredDevice.id)) {
      return;
    }

    final _OpenRingTransportCommand desiredTransport =
        _desiredState.resolveDesiredTransport();
    if (desiredTransport == _lastAppliedTransport) {
      return;
    }

    _isApplying = true;
    try {
      logger.d(
        'OpenRing apply transport ($reason): '
        '${_desiredState.debugSummary(desiredTransport)}',
      );

      if (_lastAppliedTransport == _OpenRingTransportCommand.ppg &&
          desiredTransport == _OpenRingTransportCommand.none) {
        await _writeCommand(
          OpenRingSensorConfig(
            cmd: OpenRingGatt.cmdPPGQ2,
            payload: List<int>.from(_ppgRealtimeStopPayload),
          ),
        );
        _transportTimingResetCounter += 1;
        _lastAppliedTransport = _OpenRingTransportCommand.none;
        await Future.delayed(
          const Duration(milliseconds: _commandSettleDelayMs),
        );
        return;
      }

      if (desiredTransport == _OpenRingTransportCommand.none) {
        _lastAppliedTransport = _OpenRingTransportCommand.none;
        return;
      }

      await _writeCommand(
        OpenRingSensorConfig(
          cmd: OpenRingGatt.cmdPPGQ2,
          payload: List<int>.from(_ppgRealtimeStopPayload),
        ),
      );
      await Future.delayed(
        const Duration(milliseconds: _commandSettleDelayMs),
      );
      if (!_shouldContinueApply(requestVersion)) {
        return;
      }

      await _writeCommand(
        OpenRingSensorConfig(
          cmd: OpenRingGatt.cmdPPGQ2,
          payload: List<int>.from(_ppgRealtimeStartPayload),
        ),
      );
      _transportTimingResetCounter += 1;
      _lastAppliedTransport = _OpenRingTransportCommand.ppg;
      await Future.delayed(
        const Duration(milliseconds: _commandSettleDelayMs),
      );
    } finally {
      _isApplying = false;
    }
  }

  bool _shouldContinueApply(int requestVersion) {
    return requestVersion == _applyVersion &&
        _bleManager.isConnected(_discoveredDevice.id);
  }

  void _emitSample(
    StreamController<Map<String, dynamic>> streamController,
    Map<String, dynamic> sample,
  ) {
    if (streamController.isClosed) {
      return;
    }
    if (_isApplying) {
      return;
    }

    final filtered = Map<String, dynamic>.from(sample);

    final dynamic cmd = filtered['cmd'];
    final bool isPpgSample = cmd is int && cmd == OpenRingGatt.cmdPPGQ2;
    final bool shouldConsumeTransport = _desiredState.hasAnyEnabled;

    if (isPpgSample) {
      if (!shouldConsumeTransport) {
        return;
      }
      if (!_desiredState.temperatureEnabled) {
        filtered.remove('Temperature');
      }
      if (!_desiredState.ppgEnabled) {
        filtered.remove('PPG');
      }

      final bool hasImuPayload = _hasImuPayload(filtered);
      if (_desiredState.imuEnabled && hasImuPayload) {
        final imuAlias = _createImuAliasFromPpg(filtered);
        _removeImuPayload(filtered);
        _emitIfSampleHasSensorPayload(streamController, filtered);
        streamController.add(imuAlias);
        return;
      }

      if (!_desiredState.imuEnabled && hasImuPayload) {
        _removeImuPayload(filtered);
      }

      _emitIfSampleHasSensorPayload(streamController, filtered);
      return;
    }

    // 0x40 transport is intentionally ignored. IMU is emitted via 0x32 aliasing.
    if (cmd is int && cmd == OpenRingGatt.cmdIMU) {
      return;
    }

    _emitIfSampleHasSensorPayload(streamController, filtered);
  }

  void _emitIfSampleHasSensorPayload(
    StreamController<Map<String, dynamic>> streamController,
    Map<String, dynamic> sample,
  ) {
    if (!_hasAnySensorPayload(sample)) {
      return;
    }
    streamController.add(sample);
  }

  bool _hasImuPayload(Map<String, dynamic> sample) {
    return sample.containsKey('Accelerometer') ||
        sample.containsKey('Gyroscope');
  }

  bool _hasAnySensorPayload(Map<String, dynamic> sample) {
    return _hasImuPayload(sample) ||
        sample.containsKey('PPG') ||
        sample.containsKey('Temperature');
  }

  void _removeImuPayload(Map<String, dynamic> sample) {
    sample.remove('Accelerometer');
    sample.remove('Gyroscope');
  }

  Map<String, dynamic> _createImuAliasFromPpg(Map<String, dynamic> sample) {
    final imuAlias = Map<String, dynamic>.from(sample);
    imuAlias['cmd'] = OpenRingGatt.cmdIMU;
    imuAlias.remove('PPG');
    imuAlias.remove('Temperature');
    return imuAlias;
  }

  List<Map<String, dynamic>> _filterSamplesForScheduling(
    List<Map<String, dynamic>> parsedSamples,
  ) {
    return parsedSamples.where(_shouldScheduleSample).toList(growable: false);
  }

  bool _shouldScheduleSample(Map<String, dynamic> sample) {
    if (_isApplying) {
      return false;
    }

    final dynamic cmd = sample['cmd'];
    if (cmd is! int) {
      return _hasAnySensorPayload(sample);
    }

    _adoptInitialStreamingStateIfNeeded(sample, cmd);

    final bool shouldConsumeTransport = _desiredState.hasAnyEnabled;
    final bool hasImuPayload = _hasImuPayload(sample);
    final bool hasPpgPayload = sample.containsKey('PPG');
    final bool hasTemperaturePayload = sample.containsKey('Temperature');

    if (cmd == OpenRingGatt.cmdPPGQ2) {
      if (!shouldConsumeTransport) {
        return false;
      }
      final bool shouldEmitImu = _desiredState.imuEnabled && hasImuPayload;
      final bool shouldEmitPpg = _desiredState.ppgEnabled && hasPpgPayload;
      final bool shouldEmitTemperature =
          _desiredState.temperatureEnabled && hasTemperaturePayload;
      return shouldEmitImu || shouldEmitPpg || shouldEmitTemperature;
    }

    if (cmd == OpenRingGatt.cmdIMU) {
      return false;
    }

    return _hasAnySensorPayload(sample);
  }

  void _adoptInitialStreamingStateIfNeeded(
    Map<String, dynamic> sample,
    int cmd,
  ) {
    if (_hasAdoptedInitialStreamingState ||
        _hasRealtimeConfigurationWrite ||
        _desiredState.hasAnyEnabled) {
      return;
    }
    if (cmd != OpenRingGatt.cmdPPGQ2) {
      return;
    }
    if (!_hasAnySensorPayload(sample)) {
      return;
    }

    _hasAdoptedInitialStreamingState = true;
    _desiredState.imuEnabled = true;
    _desiredState.ppgEnabled = true;
    _desiredState.temperatureEnabled = true;
    _lastAppliedTransport = _OpenRingTransportCommand.ppg;
    _transportTimingResetCounter += 1;

    logger.i(
      'OpenRing detected active realtime stream on initial start; '
      'assuming IMU/PPG/Temperature enabled',
    );
    _onInitialStreamingDetected?.call();
  }

  Stream<Map<String, dynamic>> _createSensorDataStream() {
    late final StreamController<Map<String, dynamic>> streamController;
    // ignore: cancel_subscriptions
    StreamSubscription<List<int>>? bleSubscription;

    final scheduler = _OpenRingPacedScheduler(
      pacedCommands: _pacedStreamingCommands,
      defaultSampleDelayMs: _defaultSampleDelayMs,
      minSampleDelayMs: _minSampleDelayMs,
      maxSampleDelayMs: _maxSampleDelayMs,
      maxScheduleLagMs: _maxScheduleLagMs,
      delayAlpha: _delayAlpha,
      backlogCompressionPerPacket: _backlogCompressionPerPacket,
    );

    // Keep command families independent.
    final Map<int, Future<void>> processingQueueByCmd = {};

    Future<void> processPacket(
      List<int> data,
      int arrivalMs,
      int? rawCmd,
    ) async {
      int? cmdKey = rawCmd;
      try {
        final parsedData = await _parseData(data);
        if (parsedData.isEmpty) {
          return;
        }

        final dynamic parsedCmd = parsedData.first['cmd'];
        if (parsedCmd is int) {
          cmdKey = parsedCmd;
        }

        final filteredForScheduling = _filterSamplesForScheduling(parsedData);
        if (filteredForScheduling.isEmpty) {
          return;
        }

        if (cmdKey == null) {
          for (final sample in filteredForScheduling) {
            _emitSample(streamController, sample);
          }
          return;
        }

        if (!scheduler.isPacedCommand(cmdKey)) {
          for (final sample in filteredForScheduling) {
            _emitSample(streamController, sample);
          }
          return;
        }

        await scheduler.emitPacedSamples(
          cmd: cmdKey,
          samples: filteredForScheduling,
          arrivalMs: arrivalMs,
          onEmitSample: (sample) => _emitSample(streamController, sample),
        );
      } finally {
        scheduler.finishPacket(rawCmd: rawCmd, parsedCmd: cmdKey);
      }
    }

    streamController = StreamController<Map<String, dynamic>>.broadcast(
      onListen: () {
        bleSubscription ??= _bleManager
            .subscribe(
          deviceId: _discoveredDevice.id,
          serviceId: OpenRingGatt.service,
          characteristicId: OpenRingGatt.rxChar,
        )
            .listen(
          (data) {
            scheduler.resetIfRequested(
              _transportTimingResetCounter,
              const <int>[OpenRingGatt.cmdPPGQ2],
            );

            final int? rawCmd = data.length > 2 ? data[2] : null;
            if (rawCmd != null) {
              scheduler.notePacketQueued(rawCmd);
            }

            final int arrivalMs = scheduler.nowMonotonicMs;
            final int queueKey = rawCmd ?? -1;
            final Future<void> previousQueue =
                processingQueueByCmd[queueKey] ?? Future<void>.value();

            processingQueueByCmd[queueKey] = previousQueue
                .then((_) => processPacket(data, arrivalMs, rawCmd))
                .catchError((error) {
              logger.e(
                'Error while parsing OpenRing sensor packet: $error',
              );
            });
          },
          onError: (error) {
            logger.e('Error while subscribing to sensor data: $error');
            if (!streamController.isClosed) {
              streamController.addError(error);
            }
          },
        );
      },
      onCancel: () {
        if (!streamController.hasListener) {
          final subscription = bleSubscription;
          bleSubscription = null;
          processingQueueByCmd.clear();
          scheduler.clear();

          if (subscription != null) {
            unawaited(subscription.cancel());
          }
        }
      },
    );

    return streamController.stream;
  }

  Future<void> _writeCommand(OpenRingSensorConfig sensorConfig) async {
    final sensorConfigBytes = sensorConfig.toBytes();
    await _bleManager.write(
      deviceId: _discoveredDevice.id,
      serviceId: OpenRingGatt.service,
      characteristicId: OpenRingGatt.txChar,
      byteData: sensorConfigBytes,
    );
  }

  bool _isRealtimeStreamingStart(OpenRingSensorConfig sensorConfig) {
    if (sensorConfig.payload.isEmpty) {
      return false;
    }

    if (sensorConfig.cmd == OpenRingGatt.cmdPPGQ2) {
      return sensorConfig.payload[0] == 0x00;
    }

    if (sensorConfig.cmd == OpenRingGatt.cmdIMU) {
      return sensorConfig.payload[0] != 0x00;
    }

    return false;
  }

  bool _isRealtimeStreamingStop(OpenRingSensorConfig sensorConfig) {
    if (sensorConfig.payload.isEmpty) {
      return false;
    }

    if (sensorConfig.cmd == OpenRingGatt.cmdPPGQ2) {
      return sensorConfig.payload[0] == 0x06;
    }

    if (sensorConfig.cmd == OpenRingGatt.cmdIMU) {
      return sensorConfig.payload[0] == 0x00;
    }

    return false;
  }
}

class _OpenRingDesiredState {
  bool imuEnabled = false;
  bool ppgEnabled = false;
  bool temperatureEnabled = false;

  bool get hasAnyEnabled => imuEnabled || ppgEnabled || temperatureEnabled;

  _OpenRingTransportCommand resolveDesiredTransport() {
    if (hasAnyEnabled) {
      return _OpenRingTransportCommand.ppg;
    }
    return _OpenRingTransportCommand.none;
  }

  String debugSummary(_OpenRingTransportCommand transport) {
    return 'imu=$imuEnabled ppg=$ppgEnabled temp=$temperatureEnabled '
        'transport=$transport';
  }
}

enum _OpenRingTransportCommand {
  none,
  ppg,
}

class _OpenRingPacedScheduler {
  _OpenRingPacedScheduler({
    required this.pacedCommands,
    required this.defaultSampleDelayMs,
    required this.minSampleDelayMs,
    required this.maxSampleDelayMs,
    required this.maxScheduleLagMs,
    required this.delayAlpha,
    required this.backlogCompressionPerPacket,
  })  : _clock = Stopwatch()..start(),
        _wallClockAnchorMs = DateTime.now().millisecondsSinceEpoch;

  final Set<int> pacedCommands;
  final int defaultSampleDelayMs;
  final int minSampleDelayMs;
  final int maxSampleDelayMs;
  final int maxScheduleLagMs;
  final double delayAlpha;
  final double backlogCompressionPerPacket;

  final Stopwatch _clock;
  final int _wallClockAnchorMs;

  final Map<int, int> _lastArrivalByCmd = {};
  final Map<int, double> _delayEstimateByCmd = {};
  final Map<int, int> _nextDueByCmd = {};
  final Map<int, int> _emittedTimestampByCmd = {};
  final Map<int, int> _pendingPacketsByCmd = {};
  int _seenTimingResetCounter = 0;

  int get nowMonotonicMs => _clock.elapsedMilliseconds;

  bool isPacedCommand(int cmd) => pacedCommands.contains(cmd);

  void notePacketQueued(int rawCmd) {
    _pendingPacketsByCmd[rawCmd] = (_pendingPacketsByCmd[rawCmd] ?? 0) + 1;
  }

  void clear() {
    _lastArrivalByCmd.clear();
    _delayEstimateByCmd.clear();
    _nextDueByCmd.clear();
    _emittedTimestampByCmd.clear();
    _pendingPacketsByCmd.clear();
  }

  void resetIfRequested(int timingResetCounter, Iterable<int> commandKeys) {
    if (_seenTimingResetCounter == timingResetCounter) {
      return;
    }
    _seenTimingResetCounter = timingResetCounter;
    for (final key in commandKeys) {
      _lastArrivalByCmd.remove(key);
      _delayEstimateByCmd.remove(key);
      _nextDueByCmd.remove(key);
      _emittedTimestampByCmd.remove(key);
    }
  }

  Future<void> emitPacedSamples({
    required int cmd,
    required List<Map<String, dynamic>> samples,
    required int arrivalMs,
    required void Function(Map<String, dynamic> sample) onEmitSample,
  }) async {
    final int stepMs = _resolveStepMs(
      cmd: cmd,
      sampleCount: samples.length,
      arrivalMs: arrivalMs,
    );

    int nextDueMs = _nextDueByCmd[cmd] ?? arrivalMs;
    final int nowMs = _clock.elapsedMilliseconds;
    if (nextDueMs < nowMs - maxScheduleLagMs) {
      nextDueMs = nowMs - maxScheduleLagMs;
    }

    for (final sample in samples) {
      final int now = _clock.elapsedMilliseconds;
      if (nextDueMs > now) {
        await Future.delayed(Duration(milliseconds: nextDueMs - now));
      }

      final int epochNowMs = _toEpochMs(_clock.elapsedMilliseconds);
      final int previousTsRaw =
          _emittedTimestampByCmd[cmd] ?? (epochNowMs - stepMs);
      final int previousTs =
          previousTsRaw > epochNowMs ? (epochNowMs - stepMs) : previousTsRaw;
      int nextTs = previousTs + stepMs;
      final int minTs = epochNowMs - maxScheduleLagMs;
      if (nextTs < minTs) {
        // After packet stalls, do not keep emitting stale timestamps.
        // Keep stream time close to "now" so charts do not rewind on resume.
        nextTs = minTs;
      }
      if (nextTs > epochNowMs) {
        nextTs = epochNowMs;
      }
      if (nextTs <= previousTs) {
        nextTs = math.min(epochNowMs, previousTs + 1);
      }
      _emittedTimestampByCmd[cmd] = nextTs;
      sample['timestamp'] = nextTs;

      onEmitSample(sample);

      final int emitNow = _clock.elapsedMilliseconds;
      nextDueMs = math.max(nextDueMs, emitNow) + stepMs;
    }

    _nextDueByCmd[cmd] = nextDueMs;
  }

  void finishPacket({int? rawCmd, int? parsedCmd}) {
    if (parsedCmd != null) {
      _decrementPending(parsedCmd);
    }
    if (rawCmd != null && rawCmd != parsedCmd) {
      _decrementPending(rawCmd);
    }
  }

  int _toEpochMs(int monotonicMs) => _wallClockAnchorMs + monotonicMs;

  int _resolveStepMs({
    required int cmd,
    required int sampleCount,
    required int arrivalMs,
  }) {
    double delayMs =
        _delayEstimateByCmd[cmd] ?? defaultSampleDelayMs.toDouble();

    final int? lastArrival = _lastArrivalByCmd[cmd];
    if (lastArrival != null) {
      final int interArrivalMs = arrivalMs - lastArrival;
      if (interArrivalMs > 0 && sampleCount > 0) {
        final double observedDelayMs = (interArrivalMs / sampleCount).clamp(
          minSampleDelayMs.toDouble(),
          maxSampleDelayMs.toDouble(),
        );
        delayMs = delayMs + delayAlpha * (observedDelayMs - delayMs);
      }
    }
    _lastArrivalByCmd[cmd] = arrivalMs;

    final int backlog = math.max(0, (_pendingPacketsByCmd[cmd] ?? 1) - 1);
    if (backlog > 0) {
      final double compression =
          1.0 + math.min(backlog, 6) * backlogCompressionPerPacket;
      delayMs = delayMs / compression;
    }

    delayMs = delayMs.clamp(
      minSampleDelayMs.toDouble(),
      maxSampleDelayMs.toDouble(),
    );

    _delayEstimateByCmd[cmd] = delayMs;
    return delayMs.round();
  }

  void _decrementPending(int key) {
    final int? pending = _pendingPacketsByCmd[key];
    if (pending == null || pending <= 1) {
      _pendingPacketsByCmd.remove(key);
      return;
    }
    _pendingPacketsByCmd[key] = pending - 1;
  }
}

class OpenRingSensorConfig extends SensorConfig {
  int cmd;
  List<int> payload;

  OpenRingSensorConfig({required this.cmd, required this.payload});

  Uint8List toBytes() {
    final int randomByte = DateTime.now().microsecondsSinceEpoch & 0xFF;
    return Uint8List.fromList([0x00, randomByte, cmd, ...payload]);
  }
}
