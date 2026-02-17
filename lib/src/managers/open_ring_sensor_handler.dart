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
  static const Set<int> _pacedStreamingCommands = {
    OpenRingGatt.cmdIMU,
    OpenRingGatt.cmdPPGQ2,
  };

  Stream<Map<String, dynamic>>? _sensorDataStream;
  Future<void> _commandQueue = Future<void>.value();
  List<int>? _lastImuStartPayload;
  int _imuTimingResetCounter = 0;
  bool _temperatureStreamEnabled = false;
  final Set<int> _activeRealtimeStreamingCommands = {};
  final Set<int> _desiredRealtimeStreamingCommands = {};

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
    final bool imuWasStandaloneActiveBeforePpgStart = isPpgStart &&
        _activeRealtimeStreamingCommands.contains(OpenRingGatt.cmdIMU) &&
        !_activeRealtimeStreamingCommands.contains(OpenRingGatt.cmdPPGQ2);

    if (isImuStart) {
      _lastImuStartPayload = List<int>.from(sensorConfig.payload);
    }

    if (isImuStop) {
      _lastImuStartPayload = null;
    }

    if (isRealtimeStreamingStart) {
      _desiredRealtimeStreamingCommands.add(sensorConfig.cmd);
    } else if (isRealtimeStreamingStop) {
      _desiredRealtimeStreamingCommands.remove(sensorConfig.cmd);
      _activeRealtimeStreamingCommands.remove(sensorConfig.cmd);
    }

    if (imuWasStandaloneActiveBeforePpgStart) {
      _requestImuTimingReset();
    }
    if (isPpgStop &&
        _desiredRealtimeStreamingCommands.contains(OpenRingGatt.cmdIMU)) {
      _requestImuTimingReset();
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
      _activeRealtimeStreamingCommands.remove(OpenRingGatt.cmdIMU);
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
    _imuTimingResetCounter += 1;
  }

  Future<List<Map<String, dynamic>>> _parseData(List<int> data) async {
    final byteData = ByteData.sublistView(Uint8List.fromList(data));
    return _sensorValueParser.parse(byteData, []);
  }

  void setTemperatureStreamEnabled(bool enabled) {
    _temperatureStreamEnabled = enabled;
    logger.d('OpenRing software toggle: temperatureStream=$enabled');
  }

  bool get hasActiveRealtimeStreaming =>
      _activeRealtimeStreamingCommands.isNotEmpty ||
      _desiredRealtimeStreamingCommands.isNotEmpty;

  Map<String, dynamic> _filterTemperature(Map<String, dynamic> sample) {
    if (!_temperatureStreamEnabled) {
      sample.remove('Temperature');
    }
    return sample;
  }

  bool _shouldRouteImuThroughPpg() {
    return _desiredRealtimeStreamingCommands.contains(OpenRingGatt.cmdPPGQ2) ||
        _activeRealtimeStreamingCommands.contains(OpenRingGatt.cmdPPGQ2);
  }

  bool _shouldExposeImuFromPpg() {
    return _desiredRealtimeStreamingCommands.contains(OpenRingGatt.cmdIMU) ||
        _activeRealtimeStreamingCommands.contains(OpenRingGatt.cmdIMU);
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
    final bool hasImuPayload = filtered.containsKey('Accelerometer') ||
        filtered.containsKey('Gyroscope');
    final bool isPpgSample = cmd is int && cmd == OpenRingGatt.cmdPPGQ2;
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

    // Monotonic clock for all timing decisions.
    final clock = Stopwatch()..start();
    final int wallClockAnchorMs = DateTime.now().millisecondsSinceEpoch;

    int monotonicToEpochMs(int monotonicMs) {
      return wallClockAnchorMs + monotonicMs;
    }

    // Keep command families independent (PPG should not stall IMU).
    final Map<int, Future<void>> processingQueueByCmd = {};

    final Map<int, int> lastArrivalByCmd = {};
    final Map<int, double> delayEstimateByCmd = {};
    final Map<int, int> nextDueByCmd = {};
    final Map<int, int> emittedTimestampByCmd = {};
    final Map<int, int> pendingPacketsByCmd = {};
    int seenImuTimingResetCounter = _imuTimingResetCounter;

    void resetImuTimingStateIfRequested() {
      if (seenImuTimingResetCounter == _imuTimingResetCounter) {
        return;
      }

      seenImuTimingResetCounter = _imuTimingResetCounter;
      // IMU source can switch between cmd=0x40 standalone and
      // cmd=0x32-aliased samples while PPG is active. Reset paced scheduling
      // state so timestamps re-anchor cleanly across that transition.
      for (final int key in <int>[OpenRingGatt.cmdIMU, OpenRingGatt.cmdPPGQ2]) {
        lastArrivalByCmd.remove(key);
        delayEstimateByCmd.remove(key);
        nextDueByCmd.remove(key);
        emittedTimestampByCmd.remove(key);
      }
    }

    int resolveStepMs({
      required int cmd,
      required int sampleCount,
      required int arrivalMs,
    }) {
      double delayMs =
          delayEstimateByCmd[cmd] ?? _defaultSampleDelayMs.toDouble();

      final int? lastArrival = lastArrivalByCmd[cmd];
      if (lastArrival != null) {
        final int interArrivalMs = arrivalMs - lastArrival;
        if (interArrivalMs > 0 && sampleCount > 0) {
          final double observedDelayMs = (interArrivalMs / sampleCount).clamp(
            _minSampleDelayMs.toDouble(),
            _maxSampleDelayMs.toDouble(),
          );
          delayMs = delayMs + _delayAlpha * (observedDelayMs - delayMs);
        }
      }
      lastArrivalByCmd[cmd] = arrivalMs;

      final int backlog = math.max(0, (pendingPacketsByCmd[cmd] ?? 1) - 1);
      if (backlog > 0) {
        final double compression =
            1.0 + math.min(backlog, 6) * _backlogCompressionPerPacket;
        delayMs = delayMs / compression;
      }

      delayMs = delayMs.clamp(
        _minSampleDelayMs.toDouble(),
        _maxSampleDelayMs.toDouble(),
      );

      delayEstimateByCmd[cmd] = delayMs;
      return delayMs.round();
    }

    void decrementPending(int key) {
      final int? pending = pendingPacketsByCmd[key];
      if (pending == null || pending <= 1) {
        pendingPacketsByCmd.remove(key);
        return;
      }
      pendingPacketsByCmd[key] = pending - 1;
    }

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

        if (!_pacedStreamingCommands.contains(cmdKey)) {
          for (final sample in parsedData) {
            _emitSample(streamController, sample);
          }
          return;
        }

        final int stepMs = resolveStepMs(
          cmd: cmdKey,
          sampleCount: parsedData.length,
          arrivalMs: arrivalMs,
        );

        int nextDueMs = nextDueByCmd[cmdKey] ?? arrivalMs;
        final int nowMs = clock.elapsedMilliseconds;

        // Keep bounded catch-up to avoid both lag and hard jumps.
        if (nextDueMs < nowMs - _maxScheduleLagMs) {
          nextDueMs = nowMs - _maxScheduleLagMs;
        }

        for (final sample in parsedData) {
          final int now = clock.elapsedMilliseconds;
          if (nextDueMs > now) {
            await Future.delayed(Duration(milliseconds: nextDueMs - now));
          }

          final int epochNowMs = monotonicToEpochMs(clock.elapsedMilliseconds);
          final int previousTsRaw =
              emittedTimestampByCmd[cmdKey] ?? (epochNowMs - stepMs);
          // Mode switches can leave a command timeline slightly ahead; re-anchor
          // before assigning sample time to avoid future timestamps.
          final int previousTs = previousTsRaw > epochNowMs
              ? (epochNowMs - stepMs)
              : previousTsRaw;
          int nextTs = previousTs + stepMs;
          if (nextTs > epochNowMs) {
            nextTs = epochNowMs;
          }
          emittedTimestampByCmd[cmdKey] = nextTs;
          sample['timestamp'] = nextTs;

          _emitSample(streamController, sample);

          final int emitNow = clock.elapsedMilliseconds;
          nextDueMs = math.max(nextDueMs, emitNow) + stepMs;
        }

        nextDueByCmd[cmdKey] = nextDueMs;
      } finally {
        if (cmdKey != null) {
          decrementPending(cmdKey);
        }
        if (rawCmd != null && rawCmd != cmdKey) {
          decrementPending(rawCmd);
        }
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
            resetImuTimingStateIfRequested();
            _updateRealtimeStreamingStateFromPacket(data);

            final int? rawCmd = data.length > 2 ? data[2] : null;
            if (rawCmd != null) {
              pendingPacketsByCmd[rawCmd] =
                  (pendingPacketsByCmd[rawCmd] ?? 0) + 1;
            }

            final int arrivalMs = clock.elapsedMilliseconds;
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
          lastArrivalByCmd.clear();
          delayEstimateByCmd.clear();
          nextDueByCmd.clear();
          emittedTimestampByCmd.clear();
          pendingPacketsByCmd.clear();
          _lastImuStartPayload = null;
          _activeRealtimeStreamingCommands.clear();
          _desiredRealtimeStreamingCommands.clear();

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

  Future<void> _queueImuSuspendForPpgStart() async {
    _commandQueue =
        _commandQueue.catchError((Object error, StackTrace stackTrace) {
      logger.e('OpenRing previous command failed: $error');
      logger.t(stackTrace);
    }).then((_) async {
      if (!_bleManager.isConnected(_discoveredDevice.id)) {
        return;
      }
      if (!_desiredRealtimeStreamingCommands.contains(OpenRingGatt.cmdPPGQ2)) {
        return;
      }
      if (!_desiredRealtimeStreamingCommands.contains(OpenRingGatt.cmdIMU) &&
          !_activeRealtimeStreamingCommands.contains(OpenRingGatt.cmdIMU)) {
        return;
      }

      await _writeCommand(
        OpenRingSensorConfig(cmd: OpenRingGatt.cmdIMU, payload: const [0x00]),
      );
      _activeRealtimeStreamingCommands.remove(OpenRingGatt.cmdIMU);
      await Future.delayed(
        const Duration(milliseconds: _commandSettleDelayMs),
      );
    });

    await _commandQueue;
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

      final List<int>? imuStartPayload = _lastImuStartPayload;
      if (imuStartPayload == null) {
        return;
      }
      if (!_desiredRealtimeStreamingCommands.contains(OpenRingGatt.cmdIMU)) {
        return;
      }

      await _writeCommand(
        OpenRingSensorConfig(
          cmd: OpenRingGatt.cmdIMU,
          payload: List<int>.from(imuStartPayload),
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
        _activeRealtimeStreamingCommands.remove(cmd);
        return;
      }

      if (data.length < 5) {
        return;
      }

      final int packetValue = data[4] & 0xFF;

      // Realtime waveform packets imply active streaming.
      if (packetType == 0x01 || packetType == 0x02) {
        _activeRealtimeStreamingCommands.add(cmd);
        return;
      }

      // Final/result and terminal error packets indicate no active realtime stream.
      if (packetType == 0x00 &&
          (packetValue == 0 || // not worn
              packetValue == 2 || // charging
              packetValue == 3 || // final result
              packetValue == 4)) {
        _activeRealtimeStreamingCommands.remove(cmd);
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
        _activeRealtimeStreamingCommands.remove(cmd);
        return;
      }

      if ((subOpcode == 0x01 || subOpcode == 0x04) && status != 0x01) {
        _activeRealtimeStreamingCommands.add(cmd);
        return;
      }

      if (subOpcode == 0x06 && status != 0x01) {
        _activeRealtimeStreamingCommands.add(cmd);
      }
    }
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
