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
  static const int _imuResyncAfterPpgStopDelayMs = 120;
  static const List<int> _imuDefaultStartPayload = <int>[0x06];
  static const List<int> _ppgRealtimeStartPayload = <int>[
    0x00,
    0x00,
    0x19,
    0x01,
    0x01,
  ];
  static const List<int> _ppgRealtimeStopPayload = <int>[0x06];
  static const Set<int> _pacedStreamingCommands = {
    OpenRingGatt.cmdIMU,
    OpenRingGatt.cmdPPGQ2,
  };

  Stream<Map<String, dynamic>>? _sensorDataStream;
  Future<void> _commandQueue = Future<void>.value();
  final _OpenRingRealtimeState _realtimeState = _OpenRingRealtimeState();

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

    final bool isRealtimeStreamingStart =
        _isRealtimeStreamingStart(sensorConfig);
    final bool isRealtimeStreamingStop = _isRealtimeStreamingStop(sensorConfig);

    final bool isPpgCmd = sensorConfig.cmd == OpenRingGatt.cmdPPGQ2;
    final bool isPpgStart = isPpgCmd &&
        sensorConfig.payload.isNotEmpty &&
        sensorConfig.payload[0] == 0x00;
    final bool isPpgStop = isPpgCmd &&
        sensorConfig.payload.isNotEmpty &&
        sensorConfig.payload[0] == 0x06;
    final bool isImuCmd = sensorConfig.cmd == OpenRingGatt.cmdIMU;
    final bool isImuStart = isImuCmd && isRealtimeStreamingStart;
    final bool isImuStop = isImuCmd && isRealtimeStreamingStop;
    final bool isPpgStartWhileAlreadyActive =
        isPpgStart && _realtimeState.isCommandActive(OpenRingGatt.cmdPPGQ2);
    final bool skipPpgStopBecauseTemperatureRequiresTransport =
        isPpgStop && _realtimeState.temperatureRequiresPpgTransport;
    final bool imuWasStandaloneActiveBeforePpgStart = isPpgStart &&
        _realtimeState.isCommandActive(OpenRingGatt.cmdIMU) &&
        !_realtimeState.isCommandActive(OpenRingGatt.cmdPPGQ2);

    if (isImuStart) {
      _realtimeState.noteImuStartPayload(sensorConfig.payload);
    }

    if (isImuStop) {
      _realtimeState.clearImuStartPayload();
    }

    if (isRealtimeStreamingStart) {
      _realtimeState.markDesiredStart(sensorConfig.cmd);
    } else if (isRealtimeStreamingStop) {
      _realtimeState.markDesiredStop(sensorConfig.cmd);
      if (!skipPpgStopBecauseTemperatureRequiresTransport) {
        _realtimeState.markInactive(sensorConfig.cmd);
      }
    }

    if (imuWasStandaloneActiveBeforePpgStart) {
      _requestImuTimingReset();
    }
    if (isPpgStop &&
        !skipPpgStopBecauseTemperatureRequiresTransport &&
        _realtimeState.isCommandDesired(OpenRingGatt.cmdIMU)) {
      _requestImuTimingReset();
    }

    if (isPpgStartWhileAlreadyActive) {
      logger.d(
        'OpenRing PPG start skipped because cmd=0x32 realtime is already active',
      );
      return;
    }

    if (skipPpgStopBecauseTemperatureRequiresTransport) {
      logger.d(
        'OpenRing PPG stop skipped because temperature streaming '
        'still requires cmd=0x32 transport',
      );
      return;
    }

    if (isImuCmd && _shouldRouteImuThroughPpg()) {
      if (isImuStart) {
        logger.d(
          'OpenRing IMU start skipped because PPG realtime is active; '
          'routing accelerometer/gyroscope via cmd=0x32',
        );
      } else if (isImuStop) {
        logger.d(
          'OpenRing IMU stop handled in software while PPG realtime is active',
        );
      }
      _realtimeState.markInactive(OpenRingGatt.cmdIMU);
      return;
    }

    Future<void> writeFuture;
    if (imuWasStandaloneActiveBeforePpgStart) {
      writeFuture = _queueImuSuspendForPpgStart().then(
        (_) => _enqueueCommandWrite(sensorConfig),
      );
    } else {
      writeFuture = _enqueueCommandWrite(sensorConfig);
    }
    if (isPpgStop) {
      writeFuture = writeFuture.then((_) => _queueImuResyncAfterPpgStop());
    }

    await writeFuture;
  }

  void _requestImuTimingReset() {
    _realtimeState.requestImuTimingReset();
  }

  Future<List<Map<String, dynamic>>> _parseData(List<int> data) async {
    final byteData = ByteData.sublistView(Uint8List.fromList(data));
    return _sensorValueParser.parse(byteData, []);
  }

  void setTemperatureStreamEnabled(bool enabled) {
    final bool changed = _realtimeState.temperatureStreamEnabled != enabled;
    final int requestVersion = _realtimeState.setTemperatureStreamEnabled(
      enabled,
    );
    logger.d('OpenRing software toggle: temperatureStream=$enabled');

    if (!changed) {
      return;
    }

    if (enabled) {
      unawaited(_queuePpgTransportStartForTemperature(requestVersion));
      return;
    }

    unawaited(_queuePpgTransportStopIfUnused(requestVersion));
  }

  bool get hasActiveRealtimeStreaming => _realtimeState.hasAnyRealtimeStreaming;

  Map<String, dynamic> _filterTemperature(Map<String, dynamic> sample) {
    if (!_realtimeState.temperatureStreamEnabled) {
      sample.remove('Temperature');
    }
    return sample;
  }

  bool _shouldRouteImuThroughPpg() {
    return _isPpgDesiredByAnySource() ||
        _realtimeState.isCommandActive(OpenRingGatt.cmdPPGQ2);
  }

  bool _isPpgDesiredByAnySource() {
    return _realtimeState.ppgDesiredByAnySource;
  }

  bool _shouldExposeImuFromPpg() {
    return _realtimeState.shouldExposeImuFromPpg;
  }

  bool _shouldExposePpgFromPpg() {
    return _realtimeState.shouldExposePpgFromPpg;
  }

  void _emitSample(
    StreamController<Map<String, dynamic>> streamController,
    Map<String, dynamic> sample,
  ) {
    if (streamController.isClosed) {
      return;
    }

    final filtered = _filterTemperature(Map<String, dynamic>.from(sample));

    final dynamic cmd = filtered['cmd'];
    final bool hasPpgPayload = filtered.containsKey('PPG');
    final bool hasImuPayload = filtered.containsKey('Accelerometer') ||
        filtered.containsKey('Gyroscope');
    final bool isPpgSample = cmd is int && cmd == OpenRingGatt.cmdPPGQ2;
    if (isPpgSample && hasPpgPayload && !_shouldExposePpgFromPpg()) {
      filtered.remove('PPG');
    }
    if (isPpgSample && hasImuPayload && !_shouldExposeImuFromPpg()) {
      filtered.remove('Accelerometer');
      filtered.remove('Gyroscope');
    }
    streamController.add(filtered);

    if (!isPpgSample || !hasImuPayload || !_shouldExposeImuFromPpg()) {
      return;
    }

    final imuAlias = Map<String, dynamic>.from(filtered);
    imuAlias['cmd'] = OpenRingGatt.cmdIMU;
    imuAlias.remove('PPG');
    imuAlias.remove('Temperature');
    streamController.add(imuAlias);
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

        if (cmdKey == null) {
          for (final sample in parsedData) {
            _emitSample(streamController, sample);
          }
          return;
        }

        if (!scheduler.isPacedCommand(cmdKey)) {
          for (final sample in parsedData) {
            _emitSample(streamController, sample);
          }
          return;
        }

        await scheduler.emitPacedSamples(
          cmd: cmdKey,
          samples: parsedData,
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
              _realtimeState.imuTimingResetCounter,
              const <int>[OpenRingGatt.cmdIMU, OpenRingGatt.cmdPPGQ2],
            );
            _updateRealtimeStreamingStateFromPacket(data);

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
          _realtimeState.clearRuntimeStreamingState();

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

  Future<void> _enqueueCommandWrite(
    OpenRingSensorConfig sensorConfig, {
    Duration delayBefore = Duration.zero,
  }) {
    _commandQueue =
        _commandQueue.catchError((Object error, StackTrace stackTrace) {
      logger.e('OpenRing previous command failed: $error');
      logger.t(stackTrace);
    }).then((_) async {
      if (!_bleManager.isConnected(_discoveredDevice.id)) {
        logger.w(
          'Skipping OpenRing command while disconnected: '
          'cmd=${sensorConfig.cmd}',
        );
        return;
      }

      if (delayBefore > Duration.zero) {
        await Future.delayed(delayBefore);
      }

      await _writeCommand(sensorConfig);
      await Future.delayed(
        const Duration(milliseconds: _commandSettleDelayMs),
      );
    });

    return _commandQueue;
  }

  Future<bool> _enqueueConditionalCommandWrite(
    OpenRingSensorConfig sensorConfig, {
    required bool Function() shouldWrite,
    required String staleReason,
    Duration delayBefore = Duration.zero,
  }) {
    final completer = Completer<bool>();

    _commandQueue =
        _commandQueue.catchError((Object error, StackTrace stackTrace) {
      logger.e('OpenRing previous command failed: $error');
      logger.t(stackTrace);
    }).then((_) async {
      try {
        if (!_bleManager.isConnected(_discoveredDevice.id)) {
          if (!completer.isCompleted) {
            completer.complete(false);
          }
          return;
        }
        if (!shouldWrite()) {
          logger.d('Skipping OpenRing command (stale): $staleReason');
          if (!completer.isCompleted) {
            completer.complete(false);
          }
          return;
        }

        if (delayBefore > Duration.zero) {
          await Future.delayed(delayBefore);
        }
        if (!shouldWrite()) {
          logger.d('Skipping OpenRing command (stale): $staleReason');
          if (!completer.isCompleted) {
            completer.complete(false);
          }
          return;
        }

        await _writeCommand(sensorConfig);
        await Future.delayed(
          const Duration(milliseconds: _commandSettleDelayMs),
        );
        if (!completer.isCompleted) {
          completer.complete(true);
        }
      } catch (error, stackTrace) {
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
        rethrow;
      }
    });

    return completer.future;
  }

  Future<void> _queueImuSuspendForPpgStart() async {
    _commandQueue =
        _commandQueue.catchError((Object error, StackTrace stackTrace) {
      logger.e('OpenRing previous command failed: $error');
      logger.t(stackTrace);
    }).then((_) async {
      if (!_bleManager.isConnected(_discoveredDevice.id)) {
        return;
      }
      if (!_isPpgDesiredByAnySource()) {
        return;
      }
      if (!_realtimeState.isCommandDesired(OpenRingGatt.cmdIMU) &&
          !_realtimeState.isCommandActive(OpenRingGatt.cmdIMU)) {
        return;
      }

      await _writeCommand(
        OpenRingSensorConfig(cmd: OpenRingGatt.cmdIMU, payload: const [0x00]),
      );
      _realtimeState.markInactive(OpenRingGatt.cmdIMU);
      await Future.delayed(
        const Duration(milliseconds: _commandSettleDelayMs),
      );
    });

    await _commandQueue;
  }

  Future<void> _queuePpgTransportStartForTemperature(int requestVersion) async {
    if (requestVersion != _realtimeState.temperatureTransportRequestVersion) {
      return;
    }
    if (!_realtimeState.temperatureRequiresPpgTransport) {
      return;
    }
    if (!_bleManager.isConnected(_discoveredDevice.id)) {
      return;
    }
    if (_realtimeState.isCommandActive(OpenRingGatt.cmdPPGQ2) ||
        _realtimeState.isCommandDesired(OpenRingGatt.cmdPPGQ2)) {
      return;
    }

    final bool imuWasStandaloneActive =
        _realtimeState.isCommandActive(OpenRingGatt.cmdIMU) &&
            !_realtimeState.isCommandActive(OpenRingGatt.cmdPPGQ2);
    if (imuWasStandaloneActive) {
      _requestImuTimingReset();
      await _queueImuSuspendForPpgStart();
    }

    await _enqueueConditionalCommandWrite(
      OpenRingSensorConfig(
        cmd: OpenRingGatt.cmdPPGQ2,
        payload: List<int>.from(_ppgRealtimeStartPayload),
      ),
      shouldWrite: () =>
          requestVersion == _realtimeState.temperatureTransportRequestVersion &&
          _realtimeState.temperatureRequiresPpgTransport &&
          !_realtimeState.isCommandDesired(OpenRingGatt.cmdPPGQ2) &&
          !_realtimeState.isCommandActive(OpenRingGatt.cmdPPGQ2),
      staleReason: 'temperature start superseded',
    );
  }

  Future<void> _queuePpgTransportStopIfUnused(int requestVersion) async {
    if (requestVersion != _realtimeState.temperatureTransportRequestVersion) {
      return;
    }
    if (_realtimeState.temperatureRequiresPpgTransport) {
      return;
    }
    if (!_bleManager.isConnected(_discoveredDevice.id)) {
      return;
    }
    if (_realtimeState.isCommandDesired(OpenRingGatt.cmdPPGQ2)) {
      return;
    }
    final bool imuDesired =
        _realtimeState.isCommandDesired(OpenRingGatt.cmdIMU);

    if (!_realtimeState.isCommandActive(OpenRingGatt.cmdPPGQ2)) {
      if (imuDesired && !_isPpgDesiredByAnySource()) {
        await _queueImuResyncAfterPpgStop();
      }
      return;
    }

    final bool stopWritten = await _enqueueConditionalCommandWrite(
      OpenRingSensorConfig(
        cmd: OpenRingGatt.cmdPPGQ2,
        payload: List<int>.from(_ppgRealtimeStopPayload),
      ),
      shouldWrite: () =>
          requestVersion == _realtimeState.temperatureTransportRequestVersion &&
          !_realtimeState.temperatureRequiresPpgTransport &&
          !_realtimeState.isCommandDesired(OpenRingGatt.cmdPPGQ2) &&
          _realtimeState.isCommandActive(OpenRingGatt.cmdPPGQ2),
      staleReason: 'temperature stop superseded',
    );
    if (!stopWritten) {
      if (imuDesired &&
          !_isPpgDesiredByAnySource() &&
          !_realtimeState.isCommandActive(OpenRingGatt.cmdPPGQ2)) {
        await _queueImuResyncAfterPpgStop();
      }
      return;
    }

    if (imuDesired) {
      _requestImuTimingReset();
    }

    _realtimeState.markInactive(OpenRingGatt.cmdPPGQ2);

    if (imuDesired && !_isPpgDesiredByAnySource()) {
      await _queueImuResyncAfterPpgStop();
    }
  }

  Future<void> _queueImuResyncAfterPpgStop() async {
    _commandQueue =
        _commandQueue.catchError((Object error, StackTrace stackTrace) {
      logger.e('OpenRing previous command failed: $error');
      logger.t(stackTrace);
    }).then((_) async {
      if (!_bleManager.isConnected(_discoveredDevice.id)) {
        return;
      }

      await Future.delayed(
        const Duration(milliseconds: _imuResyncAfterPpgStopDelayMs),
      );

      if (!_realtimeState.isCommandDesired(OpenRingGatt.cmdIMU)) {
        return;
      }
      if (_isPpgDesiredByAnySource() ||
          _realtimeState.isCommandActive(OpenRingGatt.cmdPPGQ2)) {
        return;
      }
      final List<int> imuStartPayload = _realtimeState.resolveImuStartPayload(
        _imuDefaultStartPayload,
      );

      await _writeCommand(
        OpenRingSensorConfig(
          cmd: OpenRingGatt.cmdIMU,
          payload: imuStartPayload,
        ),
      );
      await Future.delayed(
        const Duration(milliseconds: _commandSettleDelayMs),
      );
    });

    await _commandQueue;
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

  void _updateRealtimeStreamingStateFromPacket(List<int> data) {
    if (data.length < 4 || data[0] != 0x00) {
      return;
    }

    final int cmd = data[2] & 0xFF;

    if (cmd == OpenRingGatt.cmdPPGQ2) {
      final int packetType = data[3] & 0xFF;

      // Stop ack can be a 4-byte control frame.
      if (packetType == 0x06) {
        _realtimeState.markInactive(cmd);
        return;
      }

      if (data.length < 5) {
        return;
      }

      final int packetValue = data[4] & 0xFF;

      // Realtime waveform packets imply active streaming.
      if (packetType == 0x01 || packetType == 0x02) {
        _realtimeState.markActive(cmd);
        return;
      }

      // Final/result and terminal error packets indicate no active realtime stream.
      if (packetType == 0x00 &&
          (packetValue == 0 || // not worn
              packetValue == 2 || // charging
              packetValue == 3 || // final result
              packetValue == 4)) {
        _realtimeState.markInactive(cmd);
      }
      return;
    }

    if (cmd == OpenRingGatt.cmdIMU) {
      if (data.length < 5) {
        return;
      }

      final int subOpcode = data[3] & 0xFF;
      final int status = data[4] & 0xFF;

      if (subOpcode == 0x00) {
        _realtimeState.markInactive(cmd);
        return;
      }

      if ((subOpcode == 0x01 || subOpcode == 0x04) && status != 0x01) {
        _realtimeState.markActive(cmd);
        return;
      }

      if (subOpcode == 0x06 && status != 0x01) {
        _realtimeState.markActive(cmd);
      }
    }
  }
}

class _OpenRingRealtimeState {
  List<int>? lastImuStartPayload;
  int imuTimingResetCounter = 0;
  bool temperatureStreamEnabled = false;
  bool temperatureRequiresPpgTransport = false;
  int temperatureTransportRequestVersion = 0;
  final Set<int> activeCommands = <int>{};
  final Set<int> desiredCommands = <int>{};

  bool get hasAnyRealtimeStreaming =>
      activeCommands.isNotEmpty ||
      desiredCommands.isNotEmpty ||
      temperatureRequiresPpgTransport;

  bool get ppgDesiredByAnySource =>
      desiredCommands.contains(OpenRingGatt.cmdPPGQ2) ||
      temperatureRequiresPpgTransport;

  bool get shouldExposeImuFromPpg =>
      desiredCommands.contains(OpenRingGatt.cmdIMU) ||
      activeCommands.contains(OpenRingGatt.cmdIMU);

  bool get shouldExposePpgFromPpg =>
      desiredCommands.contains(OpenRingGatt.cmdPPGQ2);

  bool isCommandDesired(int cmd) => desiredCommands.contains(cmd);

  bool isCommandActive(int cmd) => activeCommands.contains(cmd);

  void noteImuStartPayload(List<int> payload) {
    lastImuStartPayload = List<int>.from(payload);
  }

  void clearImuStartPayload() {
    lastImuStartPayload = null;
  }

  void markDesiredStart(int cmd) {
    desiredCommands.add(cmd);
  }

  void markDesiredStop(int cmd) {
    desiredCommands.remove(cmd);
  }

  void markActive(int cmd) {
    activeCommands.add(cmd);
  }

  void markInactive(int cmd) {
    activeCommands.remove(cmd);
  }

  void requestImuTimingReset() {
    imuTimingResetCounter += 1;
  }

  int setTemperatureStreamEnabled(bool enabled) {
    final bool changed = temperatureStreamEnabled != enabled;
    temperatureStreamEnabled = enabled;
    temperatureRequiresPpgTransport = enabled;
    if (changed) {
      temperatureTransportRequestVersion += 1;
    }
    return temperatureTransportRequestVersion;
  }

  List<int> resolveImuStartPayload(List<int> defaultPayload) {
    return List<int>.from(lastImuStartPayload ?? defaultPayload);
  }

  void clearRuntimeStreamingState() {
    lastImuStartPayload = null;
    activeCommands.clear();
    desiredCommands.clear();
    temperatureRequiresPpgTransport = false;
  }
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
      if (nextTs > epochNowMs) {
        nextTs = epochNowMs;
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
