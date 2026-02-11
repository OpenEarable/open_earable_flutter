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

  static const int _defaultSampleDelayMs = 10;
  static const int _minSampleDelayMs = 2;
  static const int _maxSampleDelayMs = 20;
  static const int _maxScheduleLagMs = 80;
  static const double _delayAlpha = 0.22;
  static const double _backlogCompressionPerPacket = 0.18;

  Stream<Map<String, dynamic>>? _sensorDataStream;

  OpenRingSensorHandler({
    required DiscoveredDevice discoveredDevice,
    required BleGattManager bleManager,
    required SensorValueParser sensorValueParser,
  }) : _discoveredDevice = discoveredDevice,
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
      Exception("Can't write sensor config. Earable not connected");
    }

    final sensorConfigBytes = sensorConfig.toBytes();

    await _bleManager.write(
      deviceId: _discoveredDevice.id,
      serviceId: OpenRingGatt.service,
      characteristicId: OpenRingGatt.txChar,
      byteData: sensorConfigBytes,
    );
  }

  Future<List<Map<String, dynamic>>> _parseData(List<int> data) async {
    final byteData = ByteData.sublistView(Uint8List.fromList(data));
    return _sensorValueParser.parse(byteData, []);
  }

  Stream<Map<String, dynamic>> _createSensorDataStream() {
    late final StreamController<Map<String, dynamic>> streamController;
    StreamSubscription<List<int>>? bleSubscription;

    // Monotonic clock for all timing decisions.
    final clock = Stopwatch()..start();

    // Keep command families independent (PPG should not stall IMU).
    final Map<int, Future<void>> processingQueueByCmd = {};

    final Map<int, int> lastArrivalByCmd = {};
    final Map<int, double> delayEstimateByCmd = {};
    final Map<int, int> nextDueByCmd = {};
    final Map<int, int> emittedTimestampByCmd = {};
    final Map<int, int> pendingPacketsByCmd = {};

    int _resolveStepMs({
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

    void _decrementPending(int key) {
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
            if (!streamController.isClosed) {
              streamController.add(sample);
            }
          }
          return;
        }

        final int stepMs = _resolveStepMs(
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

          final int previousTs = emittedTimestampByCmd[cmdKey] ?? 0;
          final int nextTs = previousTs + stepMs;
          emittedTimestampByCmd[cmdKey] = nextTs;
          sample['timestamp'] = nextTs;

          if (!streamController.isClosed) {
            streamController.add(sample);
          }

          final int emitNow = clock.elapsedMilliseconds;
          nextDueMs = math.max(nextDueMs, emitNow) + stepMs;
        }

        nextDueByCmd[cmdKey] = nextDueMs;
      } finally {
        if (cmdKey != null) {
          _decrementPending(cmdKey);
        }
        if (rawCmd != null && rawCmd != cmdKey) {
          _decrementPending(rawCmd);
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

          if (subscription != null) {
            unawaited(subscription.cancel());
          }
        }
      },
    );

    return streamController.stream;
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
