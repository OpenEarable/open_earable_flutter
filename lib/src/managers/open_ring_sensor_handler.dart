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
  static const List<int> _imuStartPayload = <int>[0x06];
  static const List<int> _imuStopPayload = <int>[0x00];
  static const List<int> _ppgRealtimeStartPayload = <int>[
    0x00,
    0x00,
    0x19,
    0x01,
    0x01,
  ];
  static const List<int> _ppgRealtimeStopPayload = <int>[0x06];
  static const List<int> _ppgGreenOnlyStartPayload = <int>[
    0x00,
    0x00,
    0x19,
    0x01,
    0x00,
    0x00,
    0x01,
    0x01,
  ];
  static const List<int> _ppgGreenOnlyStopPayload = <int>[0x04];
  static const Set<int> _pacedStreamingCommands = {
    OpenRingGatt.cmdIMU,
    OpenRingGatt.cmdPPGQ2,
    OpenRingGatt.cmdHeartRota,
    OpenRingGatt.cmdPpgShoushi,
    OpenRingGatt.cmdRealTimePpg,
  };
  static const List<int> _timingResetCommands = <int>[
    OpenRingGatt.cmdIMU,
    OpenRingGatt.cmdPPGQ2,
    OpenRingGatt.cmdHeartRota,
    OpenRingGatt.cmdPpgShoushi,
    OpenRingGatt.cmdRealTimePpg,
  ];
  static const Map<int, int> _sampleDelayMsByCommand = <int, int>{
    OpenRingGatt.cmdHeartRota: 40,
    OpenRingGatt.cmdPpgShoushi: 40,
    OpenRingGatt.cmdRealTimePpg: 40,
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
  bool _lastAppliedImuEnabled = false;
  int? _lastAppliedPpgCmd;

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
      if (cmd is! int) {
        return false;
      }
      if (cmd == sensorId) {
        return true;
      }
      return sensorId == OpenRingGatt.cmdPPGQ2 && _isGreenOnlyPpgCommand(cmd);
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
      _enqueueApplyDesiredTransport(reason: 'temperature-set-$enabled'),
    );
  }

  void setInitialStreamingDetectedCallback(void Function()? callback) {
    _onInitialStreamingDetected = callback;
  }

  bool get hasActiveRealtimeStreaming =>
      _desiredState.hasAnyEnabled ||
      _isApplying ||
      _lastAppliedImuEnabled ||
      _lastAppliedPpgCmd != null;

  bool _isRealtimeStreamingCommand(int cmd) =>
      cmd == OpenRingGatt.cmdIMU ||
      cmd == OpenRingGatt.cmdPPGQ2 ||
      _isGreenOnlyPpgCommand(cmd);

  bool _isGreenOnlyPpgCommand(int cmd) =>
      cmd == OpenRingGatt.cmdHeartRota ||
      cmd == OpenRingGatt.cmdPpgShoushi ||
      cmd == OpenRingGatt.cmdRealTimePpg;

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

    if (sensorConfig.cmd == OpenRingGatt.cmdPPGQ2 ||
        _isGreenOnlyPpgCommand(sensorConfig.cmd)) {
      if (isStart) {
        _desiredState.ppgEnabled = true;
        _desiredState.ppgCmd = sensorConfig.cmd;
      } else {
        _desiredState.ppgEnabled = false;
      }
    }
  }

  Future<void> _enqueueApplyDesiredTransport({required String reason}) {
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

    final int? desiredPpgCmd = _desiredState.desiredPpgTransportCmd;
    final bool desiredStandaloneImuEnabled =
        _desiredState.imuEnabled && desiredPpgCmd != OpenRingGatt.cmdPPGQ2;
    if (desiredStandaloneImuEnabled == _lastAppliedImuEnabled &&
        desiredPpgCmd == _lastAppliedPpgCmd) {
      return;
    }

    _isApplying = true;
    try {
      logger.d(
        'OpenRing apply transport ($reason): '
        '${_desiredState.debugSummary()}',
      );

      if (_lastAppliedPpgCmd != null && _lastAppliedPpgCmd != desiredPpgCmd) {
        await _writeCommand(
          OpenRingSensorConfig(
            cmd: _lastAppliedPpgCmd!,
            payload: List<int>.from(_ppgStopPayloadFor(_lastAppliedPpgCmd!)),
          ),
        );
        _transportTimingResetCounter += 1;
        _lastAppliedPpgCmd = null;
        await Future.delayed(
          const Duration(milliseconds: _commandSettleDelayMs),
        );
        if (!_shouldContinueApply(requestVersion)) {
          return;
        }
      }

      if (_lastAppliedImuEnabled && !desiredStandaloneImuEnabled) {
        await _writeCommand(
          OpenRingSensorConfig(
            cmd: OpenRingGatt.cmdIMU,
            payload: List<int>.from(_imuStopPayload),
          ),
        );
        _transportTimingResetCounter += 1;
        _lastAppliedImuEnabled = false;
        await Future.delayed(
          const Duration(milliseconds: _commandSettleDelayMs),
        );
        if (!_shouldContinueApply(requestVersion)) {
          return;
        }
      }

      if (!_lastAppliedImuEnabled && desiredStandaloneImuEnabled) {
        await _writeCommand(
          OpenRingSensorConfig(
            cmd: OpenRingGatt.cmdIMU,
            payload: List<int>.from(_imuStartPayload),
          ),
        );
        _transportTimingResetCounter += 1;
        _lastAppliedImuEnabled = true;
        await Future.delayed(
          const Duration(milliseconds: _commandSettleDelayMs),
        );
        if (!_shouldContinueApply(requestVersion)) {
          return;
        }
      }

      if (_lastAppliedPpgCmd == null && desiredPpgCmd != null) {
        await _writeCommand(
          OpenRingSensorConfig(
            cmd: desiredPpgCmd,
            payload: List<int>.from(_ppgStartPayloadFor(desiredPpgCmd)),
          ),
        );
        _transportTimingResetCounter += 1;
        _lastAppliedPpgCmd = desiredPpgCmd;
        await Future.delayed(
          const Duration(milliseconds: _commandSettleDelayMs),
        );
      }
    } finally {
      _isApplying = false;
    }
  }

  bool _shouldContinueApply(int requestVersion) {
    return requestVersion == _applyVersion &&
        _bleManager.isConnected(_discoveredDevice.id);
  }

  List<int> _ppgStartPayloadFor(int cmd) {
    if (_isGreenOnlyPpgCommand(cmd)) {
      return _ppgGreenOnlyStartPayload;
    }
    return _ppgRealtimeStartPayload;
  }

  List<int> _ppgStopPayloadFor(int cmd) {
    if (_isGreenOnlyPpgCommand(cmd)) {
      return _ppgGreenOnlyStopPayload;
    }
    return _ppgRealtimeStopPayload;
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

    if (cmd is int && cmd == OpenRingGatt.cmdPPGQ2) {
      if (_desiredState.desiredPpgTransportCmd != OpenRingGatt.cmdPPGQ2) {
        return;
      }
      if (_desiredState.imuEnabled && _hasImuPayload(filtered)) {
        final imuSample = Map<String, dynamic>.from(filtered);
        imuSample['cmd'] = OpenRingGatt.cmdIMU;
        imuSample['sourceCmd'] = OpenRingGatt.cmdPPGQ2;
        imuSample.remove('PPG');
        imuSample.remove('Temperature');
        _emitIfSampleHasSensorPayload(streamController, imuSample);
      }
      if (!_desiredState.temperatureEnabled) {
        filtered.remove('Temperature');
      }
      if (!_desiredState.ppgEnabled) {
        filtered.remove('PPG');
      } else if (_desiredState.greenOnlyPpgRequested) {
        _keepOnlyGreenPpgChannel(filtered);
      }
      _removeImuPayload(filtered);
      _emitIfSampleHasSensorPayload(streamController, filtered);
      return;
    }

    if (cmd is int && _isGreenOnlyPpgCommand(cmd)) {
      if (_desiredState.desiredPpgTransportCmd != cmd ||
          !_desiredState.ppgEnabled) {
        return;
      }
      filtered.remove('Temperature');
      _removeImuPayload(filtered);
      _keepOnlyGreenPpgChannel(filtered);
      _emitIfSampleHasSensorPayload(streamController, filtered);
      return;
    }

    if (cmd is int && cmd == OpenRingGatt.cmdIMU) {
      if (!_desiredState.imuEnabled) {
        return;
      }
      filtered.remove('PPG');
      filtered.remove('Temperature');
      _emitIfSampleHasSensorPayload(streamController, filtered);
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

  void _keepOnlyGreenPpgChannel(Map<String, dynamic> sample) {
    final ppg = sample['PPG'];
    if (ppg is! Map) {
      return;
    }
    final dynamic green = ppg['Green'];
    if (green == null) {
      sample.remove('PPG');
      return;
    }
    sample['PPG'] = <String, dynamic>{
      'Red': 0,
      'Infrared': 0,
      'Green': green,
    };
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

    final bool hasImuPayload = _hasImuPayload(sample);
    final bool hasPpgPayload = sample.containsKey('PPG');
    final bool hasTemperaturePayload = sample.containsKey('Temperature');

    if (cmd == OpenRingGatt.cmdPPGQ2) {
      if (_desiredState.desiredPpgTransportCmd != OpenRingGatt.cmdPPGQ2) {
        return false;
      }
      final bool shouldEmitImu = _desiredState.imuEnabled && hasImuPayload;
      final bool shouldEmitPpg = _desiredState.ppgEnabled && hasPpgPayload;
      final bool shouldEmitTemperature =
          _desiredState.temperatureEnabled && hasTemperaturePayload;
      return shouldEmitImu || shouldEmitPpg || shouldEmitTemperature;
    }

    if (_isGreenOnlyPpgCommand(cmd)) {
      return _desiredState.desiredPpgTransportCmd == cmd &&
          _desiredState.ppgEnabled &&
          hasPpgPayload;
    }

    if (cmd == OpenRingGatt.cmdIMU) {
      return _desiredState.imuEnabled && hasImuPayload;
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
    if (!_hasAnySensorPayload(sample)) {
      return;
    }

    if (cmd == OpenRingGatt.cmdIMU) {
      _hasAdoptedInitialStreamingState = true;
      _desiredState.imuEnabled = true;
      _lastAppliedImuEnabled = true;
      _transportTimingResetCounter += 1;

      logger.i(
        'OpenRing detected active IMU stream on initial start; '
        'assuming IMU enabled',
      );
      return;
    }

    if (cmd == OpenRingGatt.cmdPPGQ2 || _isGreenOnlyPpgCommand(cmd)) {
      _hasAdoptedInitialStreamingState = true;
      _desiredState.ppgEnabled = sample.containsKey('PPG');
      _desiredState.ppgCmd = cmd;
      _desiredState.temperatureEnabled = sample.containsKey('Temperature');
      _lastAppliedPpgCmd = _desiredState.desiredPpgTransportCmd;
      _transportTimingResetCounter += 1;

      logger.i(
        'OpenRing detected active PPG stream on initial start; '
        'assuming PPG transport enabled',
      );
      if (_desiredState.ppgEnabled && _desiredState.temperatureEnabled) {
        _onInitialStreamingDetected?.call();
      }
    }
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
      sampleDelayMsByCommand: _sampleDelayMsByCommand,
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
              _timingResetCommands,
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

    if (_isGreenOnlyPpgCommand(sensorConfig.cmd)) {
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

    if (sensorConfig.cmd == OpenRingGatt.cmdHeartRota) {
      return sensorConfig.payload[0] == 0x04;
    }

    if (sensorConfig.cmd == OpenRingGatt.cmdPpgShoushi) {
      return sensorConfig.payload[0] == 0x06;
    }

    if (sensorConfig.cmd == OpenRingGatt.cmdRealTimePpg) {
      return sensorConfig.payload[0] == 0x04;
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
  int ppgCmd = OpenRingGatt.cmdPPGQ2;

  int? get desiredPpgTransportCmd {
    if (temperatureEnabled) {
      return OpenRingGatt.cmdPPGQ2;
    }
    if (ppgEnabled) {
      return ppgCmd;
    }
    return null;
  }

  bool get requiresPpgTransport => desiredPpgTransportCmd != null;

  bool get greenOnlyPpgRequested =>
      ppgCmd == OpenRingGatt.cmdHeartRota ||
      ppgCmd == OpenRingGatt.cmdPpgShoushi ||
      ppgCmd == OpenRingGatt.cmdRealTimePpg;

  bool get hasAnyEnabled => imuEnabled || requiresPpgTransport;

  String debugSummary() {
    return 'imu=$imuEnabled ppg=$ppgEnabled temp=$temperatureEnabled '
        'ppgCmd=$ppgCmd ppgTransport=$desiredPpgTransportCmd';
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
    this.sampleDelayMsByCommand = const <int, int>{},
  })  : _clock = Stopwatch()..start(),
        _wallClockAnchorMs = DateTime.now().millisecondsSinceEpoch;

  final Set<int> pacedCommands;
  final int defaultSampleDelayMs;
  final int minSampleDelayMs;
  final int maxSampleDelayMs;
  final int maxScheduleLagMs;
  final double delayAlpha;
  final double backlogCompressionPerPacket;
  final Map<int, int> sampleDelayMsByCommand;

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
    final int defaultDelayMs =
        sampleDelayMsByCommand[cmd] ?? defaultSampleDelayMs;
    final bool isGreenOnlyCmd = cmd == OpenRingGatt.cmdHeartRota ||
        cmd == OpenRingGatt.cmdPpgShoushi ||
        cmd == OpenRingGatt.cmdRealTimePpg;
    final int minDelayForCmd = isGreenOnlyCmd ? 20 : minSampleDelayMs;
    final int maxDelayForCmd = isGreenOnlyCmd ? 60 : maxSampleDelayMs;
    double delayMs = _delayEstimateByCmd[cmd] ?? defaultDelayMs.toDouble();

    final int? lastArrival = _lastArrivalByCmd[cmd];
    if (lastArrival != null) {
      final int interArrivalMs = arrivalMs - lastArrival;
      if (interArrivalMs > 0 && sampleCount > 0) {
        final double observedDelayMs = (interArrivalMs / sampleCount).clamp(
          minDelayForCmd.toDouble(),
          maxDelayForCmd.toDouble(),
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
      minDelayForCmd.toDouble(),
      maxDelayForCmd.toDouble(),
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
